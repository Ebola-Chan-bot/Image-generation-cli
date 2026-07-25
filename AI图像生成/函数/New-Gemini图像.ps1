function New-Gemini图像 {
    <#
    .SYNOPSIS
        调用 Gemini 图像模型生成图像。
    .DESCRIPTION
        通过 Gemini generateContent 接口生成图像，自动从响应 parts 提取 base64 图像。
        密钥、基础地址与模型以 DPAPI 加密记住。网页搜索与图片搜索默认开启。
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
    .PARAMETER 输出路径
        输出文件路径。默认时间戳 PNG。
    .PARAMETER 超时秒数
        超时时间，默认 300。
    .PARAMETER 参考图
        参考图像路径（可多张）。
    .PARAMETER 宽高比
        1:1 | 16:9 | 9:16 等。默认不指定。
    .PARAMETER 分辨率
        1K | 2K | 4K。默认不指定。
    .EXAMPLE
        New-Gemini图像 -提示词 "水彩柴犬" -密钥 'sk-xxx' -基础地址 'https://ssvip.dmxapi.com/v1' -模型 'gemini-3.1-flash-image-preview'
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
        [string]$输出路径 = ".\gemini_$(Get-Date -Format 'yyyyMMdd_HHmmss').png",

        [Parameter()][int]$超时秒数 = 300,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$参考图,

        [Parameter()][string]$宽高比 = '',
        [Parameter()][string]$分辨率 = ''
    )

    $配置路径 = Join-Path $env:LOCALAPPDATA 'Image-generation-cli\AI图像生成-Gemini配置.xml'

    # 提示词
    if ($PSCmdlet.ParameterSetName -eq '提示文件') {
        $提示词 = Read-提示文件 -路径 $提示文件
    }

    # 凭据
    $记住的配置 = Import-记住的配置 -配置路径 $配置路径
    $凭据 = Resolve-配置凭据 -参数密钥 $密钥 -参数基础地址 $基础地址 -参数模型 $模型 `
        -记住的配置 $记住的配置 -配置路径 $配置路径

    # 参考图（支持本地路径和 URL）
    $参考图数据列表 = @()
    if ($参考图) {
        foreach ($单张 in $参考图) { $参考图数据列表 += Get-图像数据 -来源 $单张 }
    }

    # 宽高比
    $有效宽高比 = @('1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3', '21:9', '5:4', '4:5')
    if ($宽高比 -and $宽高比 -notin $有效宽高比) {
        throw "宽高比无效：$宽高比。有效值：$($有效宽高比 -join '、')"
    }

    # 分辨率
    if ($分辨率 -and $分辨率 -notin @('1K', '2K', '4K')) {
        throw "分辨率无效：$分辨率。有效值：1K、2K、4K"
    }

    # 构造 contents
    $部件列表 = [System.Collections.Generic.List[object]]::new()
    $部件列表.Add(@{ text = $提示词 })
    foreach ($d in $参考图数据列表) {
        $部件列表.Add(@{
                inline_data = @{
                    mime_type = Get-Mime类型 -路径 $d.文件名
                    data      = [Convert]::ToBase64String($d.字节)
                }
            })
    }

    # generationConfig
    $生成配置 = @{ responseModalities = @('TEXT', 'IMAGE') }
    if ($宽高比 -or $分辨率) {
        $图像配置 = @{}
        if ($宽高比) { $图像配置['aspectRatio'] = $宽高比 }
        if ($分辨率) { $图像配置['imageSize'] = $分辨率 }
        $生成配置['imageConfig'] = $图像配置
    }

    # 请求体
    $请求体 = @{
        contents         = @(@{ parts = $部件列表 })
        generationConfig = $生成配置
        safetySettings   = @(
            @{ category = 'HARM_CATEGORY_HARASSMENT';        threshold = 'BLOCK_NONE' },
            @{ category = 'HARM_CATEGORY_HATE_SPEECH';       threshold = 'BLOCK_NONE' },
            @{ category = 'HARM_CATEGORY_SEXUALLY_EXPLICIT'; threshold = 'BLOCK_NONE' },
            @{ category = 'HARM_CATEGORY_DANGEROUS_CONTENT'; threshold = 'BLOCK_NONE' }
        )
        tools            = @(
            @{ google_search = @{ search_types = @{ web_search = @{ }; image_search = @{ } } } }
        )
    } | ConvertTo-Json -Depth 10

    $端点 = "{0}/models/{1}:generateContent" -f $凭据.基础地址.TrimEnd('/'), $凭据.模型
    $请求头 = @{ 'Authorization' = "Bearer $($凭据.密钥明文)"; 'Content-Type' = 'application/json' }

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

    # 记住凭据
    if ($凭据.密钥来源 -ne '已记住' -or $凭据.基础地址来源 -ne '已记住' -or $凭据.模型来源 -ne '已记住') {
        try {
            Save-配置 -安全密钥 $凭据.安全密钥对象 -保存基础地址 $凭据.基础地址 -保存模型 $凭据.模型 -配置路径 $配置路径
            Write-Host "密钥、基础地址与模型已记住：$配置路径" -ForegroundColor DarkGray
        }
        catch { Write-Warning "配置保存失败：$($_.Exception.Message)" }
    }

    # 解析响应
    if (-not $响应.candidates -or $响应.candidates.Count -eq 0) {
        throw "API 未返回候选内容。"
    }
    $候选 = $响应.candidates[0]

    # 安全拦截检查
    $结束原因属性 = $候选.PSObject.Properties['finishReason']
    $结束原因 = if ($结束原因属性 -and $结束原因属性.Value) { $结束原因属性.Value } else { '' }
    $结束消息属性 = $候选.PSObject.Properties['finishMessage']
    $结束消息 = if ($结束消息属性 -and $结束消息属性.Value) { ": $($结束消息属性.Value)" } else { '' }

    if ($结束原因 -eq 'IMAGE_SAFETY') {
        throw "生成的图像被安全过滤器拦截（IMAGE_SAFETY）$结束消息。请修改提示词后重试。"
    }
    if ($结束原因 -eq 'SAFETY') {
        throw "提示词被安全过滤器拦截（SAFETY）$结束消息。请修改提示词后重试。"
    }

    $内容属性 = $候选.PSObject.Properties['content']
    if (-not $内容属性 -or -not $内容属性.Value) {
        if ($结束原因) { throw "模型未生成任何内容（finishReason=$结束原因）$结束消息。请修改提示词后重试。" }
        throw "响应中没有 content 字段。"
    }
    $部件属性 = $内容属性.Value.PSObject.Properties['parts']
    if (-not $部件属性 -or -not $部件属性.Value) {
        if ($结束原因) { throw "模型完成了推理但未生成图像（finishReason=$结束原因）$结束消息。请修改提示词后重试。" }
        throw "响应中没有 content.parts 字段。"
    }
    $部件 = $部件属性.Value

    $图像部件 = $null
    foreach ($单部件 in $部件) {
        if ($单部件.PSObject.Properties['inlineData'] -and $单部件.inlineData) { $图像部件 = $单部件.inlineData; break }
        if ($单部件.PSObject.Properties['inline_data'] -and $单部件.inline_data) { $图像部件 = $单部件.inline_data; break }
    }
    if (-not $图像部件) {
        throw "响应中没有图像数据：$($响应 | ConvertTo-Json -Depth 10 -Compress)"
    }

    foreach ($单部件 in $部件) {
        if ($单部件.PSObject.Properties['text'] -and $单部件.text) {
            Write-Host "模型说明: $($单部件.text)" -ForegroundColor DarkGray
        }
    }

    $解析后输出 = Resolve-输出路径 -输出路径 $输出路径
    [System.IO.File]::WriteAllBytes($解析后输出, [Convert]::FromBase64String($图像部件.data))
    Write-Host "图像已保存: $解析后输出" -ForegroundColor Green
    return $解析后输出
}
