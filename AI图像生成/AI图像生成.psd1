@{
    RootModule        = 'AI图像生成.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'd47a8e3b-9f1c-4a62-b8e5-7c3d0f2a1e69'
    Author            = '埃博拉酱'
    CompanyName       = ''
    Copyright         = '(c) 2026. All rights reserved.'
    Description       = @'
通过 OpenAI 兼容接口（GPT-Image-2）、Gemini generateContent 接口、Reve v2 接口与 OpenRouter Image API（MAI）生成 AI 图像。
支持参考图编辑、DPAPI 凭据记忆、搜索增强。
公开函数使用方法（首次使用任选其一提供凭据，之后自动记忆）：
  -密钥           交互式输入密钥
  -密钥值 'sk-…'  直接传入密钥明文
  -基础地址 / -模型 / -输出路径 等通用参数

New-GPT图像 —— gpt-image-2（OpenAI 兼容接口，自动补 /v1）
  New-GPT图像 -提示词 "水彩柴犬" -基础地址 'https://open.cherryin.net/v1'
  New-GPT图像 -提示词 "优化手脚结构细节，脚趾甲要粉白圆润可爱" -参考图 "D:\Image-generation-cli\reve_20260811_135446.png" -蒙版 "D:\Image-generation-cli\135446蒙版.png"
  可选：-尺寸 2880x2880 -质量 high；参考图最多 16 张（≤50MB/张），蒙版仅作用于第一张且需透明通道。

New-Gemini图像 —— Gemini generateContent（自动补 /v1beta）
  New-Gemini图像 -提示词 "水彩柴犬" -密钥值 'sk-xxx' -模型 'gemini-3.1-flash-image-preview'
  可选：-宽高比 1:1（10 种）-分辨率 4K-参考图。

New-Reve图像 —— Reve 2.1（Atlas Cloud 协议，默认 https://api.atlascloud.ai）
  New-Reve图像 -提示词 "水彩柴犬"
  New-Reve图像 -提示词 "让人物穿上宇航服" -参考图 .\照片.jpg            （1 张 → edit）
  New-Reve图像 -提示词 "雌小鬼虫惑魔（<frame>0</frame>）与魅惑蛇女（<frame>1</frame>）撕打大战一团，腹黑病毒娘埃博拉酱（<frame>2</frame>）坏笑看戏。注意手指、脚趾和肢体结构合理性" -参考图 "D:\OneDrive\图片\虫惑魔\合并虫惑魔.png","D:\Image-generation-cli\gemini_20260811_001744.png","D:\OneDrive\图片\自设\立绘.jpg"  （2~6 张 → remix）
  可选：-宽高比 auto（18 种）-去背景。密钥失效（401）时会立即交互式提示输入新密钥并重试。

New-MAI图像 —— 微软 MAI-Image-2.5（OpenRouter Image API，默认 https://openrouter.ai）
  New-MAI图像 -提示词 "水彩柴犬" -密钥值 'sk-or-xxx'
  New-MAI图像 -提示词 "改成吉卜力风格" -参考图 .\照片.png
  可选：-宽高比 auto（8 种）-尺寸 1K -数量 2。参考图最多 1 张。

所有函数的 -提示文件 参数可传入提示词文本文件代替 -提示词；-密钥 开关可随时交互式更换密钥。
'@
    PowerShellVersion = '5.1'
    FunctionsToExport = @('New-GPT图像', 'New-Gemini图像', 'New-Reve图像', 'New-MAI图像')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('AI', 'Image', 'GPT', 'Gemini', 'Reve', 'MAI', '图像生成', '中文')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/Ebola-Chan-bot/Image-generation-cli'
            ReleaseNotes = '新增 New-MAI图像：通过 OpenRouter Image API 调用微软 MAI-Image-2.5'
        }
    }
}
