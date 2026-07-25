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
