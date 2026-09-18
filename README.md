从命令行调用 GPT-Image-2 和 Gemini 系列模型生成 AI 图像的 PowerShell 模块。

# 安装

```powershell
# 从 PowerShell Gallery 安装
Install-Module -Name AI图像生成

# 或从本地安装
Copy-Item -Recurse .\AI图像生成\ "$($env:PSModulePath.Split(';')[0])\AI图像生成\"
```

# 使用

## GPT-Image-2（OpenAI 兼容接口）

```powershell
# 首次使用需指定密钥和基础地址，之后自动记住
New-GPT图像 -提示词 "一只在月光下奔跑的柴犬，水彩风格" `
    -密钥 'sk-xxxxxxxx' -基础地址 'https://open.cherryin.net/v1' -模型 'openai/gpt-image-2'

# 从文件读入提示词
New-GPT图像 -提示文件 .\提示词.txt

# 指定尺寸和质量（质量档位：low/medium/high/auto；GPT-Image-2.5 系列还支持 xhigh/max）
New-GPT图像 -提示词 "赛博朋克城市夜景" -尺寸 1536x1024 -质量 high

# 基于参考图生成
New-GPT图像 -提示词 "把这张照片改成吉卜力动画风格" -参考图 .\照片.png

# 蒙版局部重绘：只重画透明区域，其余保持原样
New-GPT图像 -提示词 "这里改成一顶红色圣诞帽" -参考图 .\立绘.png -蒙版 .\mask.png
```

参考图为官方限制（本模块不做本地拦截）：最多 **16 张**，每张小于 **50MB**，格式 png/webp/jpg；
多张参考图搭配 `-蒙版` 时，蒙版仅作用于第一张。

### 蒙版（-蒙版）的制作方法

蒙版用于对参考图做**局部重绘（inpainting）**，语义：**透明（alpha=0）区域 = 要重画的地方；不透明区域 = 保持原样**。

要求：

- 必须是 **PNG**（JPEG/WebP 没有 alpha 通道）
- 宽高与参考图**像素级一致**（API 不会自动缩放对齐，尺寸不符会报错）
- RGBA 带 alpha 通道；保留区域的颜色不影响结果，只看透明与否

提示词只描述**透明区域里想要什么**，其余部分模型严格保留参考图原样。

## Gemini 图像模型（generateContent 接口）

```powershell
# 首次使用需指定全部凭据
New-Gemini图像 -提示词 "水彩柴犬" `
    -密钥 'sk-xxxxxxxx' -基础地址 'https://ssvip.dmxapi.com/v1' -模型 'gemini-3.1-flash-image-preview'

# 指定宽高比和分辨率
New-Gemini图像 -提示词 "电影海报" -宽高比 16:9 -分辨率 2K

# 基于参考图编辑
New-Gemini图像 -提示文件 .\提示词.txt -参考图 .\照片.png
```

宽高比支持 10 种：`1:1`、`16:9`、`9:16`、`4:3`、`3:4`、`3:2`、`2:3`、`5:4`、`4:5`、`21:9`；
分辨率支持 `1K` | `2K` | `4K`（其中 4K 仅 gemini-3-pro-image / Nano Banana Pro 支持，Flash 系最高 2K）。

## Reve 图像模型（Atlas Cloud 中转站协议）

```powershell
# 首次使用需指定密钥（基础地址默认 https://api.atlascloud.ai，可用 -基础地址 覆盖）
# 变体按参考图数量自动选择：0 张 → text-to-image，1 张 → edit，2 张以上 → remix
New-Reve图像 -提示词 "水彩柴犬" -密钥值 'xxxxxxxx'

# 基于单张参考图编辑（edit 变体）
New-Reve图像 -提示词 "让人物穿上宇航服" -参考图 .\照片.jpg

# 基于多张参考图混合生成（remix 变体，提示词用 <frame>0</frame> 引用）
New-Reve图像 -提示词 "<frame>0</frame> 中的人物穿上宇航服，站在 <frame>1</frame> 的场景里" `
    -参考图 .\人物.jpg, .\场景.jpg

# 指定宽高比、去背景输出透明 PNG
New-Reve图像 -提示词 "logo 图标" -宽高比 1:1 -去背景
```

任务提交后自动同步等待结果，中转站未完成时会轮询到出图或超时。

## MAI 图像模型（OpenRouter Image API）

```powershell
# 首次使用需指定 OpenRouter 密钥（基础地址默认 https://openrouter.ai）
New-MAI图像 -提示词 "水彩柴犬" -密钥值 'sk-or-xxxxxxxx'

# 基于参考图做图生图编辑
New-MAI图像 -提示词 "把这张照片改成吉卜力动画风格" -参考图 .\照片.png

# 指定宽高比与数量（上游支持时才生效）
New-MAI图像 -提示词 "电影海报" -宽高比 16:9 -数量 2
```

计费为全包制：成功出图整张计费，失败不计费。

## SenseNova U1 系列（商汤日日新图像接口）

```powershell
# 首次使用只需指定密钥（基础地址默认官网 https://token.sensenova.cn/v1，模型默认 SenseNova U1 Pro）
# 密钥在 https://platform.sensenova.cn/console/keys 创建
New-SenseNova图像 -提示词 "水彩柴犬" -密钥值 'xxxxxxxx'

# 基于参考图编辑（走 /v1/images/edits，本地文件自动转 Data-URL）
New-SenseNova图像 -提示词 "把背景改成雪山，人物保持不变" -参考图 .\照片.png

# 高分辨率与格式控制
New-SenseNova图像 -提示词 "神经网络发展史信息图" -尺寸 4K -输出格式 webp

# U1 Pro 处于邀测阶段，未开通时更换为已开放模型
New-SenseNova图像 -提示词 "水彩柴犬" -模型 'sensenova-u1.5-lite'
```

- `-尺寸`：`auto`（默认）/ `2K` / `4K` / 精确像素 `WxH`（宽高须为 32 的倍数、512~4096、长短边之比 ≤3，本地预校验）。
- 图像统一以 base64 返回并直接落盘，避开 url 模式临时链接仅 24 小时有效的问题。
- `-水印` 默认关闭（官方无水印公测免费，后续转付费特性）；`-保留提示词` 跳过平台提示词自动润色。
- 参考图仅支持公网 URL 或本地文件（自动转带 `data:image/*;base64,` 前缀的 Data-URL，裸 base64 会被官方驳回）。
- `n` 固定为 1（平台限制）；需要多张时多次调用。

# 凭据安全

密钥使用 Windows DPAPI 加密存储在 `%LOCALAPPDATA%\Image-generation-cli\` 下，仅当前用户可解密。调用成功后自动记住。

# 模块结构

```
AI图像生成/
├── AI图像生成.psd1          # 模块清单
├── AI图像生成.psm1          # 模块根
├── 函数/
│   ├── New-GPT图像.ps1
│   ├── New-Gemini图像.ps1
│   ├── New-Reve图像.ps1
│   ├── New-MAI图像.ps1
│   └── New-SenseNova图像.ps1
└── 内部/
    ├── 配置管理.ps1
    └── 工具函数.ps1
```
