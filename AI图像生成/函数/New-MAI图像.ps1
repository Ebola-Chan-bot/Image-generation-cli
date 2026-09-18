function New-MAI图像 {
    <#
    .SYNOPSIS
        调用微软 MAI 图像模型生成图像。
    .DESCRIPTION
        走 OpenRouter 统一图像接口（POST /api/v1/images）调用 MAI-Image
        （microsoft/mai-image，由 Azure AI Foundry 提供服务）。
        图像以 base64 返回（data[0].b64_json），media_type 标识实际格式（通常为 PNG）。
        密钥、基础地址与模型以 DPAPI 加密记住。计费为全包制：成功出图整张计费，失败不计费。

        mai-image 端点能力：
        - 参考图（input_references）：最多 1 张。
        - 宽高比：仅 1:1、4:3、3:4、16:9、9:16、3:2、2:3、auto。
        - 单次出图张数（n）：固定 1。
        - 上游 Azure 限制：宽高各 ≥768，总像素 ≤1,048,576（约 1024×1024），输出固定 PNG。
    .PARAMETER 提示词
        图像描述。与 -提示文件 二选一。
    .PARAMETER 提示文件
        提示词文本文件路径。与 -提示词 二选一。
    .PARAMETER 密钥
        交互式输入密钥开关。指定此开关时会提示输入（OpenRouter 密钥形如 sk-or-...）。
    .PARAMETER 密钥值
        API 令牌明文。未指定时查找已记住的值。
    .PARAMETER 基础地址
        OpenRouter Base URL。默认 https://openrouter.ai。
    .PARAMETER 模型
        OpenRouter 模型 ID。默认 microsoft/mai-image-2.5。
    .PARAMETER 参考图
        参考图像路径或 URL，用于图生图编辑（input_references）。
        mai-image 端点最多支持 1 张；
        本地文件自动转为 base64 data URI，URL 直接透传。
    .PARAMETER 宽高比
        mai-image 支持：1:1 | 4:3 | 3:4 | 16:9 | 9:16 | 3:2 | 2:3 | auto。默认不发送。
    .PARAMETER 尺寸
        分辨率档位（512 | 1K | 2K | 4K）或精确像素 WxH。默认不发送。
    .PARAMETER 数量
        一次生成几张（1~10，并非所有上游支持 >1）。默认 1。
    .PARAMETER 输出路径
        输出文件路径。默认时间戳 PNG。多张时自动追加序号。
    .PARAMETER 超时秒数
        超时时间，默认 500。
    .EXAMPLE
        New-MAI图像 -提示词 "水彩柴犬" -密钥值 'sk-or-xxx'
    .EXAMPLE
        New-MAI图像 -提示词 "把这张照片改成吉卜力动画风格" -参考图 .\照片.png
    .EXAMPLE
        New-MAI图像 -提示词 "电影海报" -宽高比 16:9 -数量 2
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

        [Parameter()][string]$宽高比 = '',
        [Parameter()][string]$尺寸 = '',

        [Parameter()][ValidateRange(1, 10)]
        [int]$数量 = 1,

        [Parameter()]
        [string]$输出路径 = ".\mai_$(Get-Date -Format 'yyyyMMdd_HHmmss').png",

        [Parameter()][int]$超时秒数 = 500
    )

    $配置路径 = Join-Path $env:LOCALAPPDATA 'Image-generation-cli\AI图像生成-MAI配置.xml'

    # 提示词
    if ($PSCmdlet.ParameterSetName -eq '提示文件') {
        $提示词 = Read-提示文件 -路径 $提示文件
    }

    # 凭据
    if ($密钥.IsPresent -and -not $密钥值) {
        $安全密钥 = Read-Host -Prompt '请输入 OpenRouter API 密钥（sk-or-...）' -AsSecureString
        $密钥值 = [System.Net.NetworkCredential]::new([string]::Empty, $安全密钥).Password
    }
    $记住的配置 = Import-记住的配置 -配置路径 $配置路径

    # 默认值：基础地址与模型
    if (-not $基础地址 -and -not ($记住的配置 -and $记住的配置.基础地址)) {
        $基础地址 = 'https://openrouter.ai'
    }
    if (-not $MyInvocation.BoundParameters.ContainsKey('模型') -and -not ($记住的配置 -and $记住的配置.模型)) {
        $模型 = 'microsoft/mai-image-2.5'
    }

    $凭据 = Resolve-配置凭据 -参数密钥 $密钥值 -参数基础地址 $基础地址 -参数模型 $模型 `
        -记住的配置 $记住的配置 -配置路径 $配置路径

    # 端点：基础地址已带 /api/vN 后缀则直接拼 images，否则补 /api/v1
    if ($凭据.基础地址 -match '/api/v\d+/?$') { $api基础 = $凭据.基础地址.TrimEnd('/') }
    else { $api基础 = $凭据.基础地址.TrimEnd('/') + '/api/v1' }
    $端点 = "$api基础/images"

    # 参考图：URL 直接透传，本地文件编码为 base64 data URI
    $参考引用列表 = [System.Collections.Generic.List[object]]::new()
    if ($参考图) {
        foreach ($单张 in $参考图) {
            if ($单张 -match '^https?://') { $引用URL = $单张 }
            else {
                $数据 = Get-图像数据 -来源 $单张
                $mime = Get-Mime类型 -路径 $数据.文件名
                if ($mime -eq 'application/octet-stream') {
                    throw "参考图格式无法识别：$单张"
                }
                $引用URL = "data:$mime;base64," + [Convert]::ToBase64String($数据.字节)
            }
            $参考引用列表.Add(@{ type = 'image_url'; image_url = @{ url = $引用URL } })
        }
    }

    # 请求体（OpenRouter Image API）
    $请求体对象 = [ordered]@{
        model  = $凭据.模型
        prompt = $提示词
    }
    if ($参考引用列表.Count -gt 0) {
        $参考引用数组 = $参考引用列表.ToArray()
        $请求体对象['input_references'] = $参考引用数组
    }
    if ($宽高比) { $请求体对象['aspect_ratio'] = $宽高比 }
    if ($尺寸) { $请求体对象['size'] = $尺寸 }
    if ($数量 -gt 1) { $请求体对象['n'] = $数量 }

    $请求体 = $请求体对象 | ConvertTo-Json -Depth 10
    $请求头 = @{ 'Authorization' = "Bearer $($凭据.密钥明文)"; 'Content-Type' = 'application/json' }

    Write-Host "正在调用 $($凭据.模型) 生成图像 ..." -ForegroundColor Cyan

    try {
        $响应 = Invoke-RestMethod -Uri $端点 -Method Post -Headers $请求头 `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($请求体)) -TimeoutSec $超时秒数
    }
    catch {
        # ErrorDetails 非空时即为服务端响应体；否则展开异常链提取。
        # 不翻译、不包装，原样抛出。
        $错误详对象 = $_.ErrorDetails
        if ($错误详对象 -and $错误详对象.PSObject.Properties['Message'] -and $错误详对象.Message) {
            $错误详情 = $错误详对象.Message
        }
        else {
            $错误详情 = Get-NetException详情 -Exception $_.Exception
        }
        throw $错误详情
    }

    # 记住凭据
    if ($凭据.密钥来源 -ne '已记住' -or $凭据.基础地址来源 -ne '已记住' -or $凭据.模型来源 -ne '已记住') {
        try {
            Save-配置 -安全密钥 $凭据.安全密钥对象 -保存基础地址 $凭据.基础地址 -保存模型 $凭据.模型 -配置路径 $配置路径
            Write-Host "密钥、基础地址与模型已记住：$配置路径" -ForegroundColor DarkGray
        }
        catch { Write-Warning "配置保存失败：$($_.Exception.Message)" }
    }

    # 解析响应：data[] 中的 b64_json
    $数据属性 = $响应.PSObject.Properties['data']
    if (-not $数据属性 -or -not $数据属性.Value -or @($数据属性.Value).Count -eq 0) {
        throw "API 未返回图像数据：$($响应 | ConvertTo-Json -Depth 10 -Compress)"
    }
    $图像列表 = @($数据属性.Value)

    # 费用信息
    $usage属性 = $响应.PSObject.Properties['usage']
    if ($usage属性 -and $usage属性.Value) {
        $费用属性 = $usage属性.Value.PSObject.Properties['cost']
        if ($费用属性 -and $费用属性.Value -ne $null) {
            # PS 5.1 的 ConvertFrom-Json 数字可能为对象，先转字符串再转 double
            Write-Host ("本次费用: $" + [double]"$($费用属性.Value)") -ForegroundColor DarkGray
        }
    }

    # 保存输出：media_type 决定扩展名；多张时追加序号
    $解析后输出 = Resolve-输出路径 -输出路径 $输出路径
    $序号 = 0
    $保存路径列表 = @()
    foreach ($图像 in $图像列表) {
        $序号++
        $当前路径 = $解析后输出
        if ($图像列表.Count -gt 1) {
            $无扩展名 = [System.IO.Path]::GetFileNameWithoutExtension($解析后输出)
            $扩展名 = [System.IO.Path]::GetExtension($解析后输出)
            $当前路径 = Join-Path (Split-Path -Parent $解析后输出) "${无扩展名}_${序号}${扩展名}"
            $目录 = Split-Path -Parent $当前路径
            if ($目录 -and -not (Test-Path $目录)) { New-Item -ItemType Directory -Path $目录 -Force | Out-Null }
        }

        # 若 media_type 与文件扩展名不一致，按实际格式调整扩展名
        $media属性 = $图像.PSObject.Properties['media_type']
        if ($media属性 -and $media属性.Value) {
            $实际扩展名 = switch ($media属性.Value) {
                'image/jpeg' { '.jpg' }
                'image/webp' { '.webp' }
                'image/gif'  { '.gif' }
                'image/png'  { '.png' }
                default      { [System.IO.Path]::GetExtension($当前路径) }
            }
            if ($实际扩展名 -and [System.IO.Path]::GetExtension($当前路径) -ne $实际扩展名) {
                $当前路径 = [System.IO.Path]::ChangeExtension($当前路径, $实际扩展名)
            }
        }

        $b64属性 = $图像.PSObject.Properties['b64_json']
        if (-not $b64属性 -or -not $b64属性.Value) {
            throw "第 $序号 张图像缺少 b64_json：$($图像 | ConvertTo-Json -Depth 5 -Compress)"
        }
        [System.IO.File]::WriteAllBytes($当前路径, [Convert]::FromBase64String($b64属性.Value))
        Write-Host "图像已保存: $当前路径" -ForegroundColor Green
        $保存路径列表 += $当前路径
    }

    if ($保存路径列表.Count -eq 1) { return $保存路径列表[0] }
    return $保存路径列表
}
