# 配置管理：DPAPI 加密存储凭据
# API 字段名（密钥/基础地址/模型）保持英文

function Import-记住的配置 {
    param([string]$配置路径)
    if (-not (Test-Path $配置路径)) { return $null }
    try { return Import-Clixml -Path $配置路径 }
    catch {
        Write-Warning "无法读取已记住的配置（$配置路径）：$($_.Exception.Message)"
        return $null
    }
}

function Save-配置 {
    param(
        [Parameter(Mandatory = $true)][System.Security.SecureString]$安全密钥,
        [Parameter(Mandatory = $true)][string]$保存基础地址,
        [Parameter(Mandatory = $true)][string]$保存模型,
        [Parameter(Mandatory = $true)][string]$配置路径
    )
    $配置目录 = Split-Path -Parent $配置路径
    if (-not (Test-Path $配置目录)) {
        New-Item -ItemType Directory -Path $配置目录 -Force | Out-Null
    }
    [pscustomobject]@{ 密钥 = $安全密钥; 基础地址 = $保存基础地址; 模型 = $保存模型 } |
        Export-Clixml -Path $配置路径 -Force
}

function Resolve-配置凭据 {
    <#
    .SYNOPSIS
        解析密钥/基础地址/模型：参数 > 已记住 > 交互/报错
    #>
    param(
        [string]$参数密钥,
        [string]$参数基础地址,
        [string]$参数模型,
        [object]$记住的配置,
        [string]$配置路径
    )

    # 密钥（注意：属性可能不存在，必须用 PSObject.Properties 防护，否则严格模式抛异常）
    $密钥来源 = $null
    $安全密钥对象 = $null
    $已记住密钥 = if ($记住的配置 -and $记住的配置.PSObject.Properties['密钥']) { $记住的配置.密钥 } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($参数密钥)) {
        $安全密钥对象 = ConvertTo-SecureString -String $参数密钥 -AsPlainText -Force
        $密钥来源 = '参数'
    }
    elseif ($已记住密钥) {
        $安全密钥对象 = $已记住密钥
        $密钥来源 = '已记住'
    }
    else {
        $输入密钥 = Read-Host -Prompt '请输入 API 密钥（sk-...）' -AsSecureString
        if ($输入密钥.Length -eq 0) { throw '未提供 API 密钥。' }
        $安全密钥对象 = $输入密钥
        $密钥来源 = '交互输入'
    }
    $密钥明文 = [System.Net.NetworkCredential]::new([string]::Empty, $安全密钥对象).Password

    # 基础地址（同样防护属性不存在）
    $基础地址来源 = $null
    $已记住基础地址 = if ($记住的配置 -and $记住的配置.PSObject.Properties['基础地址']) { $记住的配置.基础地址 } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($参数基础地址)) {
        $基础地址来源 = '参数'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($已记住基础地址)) {
        $参数基础地址 = $已记住基础地址
        $基础地址来源 = '已记住'
    }
    else {
        throw "未指定基础地址，且没有已记住的基础地址。请通过 -基础地址 参数指定，调用成功后将被记住。"
    }

    # 模型
    $模型来源 = $null
    if (-not [string]::IsNullOrWhiteSpace($参数模型)) {
        $模型来源 = '参数'
    }
    elseif ($记住的配置 -and $记住的配置.PSObject.Properties['模型'] -and -not [string]::IsNullOrWhiteSpace($记住的配置.模型)) {
        $参数模型 = $记住的配置.模型
        $模型来源 = '已记住'
    }
    else {
        throw "未指定模型，且没有已记住的模型。请通过 -模型 参数指定，调用成功后将被记住。"
    }

    [pscustomobject]@{
        安全密钥对象 = $安全密钥对象
        密钥明文     = $密钥明文
        基础地址     = $参数基础地址
        模型         = $参数模型
        密钥来源     = $密钥来源
        基础地址来源 = $基础地址来源
        模型来源     = $模型来源
    }
}
