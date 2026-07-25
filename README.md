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

# 透明背景
New-GPT图像 -提示词 "logo 图标" -背景 transparent
```

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

# 凭据安全

密钥使用 Windows DPAPI 加密存储在 `%LOCALAPPDATA%\Image-generation-cli\` 下，仅当前用户可解密。调用成功后自动记住。

# 模块结构

```
AI图像生成/
├── AI图像生成.psd1          # 模块清单
├── AI图像生成.psm1          # 模块根
├── 函数/
│   ├── New-GPT图像.ps1
│   └── New-Gemini图像.ps1
└── 内部/
    ├── 配置管理.ps1
    └── 工具函数.ps1
```
