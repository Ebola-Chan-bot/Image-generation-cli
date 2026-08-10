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

# 指定尺寸和质量
New-GPT图像 -提示词 "赛博朋克城市夜景" -尺寸 1536x1024 -质量 high

# 基于参考图生成
New-GPT图像 -提示词 "把这张照片改成吉卜力动画风格" -参考图 .\照片.png

# 蒙版局部重绘：只重画透明区域，其余保持原样
New-GPT图像 -提示词 "这里改成一顶红色圣诞帽" -参考图 .\立绘.png -蒙版 .\mask.png
```

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
│   └── New-Reve图像.ps1
└── 内部/
    ├── 配置管理.ps1
    └── 工具函数.ps1
```
