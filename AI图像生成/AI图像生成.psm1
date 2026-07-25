# AI图像生成 模块根
# 点源加载所有函数文件

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$模块目录 = Split-Path -Parent $MyInvocation.MyCommand.Path

# 加载内部函数
. (Join-Path $模块目录 '内部\配置管理.ps1')
. (Join-Path $模块目录 '内部\工具函数.ps1')

# 加载公开函数
. (Join-Path $模块目录 '函数\New-GPT图像.ps1')
. (Join-Path $模块目录 '函数\New-Gemini图像.ps1')

# 导出
Export-ModuleMember -Function 'New-GPT图像', 'New-Gemini图像'
