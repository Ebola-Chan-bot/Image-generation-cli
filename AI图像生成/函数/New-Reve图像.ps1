function New-Reve图像 {
    <#
    .SYNOPSIS
        通过 Reve 2.1 中转站（Atlas Cloud 统一协议）生成图像。
    .DESCRIPTION
        走 Atlas Cloud 统一图像接口（POST /api/v1/model/generateImage）调用 Reve 2.1。
        任务为异步提交：优先使用同步模式（enable_sync_mode）等待结果；若中转站
        未完成即返回，将自动轮询 prediction 接口直到出图或超时。
        密钥、基础地址与模型以 DPAPI 加密记住。

        模型变体自动选择（未显式指定 -模型 时）：
        - 无 -参考图：使用 reve-ai/reve-2.1/text-to-image（纯文生图）。
        - 1 张 -参考图：使用 reve-ai/reve-2.1/edit（图像编辑），提示词为编辑指令。
        - 2~6 张 -参考图：使用 reve-ai/reve-2.1/remix（多图融合），提示词中用
          <frame>0</frame>、<frame>1</frame> 等引用对应序号的参考图。

        Atlas Cloud 的 effects 效果后处理（颗粒、光斑等 51 种）暂未开放参数。
    .PARAMETER 提示词
        图像描述（最长 4000 字符）。与 -提示文件 二选一。
    .PARAMETER 提示文件
        提示词文本文件路径。与 -提示词 二选一。
    .PARAMETER 密钥
        交互式输入密钥开关。指定此开关时会提示输入。
    .PARAMETER 密钥值
        API 令牌明文。未指定时查找已记住的值。
    .PARAMETER 基础地址
        中转站 Base URL。默认 https://api.atlascloud.ai。
    .PARAMETER 模型
        完整模型 ID。未指定时按参考图数量自动选择：
        0 张 → text-to-image，1 张 → edit，2 张以上 → remix。
    .PARAMETER 参考图
        参考图像路径或 URL，1~6 张。
        1 张时走 edit（编辑指令式提示词）；2 张以上走 remix，
        提示词中用 <frame>N</frame> 引用（N 从 0 开始）。
    .PARAMETER 宽高比
        auto | 4:1 | 3:1 | 21:9 | 2:1 | 17:9 | 16:9 | 3:2 | 4:3 | 5:4 | 1:1 | 4:5 | 3:4 | 2:3 | 9:16 | 1:2 | 1:3 | 1:4。默认 auto。
    .PARAMETER 去背景
        移除背景，仅保留中央主体并输出透明背景。
    .PARAMETER 输出路径
        输出文件路径。默认时间戳 PNG。扩展名决定 output_format（.jpg/.jpeg → jpeg，.webp → webp，其余 png）；-去背景 时强制 png。
    .PARAMETER 超时秒数
        提交与轮询的总超时，默认 300。
    .PARAMETER 轮询间隔秒数
        轮询 prediction 接口的间隔，默认 3。
    .EXAMPLE
        New-Reve图像 -提示词 "水彩柴犬" -密钥值 'sk-xxx'
    .EXAMPLE
        New-Reve图像 -提示词 "让人物穿上宇航服" -参考图 .\照片.jpg
    .EXAMPLE
        New-Reve图像 -提示词 "<frame>0</frame> 中的人物穿上宇航服，站在 <frame>1</frame> 的场景里" -参考图 .\人物.jpg, .\场景.jpg
    .EXAMPLE
        New-Reve图像 -提示词 "logo 图标" -宽高比 1:1 -去背景
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
        [ValidateNotNullOrEmpty()]
        [string[]]$参考图,

        [Parameter()][string]$宽高比 = 'auto',

        [Parameter()]
        [switch]$去背景,

        [Parameter()]
        [string]$输出路径 = ".\reve_$(Get-Date -Format 'yyyyMMdd_HHmmss').png",

        [Parameter()][int]$超时秒数 = 300,

        [Parameter()][ValidateRange(1, 30)]
        [int]$轮询间隔秒数 = 3
    )

    $配置路径 = Join-Path $env:LOCALAPPDATA 'Image-generation-cli\AI图像生成-Reve配置.xml'

    # 提示词
    if ($PSCmdlet.ParameterSetName -eq '提示文件') {
        $提示词 = Read-提示文件 -路径 $提示文件
    }
    if ($提示词.Length -gt 4000) {
        throw "提示词过长：$($提示词.Length) 字符，Reve 上限为 4000 字符。"
    }

    # 凭据
    if ($密钥.IsPresent -and -not $密钥值) {
        $安全密钥 = Read-Host -Prompt '请输入 API 密钥' -AsSecureString
        $密钥值 = [System.Net.NetworkCredential]::new([string]::Empty, $安全密钥).Password
    }
    $记住的配置 = Import-记住的配置 -配置路径 $配置路径

    # 基础地址默认值
    if (-not $基础地址 -and -not ($记住的配置 -and $记住的配置.基础地址)) {
        $基础地址 = 'https://api.atlascloud.ai'
    }

    # 模型变体自动选择（未显式指定 -模型 时）：0 张 → text-to-image，1 张 → edit，2 张以上 → remix
    if (-not $MyInvocation.BoundParameters.ContainsKey('模型')) {
        if (-not $参考图) { $期望变体 = 'text-to-image' }
        elseif (@($参考图).Count -eq 1) { $期望变体 = 'edit' }
        else { $期望变体 = 'remix' }
        if ($记住的配置 -and $记住的配置.模型) {
            if ($记住的配置.模型 -notlike ('*/' + $期望变体)) {
                $旧模型 = $记住的配置.模型
                $记住的配置.模型 = $旧模型 -replace '/(remix|text-to-image|edit)$', ('/' + $期望变体)
                Write-Host "参考图情况变化，模型自动切换：$旧模型 → $($记住的配置.模型)" -ForegroundColor Yellow
            }
        }
        else {
            $模型 = 'reve-ai/reve-2.1/' + $期望变体
        }
    }

    $凭据 = Resolve-配置凭据 -参数密钥 $密钥值 -参数基础地址 $基础地址 -参数模型 $模型 `
        -记住的配置 $记住的配置 -配置路径 $配置路径

    # 宽高比
    $有效宽高比 = @('auto', '4:1', '3:1', '21:9', '2:1', '17:9', '16:9', '3:2', '4:3', '5:4', '1:1', '4:5', '3:4', '2:3', '9:16', '1:2', '1:3', '1:4')
    if ($宽高比 -and $宽高比 -notin $有效宽高比) {
        throw "宽高比无效：$宽高比。有效值：$($有效宽高比 -join '、')"
    }

    # 参考图：URL 直接透传，本地文件转 base64（单张 ≤40MB，总计 ≤100MB）
    $图像值列表 = [System.Collections.Generic.List[string]]::new()
    if ($参考图) {
        if ($参考图.Count -gt 6) { throw "参考图最多 6 张，当前 $($参考图.Count) 张。" }
        $总数据量 = [long]0
        foreach ($单张 in $参考图) {
            if ($单张 -match '^https?://') {
                $图像值列表.Add($单张)
            }
            else {
                $数据 = Get-图像数据 -来源 $单张
                if ($数据.字节.Length -gt 41943040) { throw "参考图过大（上限 40MB）：$单张" }
                $总数据量 += $数据.字节.Length
                $图像值列表.Add([Convert]::ToBase64String($数据.字节))
            }
        }
        if ($总数据量 -gt 104857600) { throw "参考图总大小超过 100MB 上限。" }
    }

    # 模型与参考图一致性检查
    if ($凭据.模型 -like '*/remix' -and $图像值列表.Count -eq 0) {
        throw "模型 $($凭据.模型) 是 Remix 变体，必须提供至少 1 张 -参考图。"
    }
    if ($凭据.模型 -like '*/edit' -and $图像值列表.Count -ne 1) {
        throw "模型 $($凭据.模型) 是 Edit 变体，必须且只能提供 1 张 -参考图（当前 $($图像值列表.Count)）。如需多张参考图请指定 -模型 'reve-ai/reve-2.1/remix'。"
    }
    if ($凭据.模型 -like '*/text-to-image' -and $图像值列表.Count -gt 0) {
        throw "模型 $($凭据.模型) 是纯文生图变体，不支持参考图。如需编辑请指定 -模型 'reve-ai/reve-2.1/edit'。"
    }

    # 输出格式由扩展名决定；-去背景 需要透明通道，强制 png
    $输出扩展名 = [System.IO.Path]::GetExtension($输出路径).ToLowerInvariant()
    $输出格式 = switch ($输出扩展名) {
        '.jpg'  { 'jpeg' }
        '.jpeg' { 'jpeg' }
        '.webp' { 'webp' }
        default { 'png' }
    }
    if ($去背景.IsPresent -and $输出格式 -eq 'jpeg') {
        $输出格式 = 'png'
        $输出路径 = [System.IO.Path]::ChangeExtension($输出路径, '.png')
        Write-Warning "去背景需要透明通道，输出已改为 png：$输出路径"
    }

    # 端点
    if ($凭据.基础地址 -match '/api/v\d+/?$') { $api基础 = $凭据.基础地址.TrimEnd('/') }
    else { $api基础 = $凭据.基础地址.TrimEnd('/') + '/api/v1' }
    $提交端点 = "$api基础/model/generateImage"

    # 请求体（Atlas Cloud 统一图像协议）
    $请求体对象 = [ordered]@{
        model                = $凭据.模型
        prompt               = $提示词
        aspect_ratio         = $宽高比
        output_format        = $输出格式
        enable_base64_output = $true
        enable_sync_mode     = $true
    }
    if ($图像值列表.Count -gt 0) {
        if ($凭据.模型 -like '*/edit') {
            # Edit 变体使用单数字段 image（URL 或 base64 字符串）
            $请求体对象['image'] = $图像值列表[0]
        }
        else {
            $图像值数组 = $图像值列表.ToArray()
            $请求体对象['images'] = $图像值数组
        }
    }
    if ($去背景.IsPresent) { $请求体对象['remove_background'] = $true }

    $请求体 = $请求体对象 | ConvertTo-Json -Depth 10
    $请求头 = @{ 'Authorization' = "Bearer $($凭据.密钥明文)"; 'Content-Type' = 'application/json' }

    Write-Host "正在调用 $($凭据.模型) 生成图像（原生 4K，通常需要数十秒）..." -ForegroundColor Cyan

    try {
        $响应 = Invoke-RestMethod -Uri $提交端点 -Method Post -Headers $请求头 `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($请求体)) -TimeoutSec $超时秒数
    }
    catch {
        $错误详情 = $_.Exception.Message
        $错误详对象 = $_.ErrorDetails
        if ($错误详对象 -and $错误详对象.PSObject.Properties['Message'] -and $错误详对象.Message) {
            $错误详情 = $错误详对象.Message
        }
        if ($错误详情 -match '(Invalid token|Unauthorized|Invalid API key|Authentication|401)') {
            throw "API 请求失败：密钥无效或已过期。请使用 -密钥值 '新密钥' 或 -密钥 交互式输入。`n原始错误：$错误详情"
        }
        throw "API 请求失败：$错误详情"
    }

    # 记住凭据
    if ($凭据.密钥来源 -ne '已记住' -or $凭据.基础地址来源 -ne '已记住' -or $凭据.模型来源 -ne '已记住') {
        try {
            Save-配置 -安全密钥 $凭据.安全密钥对象 -保存基础地址 $凭据.基础地址 -保存模型 $凭据.模型 -配置路径 $配置路径
            Write-Host "密钥、基础地址与模型已记住：$配置路径" -ForegroundColor DarkGray
        }
        catch { Write-Warning "配置保存失败：$($_.Exception.Message)" }
    }

    # 响应外层 code 检查
    $code属性 = $响应.PSObject.Properties['code']
    if ($code属性 -and $code属性.Value -ne 0 -and $code属性.Value -ne 200) {
        $message属性 = $响应.PSObject.Properties['message']
        $message = if ($message属性 -and $message属性.Value) { $message属性.Value } else { '' }
        throw "API 返回失败（code=$($code属性.Value)）：$message"
    }
    $data属性 = $响应.PSObject.Properties['data']
    $数据 = if ($data属性) { $data属性.Value } else { $null }
    if (-not $数据) {
        $响应预览 = $(try { $响应 | ConvertTo-Json -Depth 6 -Compress } catch { (Out-String -InputObject $响应) })
        throw "响应中没有 data 字段：$响应预览"
    }

    $任务ID属性 = $数据.PSObject.Properties['id']
    if (-not $任务ID属性 -or -not $任务ID属性.Value) {
        throw "响应中没有任务 ID：$($数据 | ConvertTo-Json -Depth 6 -Compress)"
    }
    $任务ID = $任务ID属性.Value

    # 状态与 outputs
    $状态 = ''
    $状态属性 = $数据.PSObject.Properties['status']
    if ($状态属性 -and $状态属性.Value) { $状态 = $状态属性.Value }
    $输出列表 = $null
    $输出属性 = $数据.PSObject.Properties['outputs']
    if ($输出属性 -and $输出属性.Value) { $输出列表 = @($输出属性.Value) }

    # 同步模式未完成时自动轮询
    $轮询端点 = "$api基础/model/prediction/$任务ID"
    $计时器 = [System.Diagnostics.Stopwatch]::StartNew()
    while ($状态 -notin @('completed', 'succeeded', 'failed', 'timeout')) {
        if ($计时器.Elapsed.TotalSeconds -gt $超时秒数) {
            throw "生成超时（$超时秒数 秒）。任务 ID：$任务ID，可稍后用 GET $轮询端点 继续查询。"
        }
        Start-Sleep -Seconds $轮询间隔秒数
        try {
            $查询 = Invoke-RestMethod -Uri $轮询端点 -Headers @{ 'Authorization' = "Bearer $($凭据.密钥明文)" } -TimeoutSec 30
        }
        catch {
            throw "轮询任务状态失败：$($_.Exception.Message)"
        }
        $查询data属性 = $查询.PSObject.Properties['data']
        if (-not $查询data属性 -or -not $查询data属性.Value) { continue }
        # 用最新一次查询的数据覆盖，保证后续错误/输出解析基于最终状态
        $数据 = $查询data属性.Value
        $查询状态属性 = $数据.PSObject.Properties['status']
        if ($查询状态属性 -and $查询状态属性.Value) { $状态 = $查询状态属性.Value }
        $查询输出属性 = $数据.PSObject.Properties['outputs']
        if ($查询输出属性 -and $查询输出属性.Value) { $输出列表 = @($查询输出属性.Value) }
    }

    if ($状态 -in @('failed', 'timeout')) {
        $失败信息 = ''
        $错误属性 = $数据.PSObject.Properties['error']
        if ($错误属性 -and $错误属性.Value) { $失败信息 = $错误属性.Value }
        throw "图像生成失败（status=$状态）：$失败信息 （任务 ID：$任务ID）"
    }

    if (-not $输出列表 -or $输出列表.Count -eq 0) {
        throw "任务完成但没有输出内容：$($数据 | ConvertTo-Json -Depth 6 -Compress)"
    }

    # NSFW 检查
    $nsfw属性 = $数据.PSObject.Properties['has_nsfw_contents']
    if ($nsfw属性 -and $nsfw属性.Value -and @($nsfw属性.Value).Count -gt 0 -and @($nsfw属性.Value)[0] -eq $true) {
        throw "生成内容被判定为 NSFW 而拒绝返回。请修改提示词后重试。"
    }

    # 耗时信息
    $耗时属性 = $数据.PSObject.Properties['executionTime']
    if ($耗时属性 -and $耗时属性.Value) {
        Write-Host "远端耗时: $([math]::Round($耗时属性.Value / 1000, 1)) 秒" -ForegroundColor DarkGray
    }

    # 保存输出。已实测确认（enable_base64_output=true）：outputs[0] 为
    # "data:image/png;base64,<base64>" 形式的字符串（见 测试\探测-AtlasCloud输出格式.ps1）
    $输出内容 = "$($输出列表[0])".Trim()

    $解析后输出 = Resolve-输出路径 -输出路径 $输出路径
    if ($输出内容 -match '^data:image/[a-zA-Z0-9.+-]+;base64,') {
        $b64部分 = $输出内容.Substring($输出内容.IndexOf(',') + 1)
        [System.IO.File]::WriteAllBytes($解析后输出, [Convert]::FromBase64String($b64部分))
    }
    else {
        $预览长度 = [Math]::Min(300, $输出内容.Length)
        throw "输出内容不是预期的 data:image/*;base64 格式，无法保存。前 $预览长度 字符预览：`n$($输出内容.Substring(0, $预览长度))"
    }
    Write-Host "图像已保存: $解析后输出" -ForegroundColor Green
    return $解析后输出
}
