# 工具函数
# API 字段名（mime_type/inline_data 等）保持英文

function Get-Mime类型 {
    param([string]$路径)
    switch ([System.IO.Path]::GetExtension($路径).ToLowerInvariant()) {
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif'  { 'image/gif' }
        '.webp' { 'image/webp' }
        default { 'application/octet-stream' }
    }
}

function Get-图像数据 {
    <#
    .SYNOPSIS
        从本地路径或 URL 获取图像字节和文件名。
    #>
    param([string]$来源)
    if ($来源 -match '^https?://') {
        try { $响应 = Invoke-WebRequest -Uri $来源 -TimeoutSec 60 -ErrorAction Stop }
        catch { throw "下载图像失败（$来源）：$($_.Exception.Message)" }
        $文件名 = [System.IO.Path]::GetFileName($来源.Split('?')[0])
        if (-not $文件名 -or $文件名 -eq '') { $文件名 = 'image.png' }
        # 强制包成数组，避免单字节时管道展平为标量
        return @(, @{ 字节 = ([byte[]]$响应.Content); 文件名 = $文件名 })
    }
    $解析后 = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($来源)
    if (-not (Test-Path -LiteralPath $解析后 -PathType Leaf)) {
        throw "参考图不存在：$来源"
    }
    return @{ 字节 = [System.IO.File]::ReadAllBytes($解析后); 文件名 = [System.IO.Path]::GetFileName($解析后) }
}

function Read-提示文件 {
    param([string]$路径)
    if (-not (Test-Path -LiteralPath $路径 -PathType Leaf)) {
        throw "提示文件不存在：$路径"
    }
    $内容 = [System.IO.File]::ReadAllText(
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($路径),
        [System.Text.Encoding]::UTF8).Trim()
    if ([string]::IsNullOrWhiteSpace($内容)) {
        throw "提示文件内容为空：$路径"
    }
    return $内容
}

function Resolve-输出路径 {
    param([string]$输出路径)
    $解析后 = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($输出路径)
    $目录 = Split-Path -Parent $解析后
    if ($目录 -and -not (Test-Path $目录)) {
        New-Item -ItemType Directory -Path $目录 -Force | Out-Null
    }
    return $解析后
}

function Get-NetException详情 {
    <#
    .SYNOPSIS
        递归展开 .NET 异常链，提取真实的 HTTP 错误内容。
    .DESCRIPTION
        PowerShell 5.1 调用 .NET 方法抛出的异常会被包装成 MethodInvocationException，
        HttpClient 在服务端报错且关闭连接时常抛 TaskCanceledException（"A task was canceled"），
        而真实的服务器错误（状态码 + 响应体 JSON）位于内部 WebException 的 Response 流中。
        本函数沿 InnerException 链逐层展开，找到带 Response 的 WebException 并读取其内容；
        找不到时拼接整条异常链的消息，避免只报 "A task was canceled" 而无细节。
    .PARAMETER Exception
        最外层异常对象（通常是 MethodInvocationException 或 TaskCanceledException）。
    #>
    param([Exception]$Exception)

    # 逐层展开，优先找带 HTTP 响应的 WebException
    $当前 = $Exception
    $深度 = 0
    while ($当前 -and $深度 -lt 8) {
        if ($当前 -is [System.Net.WebException] -and $当前.Response) {
            $响应对象 = $当前.Response
            $响应体 = ''
            try {
                $流 = $响应对象.GetResponseStream()
                if ($流) {
                    $流.Position = 0
                    $响应体 = [System.IO.StreamReader]::new($流).ReadToEnd()
                }
            }
            catch { }
            if ([string]::IsNullOrWhiteSpace($响应体)) { $响应体 = $当前.Message }
            $状态码 = ''
            $状态码属性 = $响应对象.PSObject.Properties['StatusCode']
            if ($状态码属性) { $状态码 = "HTTP $([int]$状态码属性.Value): " }
            return "$状态码$响应体"
        }
        $深度++
        $当前 = $当前.InnerException
    }

    # 未找到 WebException：拼接整条异常链的消息
    $消息列表 = [System.Collections.Generic.List[string]]::new()
    $当前 = $Exception
    $深度 = 0
    while ($当前 -and $深度 -lt 8) {
        $消息列表.Add($当前.Message)
        $深度++
        $当前 = $当前.InnerException
    }
    return ($消息列表 -join ' -> ')
}
