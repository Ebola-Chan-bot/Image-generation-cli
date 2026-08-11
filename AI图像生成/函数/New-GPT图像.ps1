function New-GPT图像 {
    <#
    .SYNOPSIS
        调用 gpt-image-2 模型生成图像。
    .DESCRIPTION
        通过 OpenAI 兼容接口生成图像，自动处理 b64_json / url 两种返回形式。
        密钥、基础地址与模型以 DPAPI 加密记住。
        有参考图时走 images/edits 端点，否则走 images/generations。
    .PARAMETER 提示词
        图像描述。与 -提示文件 二选一。
    .PARAMETER 提示文件
        提示词文本文件路径。与 -提示词 二选一。
    .PARAMETER 密钥
        交互式输入密钥开关。指定此开关时会提示输入。
    .PARAMETER 密钥值
        API 令牌明文。未指定时查找已记住的值。
    .PARAMETER 基础地址
        Base URL。未指定时查找已记住的值。
    .PARAMETER 模型
        模型名。未指定时查找已记住的值。
    .PARAMETER 尺寸
        自定义 WxH 像素（auto 为默认）。需满足：最长边 ≤3840、宽高均为 16 的倍数、长宽比 ≤3:1、总像素 655360~8294400。默认 auto。
    .PARAMETER 质量
        low | medium | high | auto。默认 auto。
    .PARAMETER 输出路径
        输出文件路径。默认时间戳 PNG。
    .PARAMETER 超时秒数
        超时时间，默认 500。
    .PARAMETER 参考图
        参考图像路径或 URL（可多张）。官方限制（OpenAI images/edits，本函数不做本地拦截）：
        GPT 图像模型最多 16 张，每张为小于 50MB 的 png / webp / jpg；dall-e-2 仅支持单张 ≤4MB 方形 png。
        同时指定 -蒙版 时，蒙版仅应用于第一张参考图。
    .PARAMETER 蒙版
        蒙版（mask）图像路径，用于对参考图做局部重绘（inpainting），仅在有参考图时生效；
        提供多张参考图时，蒙版仅应用于第一张。
        语义：透明（alpha=0）区域 = 要重绘的地方；不透明区域 = 保持原样不动。
        要求：1) 必须是 PNG；2) 宽高与参考图像素级一致（不会自动缩放对齐）；3) RGBA 带 alpha 通道。
        提示词只描述透明区域中想要的内容，其余部分模型严格保留参考图原样。
    .EXAMPLE
        New-GPT图像 -提示词 "水彩柴犬" -密钥 'sk-xxx' -基础地址 'https://open.cherryin.net/v1'
    .EXAMPLE
        New-GPT图像 -提示词 "这里改成一顶红色圣诞帽" -参考图 .\立绘.png -蒙版 .\mask.png
    #>
    [CmdletBinding(DefaultParameterSetName = '提示词')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = '提示词')]
        [ValidateNotNullOrEmpty()]
        [string]$提示词,

        [Parameter(Mandatory = $true, ParameterSetName = '提示文件')]
        [ValidateNotNullOrEmpty()]
        [string]$提示文件,

        [Parameter()]
        [switch]$密钥,

        [Parameter()][string]$密钥值,
        [Parameter()][string]$基础地址,
        [Parameter()][string]$模型,

        [Parameter()]
        [string]$尺寸 = 'auto',

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', 'auto')]
        [string]$质量 = 'auto',

        [Parameter()]
        [string]$输出路径 = ".\gpt-image-2_$(Get-Date -Format 'yyyyMMdd_HHmmss').png",

        [Parameter()][int]$超时秒数 = 500,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$参考图,

        [Parameter()][string]$蒙版 = ''
    )

    $配置路径 = Join-Path $env:LOCALAPPDATA 'Image-generation-cli\AI图像生成-GPT配置.xml'

    # 提示词
    if ($PSCmdlet.ParameterSetName -eq '提示文件') {
        $提示词 = Read-提示文件 -路径 $提示文件
    }

    # 凭据
    if ($密钥.IsPresent -and -not $密钥值) {
        $安全密钥 = Read-Host -Prompt '请输入 API 密钥' -AsSecureString
        $密钥值 = [System.Net.NetworkCredential]::new([string]::Empty, $安全密钥).Password
    }
    $记住的配置 = Import-记住的配置 -配置路径 $配置路径
    $凭据 = Resolve-配置凭据 -参数密钥 $密钥值 -参数基础地址 $基础地址 -参数模型 $模型 `
        -记住的配置 $记住的配置 -配置路径 $配置路径

    # 基础地址自动补全 /v1
    if ($凭据.基础地址 -notmatch '/v\d+/?$') {
        $凭据.基础地址 = $凭据.基础地址.TrimEnd('/') + '/v1'
    }

    # 参考图（支持本地路径和 URL）
    $参考图数据列表 = @()
    if ($参考图) {
        foreach ($单张 in $参考图) { $参考图数据列表 += Get-图像数据 -来源 $单张 }
    }

    # 蒙版（支持本地路径和 URL）
    $蒙版数据 = $null
    if ($蒙版) {
        $蒙版数据 = Get-图像数据 -来源 $蒙版
    }

    # 构造请求
    if ($参考图数据列表.Count -gt 0) {
        Add-Type -AssemblyName System.Net.Http
        $端点 = "$($凭据.基础地址.TrimEnd('/'))/images/edits"

        Write-Host "正在调用 $($凭据.模型) 生成图像 ..." -ForegroundColor Cyan

        # 连接中断无限重试：大尺寸/高质量多参考图生成耗时长，
        # 客户端默认 300 秒超时或中转链路易在等待期间断开连接（"A task was canceled"
        # 且无响应体）。仅"无服务端响应体"的传输层中断才重试（退避等待，最长 30 秒）；
        # 成功响应或明确的 HTTP 错误不重试。
        # 重试不产生额外费用：每次调用生成一个幂等键贯穿所有尝试，OpenAI 兼容 API
        # 收到相同 Idempotency-Key 时会复用首次结果而非重新生成，避免重复计费。
        $幂等键 = [guid]::NewGuid().ToString()
        $尝试 = 0
        $表单 = $null
        $客户端 = $null
        $响应 = $null
        while ($true) {
            $尝试++
            if ($尝试 -gt 1) {
                $等待秒数 = [Math]::Min($尝试, 30)
                Write-Host "连接中断，正在等待 $等待秒数 秒后第 $尝试 次重试（幂等键相同，不会重复计费）..." -ForegroundColor Yellow
                Start-Sleep -Seconds $等待秒数
                $表单.Dispose()
                $客户端.Dispose()
            }
            $表单 = [System.Net.Http.MultipartFormDataContent]::new()
            $表单.Add([System.Net.Http.StringContent]::new($凭据.模型), 'model')
            $表单.Add([System.Net.Http.StringContent]::new($提示词), 'prompt')
            $表单.Add([System.Net.Http.StringContent]::new('1'), 'n')
            $表单.Add([System.Net.Http.StringContent]::new('low'), 'moderation')
            if ($尺寸 -ne 'auto') { $表单.Add([System.Net.Http.StringContent]::new($尺寸), 'size') }
            if ($质量 -ne 'auto') { $表单.Add([System.Net.Http.StringContent]::new($质量), 'quality') }
            if ($蒙版数据) {
                $mc = [System.Net.Http.ByteArrayContent]::new($蒙版数据.字节)
                $mc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
                $表单.Add($mc, 'mask', $蒙版数据.文件名)
            }
            $字段名 = $(if ($参考图数据列表.Count -gt 1) { 'image[]' } else { 'image' })
            foreach ($d in $参考图数据列表) {
                $ic = [System.Net.Http.ByteArrayContent]::new($d.字节)
                $ic.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
                $表单.Add($ic, $字段名, $d.文件名)
            }
            $客户端 = [System.Net.Http.HttpClient]::new()
            $客户端.Timeout = [TimeSpan]::FromSeconds($超时秒数)
            $客户端.DefaultRequestHeaders.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $凭据.密钥明文)
            # 幂等键：让上游把本次调用的多次重试视为同一请求，防止重复计费
            if ($客户端.DefaultRequestHeaders.Contains('Idempotency-Key')) {
                $客户端.DefaultRequestHeaders.Remove('Idempotency-Key')
            }
            $客户端.DefaultRequestHeaders.Add('Idempotency-Key', $幂等键)
            try {
                $响应消息 = $客户端.PostAsync($端点, $表单).GetAwaiter().GetResult()
                $响应文本 = $响应消息.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                if (-not $响应消息.IsSuccessStatusCode) {
                    $状态码 = [int]$响应消息.StatusCode
                    throw "HTTP $状态码：$响应文本"
                }
                $响应 = $响应文本 | ConvertFrom-Json
                break  # 成功，跳出重试循环
            }
            catch [System.Management.Automation.MethodInvocationException] {
                # 服务端报错并关闭连接时，HttpClient 常抛 TaskCanceledException（"A task was canceled"），
                # 真实的 HTTP 错误藏在内部 WebException 中——逐层展开提取，而不是只报最外层消息
                $详情 = Get-NetException详情 -Exception $_.Exception
                # 有服务端响应体（形如 "HTTP 4xx: {...}" 或含 error JSON）视为明确错误，直接抛出
                if ($详情 -match '^HTTP \d{3}[：:]' -or $详情 -match '"error"|"code"') {
                    throw "API 请求失败：$详情"
                }
                # 纯粹的传输层中断：无响应体，判定为可重试（无限重试直到成功或明确错误）
                Write-Warning "连接被中断（无服务端响应，可能是生成超时或网络抖动）：$详情"
                continue
            }
            catch { throw "API 请求失败：$($_.Exception.Message)" }
        }
        if ($表单) { $表单.Dispose() }
        if ($客户端) { $客户端.Dispose() }
    }
    else {
        $端点 = "$($凭据.基础地址.TrimEnd('/'))/images/generations"
        $请求头 = @{ 'Authorization' = "Bearer $($凭据.密钥明文)"; 'Content-Type' = 'application/json' }
        $请求体 = @{ model = $凭据.模型; prompt = $提示词; n = 1; moderation = 'low' }
        if ($尺寸 -ne 'auto') { $请求体['size'] = $尺寸 }
        if ($质量 -ne 'auto') { $请求体['quality'] = $质量 }
        $请求体 = $请求体 | ConvertTo-Json -Depth 5

        Write-Host "正在调用 $($凭据.模型) 生成图像 ..." -ForegroundColor Cyan
        try {
            $响应 = Invoke-RestMethod -Uri $端点 -Method Post -Headers $请求头 `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($请求体)) -TimeoutSec $超时秒数
        }
        catch {
            $错误详情 = $_.Exception.Message
            $错误详对象 = $_.ErrorDetails
            if ($错误详对象 -and $错误详对象.PSObject.Properties['Message'] -and $错误详对象.Message) {
                $错误详情 = $错误详对象.Message
            }
            throw "API 请求失败：$错误详情"
        }
    }

    # 记住凭据
    if ($凭据.密钥来源 -ne '已记住' -or $凭据.基础地址来源 -ne '已记住' -or $凭据.模型来源 -ne '已记住') {
        try {
            Save-配置 -安全密钥 $凭据.安全密钥对象 -保存基础地址 $凭据.基础地址 -保存模型 $凭据.模型 -配置路径 $配置路径
            Write-Host "密钥、基础地址与模型已记住：$配置路径" -ForegroundColor DarkGray
        }
        catch { Write-Warning "配置保存失败：$($_.Exception.Message)" }
    }

    # 解析响应
    $数据属性 = $响应.PSObject.Properties['data']
    if (-not $数据属性 -or -not $数据属性.Value -or $数据属性.Value.Count -eq 0) {
        throw "API 未返回图像数据：$($响应 | ConvertTo-Json -Depth 10 -Compress)"
    }
    $图像 = $数据属性.Value[0]
    $改写 = $图像.PSObject.Properties['revised_prompt']
    if ($改写 -and $改写.Value) { Write-Host "改写后的提示词: $($改写.Value)" -ForegroundColor DarkGray }

    $解析后输出 = Resolve-输出路径 -输出路径 $输出路径
    $b64属性 = $图像.PSObject.Properties['b64_json']
    if ($b64属性 -and $b64属性.Value) {
        [System.IO.File]::WriteAllBytes($解析后输出, [Convert]::FromBase64String($b64属性.Value))
    }
    else {
        $url属性 = $图像.PSObject.Properties['url']
        if ($url属性 -and $url属性.Value) {
            Invoke-WebRequest -Uri $url属性.Value -OutFile $解析后输出 -TimeoutSec $超时秒数
        }
        else { throw "响应中既没有 b64_json 也没有 url：$($图像 | ConvertTo-Json -Depth 5 -Compress)" }
    }

    Write-Host "图像已保存: $解析后输出" -ForegroundColor Green
    return $解析后输出
}
