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
        API 令牌。未指定时查找已记住的值。
    .PARAMETER 基础地址
        Base URL。未指定时查找已记住的值。
    .PARAMETER 模型
        模型名。未指定时查找已记住的值。
    .PARAMETER 尺寸
        1024x1024 | 1536x1024 | 1024x1536 | auto。默认 auto。
    .PARAMETER 质量
        low | medium | high | auto。默认 auto。
    .PARAMETER 输出路径
        输出文件路径。默认时间戳 PNG。
    .PARAMETER 超时秒数
        超时时间，默认 300。
    .PARAMETER 参考图
        参考图像路径（可多张）。
    .PARAMETER 背景
        opaque | transparent | auto。默认不指定。
    .PARAMETER 蒙版
        蒙版图像路径。仅在有参考图时生效。
    .EXAMPLE
        New-GPT图像 -提示词 "水彩柴犬" -密钥 'sk-xxx' -基础地址 'https://open.cherryin.net/v1'
    #>
    [CmdletBinding(DefaultParameterSetName = '提示词')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = '提示词')]
        [ValidateNotNullOrEmpty()]
        [string]$提示词,

        [Parameter(Mandatory = $true, ParameterSetName = '提示文件')]
        [ValidateNotNullOrEmpty()]
        [string]$提示文件,

        [Parameter()][string]$密钥,
        [Parameter()][string]$基础地址,
        [Parameter()][string]$模型,

        [Parameter()]
        [ValidateSet('1024x1024', '1536x1024', '1024x1536', 'auto')]
        [string]$尺寸 = 'auto',

        [Parameter()]
        [ValidateSet('low', 'medium', 'high', 'auto')]
        [string]$质量 = 'auto',

        [Parameter()]
        [string]$输出路径 = ".\gpt-image-2_$(Get-Date -Format 'yyyyMMdd_HHmmss').png",

        [Parameter()][int]$超时秒数 = 300,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$参考图,

        [Parameter()][string]$背景 = '',
        [Parameter()][string]$蒙版 = ''
    )

    $配置路径 = Join-Path $env:LOCALAPPDATA 'Image-generation-cli\AI图像生成-GPT配置.xml'

    # 提示词
    if ($PSCmdlet.ParameterSetName -eq '提示文件') {
        $提示词 = Read-提示文件 -路径 $提示文件
    }

    # 凭据
    $记住的配置 = Import-记住的配置 -配置路径 $配置路径
    $凭据 = Resolve-配置凭据 -参数密钥 $密钥 -参数基础地址 $基础地址 -参数模型 $模型 `
        -记住的配置 $记住的配置 -配置路径 $配置路径

    # 参考图
    $参考图路径列表 = @()
    if ($参考图) {
        foreach ($单张 in $参考图) {
            if (-not (Test-Path -LiteralPath $单张 -PathType Leaf)) { throw "参考图不存在：$单张" }
            $参考图路径列表 += $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($单张)
        }
    }

    # 背景
    if ($背景 -and $背景 -notin @('opaque', 'transparent', 'auto')) {
        throw "背景取值无效：$背景。有效值：opaque、transparent、auto"
    }

    # 蒙版
    $蒙版路径 = $null
    if ($蒙版) {
        if (-not (Test-Path -LiteralPath $蒙版 -PathType Leaf)) { throw "蒙版文件不存在：$蒙版" }
        if ($参考图路径列表.Count -eq 0) { throw "蒙版仅在指定 -参考图 时有效。" }
        $蒙版路径 = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($蒙版)
    }

    # 构造请求
    if ($参考图路径列表.Count -gt 0) {
        Add-Type -AssemblyName System.Net.Http
        $端点 = "$($凭据.基础地址.TrimEnd('/'))/images/edits"
        $表单 = [System.Net.Http.MultipartFormDataContent]::new()
        $表单.Add([System.Net.Http.StringContent]::new($凭据.模型), 'model')
        $表单.Add([System.Net.Http.StringContent]::new($提示词), 'prompt')
        $表单.Add([System.Net.Http.StringContent]::new('1'), 'n')
        $表单.Add([System.Net.Http.StringContent]::new('low'), 'moderation')
        if ($尺寸 -ne 'auto') { $表单.Add([System.Net.Http.StringContent]::new($尺寸), 'size') }
        if ($质量 -ne 'auto') { $表单.Add([System.Net.Http.StringContent]::new($质量), 'quality') }
        if ($背景) { $表单.Add([System.Net.Http.StringContent]::new($背景), 'background') }
        if ($蒙版路径) {
            $mc = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes($蒙版路径))
            $mc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
            $表单.Add($mc, 'mask', [System.IO.Path]::GetFileName($蒙版路径))
        }
        $字段名 = $(if ($参考图路径列表.Count -gt 1) { 'image[]' } else { 'image' })
        foreach ($p in $参考图路径列表) {
            $ic = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes($p))
            $ic.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
            $表单.Add($ic, $字段名, [System.IO.Path]::GetFileName($p))
        }

        Write-Host "正在调用 $($凭据.模型) 生成图像 ..." -ForegroundColor Cyan
        $客户端 = [System.Net.Http.HttpClient]::new()
        $客户端.Timeout = [TimeSpan]::FromSeconds($超时秒数)
        $客户端.DefaultRequestHeaders.Authorization =
            [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $凭据.密钥明文)
        try {
            $响应消息 = $客户端.PostAsync($端点, $表单).GetAwaiter().GetResult()
            $响应文本 = $响应消息.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $响应消息.IsSuccessStatusCode) {
                throw "API 请求失败（HTTP $([int]$响应消息.StatusCode)）：$响应文本"
            }
            $响应 = $响应文本 | ConvertFrom-Json
        }
        catch [System.Management.Automation.MethodInvocationException] {
            throw "API 请求失败：$($_.Exception.InnerException.Message)"
        }
        catch { throw "API 请求失败：$($_.Exception.Message)" }
        finally { $表单.Dispose(); $客户端.Dispose() }
    }
    else {
        $端点 = "$($凭据.基础地址.TrimEnd('/'))/images/generations"
        $请求头 = @{ 'Authorization' = "Bearer $($凭据.密钥明文)"; 'Content-Type' = 'application/json' }
        $请求体 = @{ model = $凭据.模型; prompt = $提示词; n = 1; moderation = 'low' }
        if ($尺寸 -ne 'auto') { $请求体['size'] = $尺寸 }
        if ($质量 -ne 'auto') { $请求体['quality'] = $质量 }
        if ($背景) { $请求体['background'] = $背景 }
        $请求体 = $请求体 | ConvertTo-Json -Depth 5

        Write-Host "正在调用 $($凭据.模型) 生成图像 ..." -ForegroundColor Cyan
        try {
            $响应 = Invoke-RestMethod -Uri $端点 -Method Post -Headers $请求头 `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($请求体)) -TimeoutSec $超时秒数
        }
        catch {
            $错误详情 = $_.ErrorDetails.Message
            if (-not $错误详情) { $错误详情 = $_.Exception.Message }
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
    if (-not $响应.data -or $响应.data.Count -eq 0) {
        throw "API 未返回图像数据：$($响应 | ConvertTo-Json -Depth 10 -Compress)"
    }
    $图像 = $响应.data[0]
    $改写 = $图像.PSObject.Properties['revised_prompt']
    if ($改写 -and $改写.Value) { Write-Host "改写后的提示词: $($改写.Value)" -ForegroundColor DarkGray }

    $解析后输出 = Resolve-输出路径 -输出路径 $输出路径
    if ($图像.b64_json) {
        [System.IO.File]::WriteAllBytes($解析后输出, [Convert]::FromBase64String($图像.b64_json))
    }
    elseif ($图像.url) {
        Invoke-WebRequest -Uri $图像.url -OutFile $解析后输出 -TimeoutSec $超时秒数
    }
    else { throw "响应中既没有 b64_json 也没有 url。" }

    Write-Host "图像已保存: $解析后输出" -ForegroundColor Green
    return $解析后输出
}
