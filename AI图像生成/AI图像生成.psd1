@{
    RootModule        = 'AI图像生成.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'd47a8e3b-9f1c-4a62-b8e5-7c3d0f2a1e69'
    Author            = '埃博拉酱'
    CompanyName       = ''
    Copyright         = '(c) 2026. All rights reserved.'
    Description       = @'
通过 OpenAI 兼容接口（GPT-Image-2）、Gemini generateContent 接口与 Reve v2 接口生成 AI 图像。
支持参考图编辑、DPAPI 凭据记忆、搜索增强。
'@
    PowerShellVersion = '5.1'
    FunctionsToExport = @('New-GPT图像', 'New-Gemini图像', 'New-Reve图像')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('AI', 'Image', 'GPT', 'Gemini', 'Reve', '图像生成', '中文')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/Ebola-Chan-bot/Image-generation-cli'
            ReleaseNotes = '新增 New-Reve图像：通过 Reve v2 接口生成 4K 图像'
        }
    }
}
