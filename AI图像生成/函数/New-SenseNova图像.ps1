function New-SenseNova图像 {
	<#
	.SYNOPSIS
		通过商汤日日新开放平台调用 SenseNova U1 系列图片创作模型生成图像。
	.DESCRIPTION
		走日日新独立图像接口（非 Chat Completions）：
		- 无参考图 → POST /v1/images/generations 文生图
		- 有参考图 → POST /v1/images/edits 图片编辑（输入图 + 编辑指令），第一张为主编辑图
		密钥、基础地址与模型以 DPAPI 加密记住。默认调用官网
		（https://token.sensenova.cn/v1）的旗舰模型（默认 SenseNova U1 Pro，
		当前处于邀测阶段，未开通时请用 -模型 换成 sensenova-u1.5-lite 等已开放模型）。

		接口要点（U1 家族统一协议）：
		- 图像输出统一以 base64 返回（response_format 强制 b64_json），避开
		  url 模式的 24 小时临时链接失效问题。
		- 参考图仅支持公网 http/https URL 或带 "data:image/*;base64," 前缀的
		  Data-URL；本地文件自动转 Data-URL。
		- n 仅支持 1；水印参数显式传（默认无水印，公测期免费，后续转付费特性）。
	.PARAMETER 提示词
		图像描述或编辑指令。与 -提示文件 二选一。
		有参考图时提示词为编辑指令：描述期望的最终画面，尽量保留未指定修改的主体元素。
	.PARAMETER 提示文件
		提示词文本文件路径。与 -提示词 二选一。
	.PARAMETER 密钥
		交互式输入密钥开关。指定此开关时会提示输入。
		平台密钥在 https://platform.sensenova.cn/console/keys 创建。
	.PARAMETER 密钥值
		API 令牌明文。未指定时查找已记住的值。
	.PARAMETER 基础地址
		日日新 Base URL。默认官网 https://token.sensenova.cn/v1。
	.PARAMETER 模型
		日日新平台模型 ID。默认 SenseNova U1 Pro。
		其他可选（按平台开放情况）：sensenova-u1.5-lite、sensenova-u1-fast 等。
		注意：U1 Pro 处于邀测阶段，若调用返回 404 类错误说明当前密钥未开通该模型权限，
		请通过 -模型 更换为已开通的模型。
	.PARAMETER 参考图
		参考图像路径或 URL（可多张，第一张为主编辑图）。
		本地文件自动读取并编码为 Base64 Data-URL（带 data:image/*;base64, 前缀）；
		URL 直接透传（须为公网可访问的 http/https 链接）。
		有参考图时走 /v1/images/edits，否则走 /v1/images/generations。
	.PARAMETER 尺寸
		生成尺寸，支持：
		- auto（默认，自动适配；编辑模式下自动适配主图）
		- 分辨率档位：2K / 4K（平台官方建议档位，U1 Pro 原生支持更高分辨率）
		- 精确像素 WxH（如 2048x2048）：宽高均须为 32 的倍数、介于 512~4096，且长短边之比 ≤3
		本地会校验精确像素规则，避免浪费调用。
	.PARAMETER 输出格式
		png | jpeg | webp。默认 png。仅控制图片格式，不影响返回形式（始终 base64）。
		JPEG 不支持透明背景；WebP 兼顾文件大小与透明背景。
	.PARAMETER 水印
		添加日日新 SenseNova 官方 Logo 水印。默认关闭（公测期无水印免费）。
		官方说明无水印生成后续将转为付费高级特性。
	.PARAMETER 保留提示词
		跳过平台的提示词自动润色优化（prompt_extend）。
		默认不传此开关，由平台自动扩写优化提示词（扩写失败时自动使用原始提示词）。
		适用场景：提示词已精心设计、不希望被模型改写。
		指定后显式传 prompt_extend=false，避免平台未来默认值变更影响行为。
	.PARAMETER 输出路径
		输出文件路径。默认时间戳 PNG。
	.PARAMETER 超时秒数
		单次 HTTP 请求的超时秒数。默认 1800（U1 Pro 的图文交错思维链生成
		需要自主完成草图-细化-着色-检查-调整全流程，耗时远超普通模型）。
		网络抖动重试不受此超时限制，直到成功或服务端给出明确错误。
	.EXAMPLE
		New-SenseNova图像 -提示词 "水彩柴犬" -密钥值 'xxx'
	.EXAMPLE
		New-SenseNova图像 -提示词 "把背景改成雪山，人物保持不变" -参考图 .\照片.png
	.EXAMPLE
		New-SenseNova图像 -提示词 "复杂信息图：神经网络发展史，含大量文字与图表" -尺寸 4K
	.EXAMPLE
		New-SenseNova图像 -提示词 "水彩柴犬" -模型 'sensenova-u1.5-lite' -尺寸 2K -输出格式 webp
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

		[Parameter()][string]$尺寸 = 'auto',

		[Parameter()]
		[ValidateSet('png', 'jpeg', 'webp')]
		[string]$输出格式 = 'png',

		[Parameter()]
		[switch]$水印,

		[Parameter()]
		[switch]$保留提示词,

		[Parameter()]
		[string]$输出路径 = ".\sensenova_$(Get-Date -Format 'yyyyMMdd_HHmmss').png",

		[Parameter()][int]$超时秒数 = 1800
	)

	$配置路径 = Join-Path $env:LOCALAPPDATA 'Image-generation-cli\AI图像生成-SenseNova配置.xml'

	# 提示词
	if ($PSCmdlet.ParameterSetName -eq '提示文件') {
		$提示词 = Read-提示文件 -路径 $提示文件
	}

	# 尺寸本地预校验（官方规则：auto / 2K / 4K / WxH，WxH 需 32 的倍数、512~4096、最大比例 3:1）
	if ($尺寸 -match '^\d+[xX]\d+$') {
		$宽度 = [int]($尺寸.Split('x', 'X')[0])
		$高度 = [int]($尺寸.Split('x', 'X')[1])
		if ($宽度 % 32 -ne 0 -or $高度 % 32 -ne 0) {
			throw "尺寸宽高须为 32 的倍数：当前 ${宽度}x${高度}（宽余 $($宽度 % 32)、高余 $($高度 % 32)）。"
		}
		if ($宽度 -lt 512 -or $宽度 -gt 4096 -or $高度 -lt 512 -or $高度 -gt 4096) {
			throw "尺寸宽高须介于 512~4096 之间：当前 ${宽度}x${高度}。也可改用档位：2K / 4K。"
		}
		$长短边比 = [Math]::Max($宽度, $高度) / [Math]::Min($宽度, $高度)
		if ($长短边比 -gt 3) {
			throw "长短边之比须 ≤3:1（或 1:3）：当前 ${宽度}x${高度}（$([Math]::Round($长短边比, 2)):1）。"
		}
	}

	# 凭据
	if ($密钥.IsPresent -and -not $密钥值) {
		$安全密钥 = Read-Host -Prompt '请输入日日新 API 密钥' -AsSecureString
		$密钥值 = [System.Net.NetworkCredential]::new([string]::Empty, $安全密钥).Password
	}
	$记住的配置 = Import-记住的配置 -配置路径 $配置路径

	# 默认值：基础地址与模型（用户指定的显式参数优先；已记住的值优先于默认）
	if (-not $基础地址 -and -not ($记住的配置 -and $记住的配置.基础地址)) {
		$基础地址 = 'https://token.sensenova.cn/v1'
	}
	if (-not $MyInvocation.BoundParameters.ContainsKey('模型') -and -not ($记住的配置 -and $记住的配置.模型)) {
		$模型 = 'SenseNova U1 Pro'
	}

	$凭据 = Resolve-配置凭据 -参数密钥 $密钥值 -参数基础地址 $基础地址 -参数模型 $模型 `
		-记住的配置 $记住的配置 -配置路径 $配置路径

	# 端点选择 + 参考图：URL 直接透传；本地文件转带 MIME 前缀的 base64 Data-URL。
	# 官方要求：不支持纯无前缀 base64；链接访问失败 / 内容不是图片 / base64 解码错误会被直接驳回。
	$参考图URL列表 = [System.Collections.Generic.List[string]]::new()
	$有参考图 = [bool]$参考图
	if ($有参考图) {
		$总数据量 = [long]0
		foreach ($单张 in $参考图) {
			if ($单张 -match '^https?://') {
				$参考图URL列表.Add($单张)
			}
			else {
				$数据 = Get-图像数据 -来源 $单张
				$mime = Get-Mime类型 -路径 $数据.文件名
				if ($mime -eq 'application/octet-stream') { $mime = 'image/png' }
				$总数据量 += $数据.字节.Length
				$参考图URL列表.Add('data:' + $mime + ';base64,' + [Convert]::ToBase64String($数据.字节))
			}
		}
		# Data-URL 编码后体积约为原文件的 1.33 倍，留足余量避免请求体过大被拒
		if ($总数据量 -gt 83886080) { throw "参考图总大小超过 80MB 上限（当前 $([Math]::Round($总数据量 / 1MB, 1)) MB）。" }
	}

	# 端点：基础地址已带 /vN 后缀直接用，否则补 /v1
	if ($凭据.基础地址 -match '/v\d+/?$') { $api基础 = $凭据.基础地址.TrimEnd('/') }
	else { $api基础 = $凭据.基础地址.TrimEnd('/') + '/v1' }
	if ($有参考图) { $端点 = "$api基础/images/edits" }
	else { $端点 = "$api基础/images/generations" }

	# 请求体（日日新图像接口）
	# response_format 固定 b64_json：url 模式临时链接仅 24 小时有效，
	# base64 直接落盘无失效风险，网络中断重试也不必重新生成（会重复计费）。
	# watermark 显式传（公测期无水印免费，官方建议显式传参以防默认值变更）。
	$请求体对象 = [ordered]@{
		model           = $凭据.模型
		prompt          = $提示词
		n               = 1
		size            = $尺寸
		output_format   = $输出格式
		response_format = 'b64_json'
		watermark       = $水印.IsPresent
	}
	if ($保留提示词.IsPresent) { $请求体对象['prompt_extend'] = $false }
	if ($有参考图) {
		$请求体对象['images'] = @(foreach ($u in $参考图URL列表) { @{ image_url = $u } })
	}
	$请求体 = $请求体对象 | ConvertTo-Json -Depth 6

	Write-Host "正在调用 $($凭据.模型) 生成图像（U1 Pro 需多步思维链，可能耗时数分钟）..." -ForegroundColor Cyan

	# 用 HttpClient 提交：本地参考图 base64 编码后请求体可能很大，
	# Invoke-RestMethod（HttpWebRequest）默认 Expect 100-continue 在大体积上传时容易被服务端断开。
	# 密钥验证失败（401）时不直接失败退出：立即交互式提示输入新密钥，然后重试。
	# 网络抖动（连接中断无服务端响应体）无限重试等待恢复；有响应体的明确错误直接抛出。
	Add-Type -AssemblyName System.Net.Http
	while ($true) {
		$客户端 = [System.Net.Http.HttpClient]::new()
		$客户端.Timeout = [TimeSpan]::FromSeconds($超时秒数)
		$客户端.DefaultRequestHeaders.Authorization =
			[System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $凭据.密钥明文)
		$内容 = [System.Net.Http.StringContent]::new($请求体, [System.Text.Encoding]::UTF8, 'application/json')
		try {
			$响应消息 = $客户端.PostAsync($端点, $内容).GetAwaiter().GetResult()
			$响应文本 = $响应消息.Content.ReadAsStringAsync().GetAwaiter().GetResult()
			if (-not $响应消息.IsSuccessStatusCode) {
				$状态码 = [int]$响应消息.StatusCode
				if ($状态码 -eq 401) {
					Write-Warning "密钥验证失败（HTTP $状态码）：$响应文本"
					$新安全密钥 = Read-Host -Prompt '请重新输入正确的日日新 API 密钥以立即重试（留空则取消）' -AsSecureString
					if ($新安全密钥.Length -eq 0) {
						throw [System.Management.Automation.RuntimeException]"未输入密钥，请求已取消。"
					}
					$凭据.安全密钥对象 = $新安全密钥
					$凭据.密钥明文 = [System.Net.NetworkCredential]::new([string]::Empty, $新安全密钥).Password
					$凭据.密钥来源 = '交互输入'
					Write-Host "使用新密钥重试..." -ForegroundColor Yellow
					continue
				}
				$提示信息 = ''
				if ($状态码 -eq 404 -and $凭据.模型 -eq 'SenseNova U1 Pro') {
					$提示信息 = '（Hint：404 + 邀测中的默认模型通常表示该密钥未开通 U1 Pro 权限，' +
						'请换模型重试，例如 -模型 sensenova-u1.5-lite）'
				}
				if ($状态码 -eq 400 -and ($响应文本 -match 'image_url|images')) {
					$提示信息 = '（Hint：参考图不合法。URL 须公网可访问且是图片；' +
						'Base64 须带 data:image/*;base64, 前缀——本函数转本地文件为 Data-URL）'
				}
				throw [System.Management.Automation.RuntimeException]"HTTP $状态码：$响应文本 $提示信息"
			}
			$响应 = $响应文本 | ConvertFrom-Json
			break
		}
		catch [System.Management.Automation.MethodInvocationException] {
			# 连接中断时 HttpClient 常抛 TaskCanceledException，真实原因藏在内部异常链里
			$详情 = Get-NetException详情 -Exception $_.Exception
			if ($详情 -match '^HTTP \d{3}[：:]' -or $详情 -match '"error"|"code"') {
				# 有服务端响应体，视为明确业务错误
				throw [System.Management.Automation.RuntimeException]"API 请求失败：$详情"
			}
			# 纯传输层中断（无响应体）：视为网络抖动，重试
			Write-Warning "连接中断（网络抖动，稍后重试）：$详情"
			Start-Sleep -Seconds 3
			continue
		}
		catch [System.Management.Automation.RuntimeException] { throw }
		catch { throw "API 请求失败：$($_.Exception.Message)" }
		finally { $内容.Dispose(); $客户端.Dispose() }
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
	if (-not $数据属性 -or -not $数据属性.Value -or @($数据属性.Value).Count -eq 0) {
		$响应预览 = $(try { $响应 | ConvertTo-Json -Depth 6 -Compress } catch { (Out-String -InputObject $响应) })
		throw "响应中没有 data 字段：$响应预览"
	}
	$图像 = @($数据属性.Value)[0]
	$b64属性 = $图像.PSObject.Properties['b64_json']
	if (-not $b64属性 -or -not $b64属性.Value) {
		throw "data[0] 中没有 b64_json 字段：$($图像 | ConvertTo-Json -Depth 6 -Compress)"
	}

	$解析后输出 = Resolve-输出路径 -输出路径 $输出路径
	$字节 = [Convert]::FromBase64String($b64属性.Value)
	[System.IO.File]::WriteAllBytes($解析后输出, $字节)

	# 提示改写信息
	$改写属性 = $图像.PSObject.Properties['revised_prompt']
	if ($改写属性 -and $改写属性.Value) {
		Write-Host "改写后的提示词: $($改写属性.Value)" -ForegroundColor DarkGray
	}

	Write-Host "图像已保存: $解析后输出" -ForegroundColor Green
	return $解析后输出
}
