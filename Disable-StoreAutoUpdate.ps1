# Disable-StoreAutoUpdate.ps1
# 禁用 Microsoft Store 应用的自动更新（防止 Shapr3D 被自动升级导致补丁失效）
#
# 用法：
#   右键 -> 使用 PowerShell 运行
#   或：powershell -ExecutionPolicy Bypass -File .\Disable-StoreAutoUpdate.ps1
#
# 说明：
#   - 用户级设置（HKCU）无需管理员权限
#   - 系统级策略（HKLM）需要管理员权限，脚本会先提示再请求 UAC 授权

param(
    [switch]$Elevated,  # 内部使用：标记为提权后的实例
    [switch]$NoUI       # 内部使用：控制台输出，不弹窗（便于自动化验证）
)

$ErrorActionPreference = 'Continue'
if (-not $NoUI) { Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue }

$Title   = 'Shapr3D - 禁用商店自动更新'
$HklmKey = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
$HkcuKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate'

function Show-Msg {
    param([string]$Text, [string]$Icon = 'Information')
    if ($NoUI) {
        Write-Host $Text
    } else {
        [System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', $Icon) | Out-Null
    }
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-AutoDownload {
    param([string]$Path)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name 'AutoDownload' -Value 2 -Type DWord
    return (Get-ItemProperty -Path $Path -Name 'AutoDownload').AutoDownload
}

$isAdmin = Test-Admin

# 需要写 HKLM 但没有管理员权限 -> 先提示，再请求提权
if (-not $isAdmin -and -not $Elevated) {
    if ($NoUI) {
        Write-Host '[提示] 当前非管理员，将跳过系统级策略（HKLM）'
    } else {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "禁用 Microsoft Store 自动更新需要写入系统级策略（HKLM），这需要管理员权限。`n`n" +
            "点击「是」将弹出 UAC 授权窗口，请在弹窗中点击「是」继续。`n" +
            "点击「否」则只应用用户级设置（HKCU），效果可能不完整。",
            $Title, 'YesNo', 'Question')

        if ($answer -eq 'Yes') {
            try {
                $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Elevated')
                Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Verb RunAs -Wait -ErrorAction Stop
                exit 0
            } catch {
                Show-Msg ("提权被取消或失败：" + $_.Exception.Message + "`n`n将只应用用户级设置（HKCU）。") 'Warning'
            }
        }
    }
}

# 应用设置
$results = @()

try {
    $v = Set-AutoDownload -Path $HkcuKey
    $results += "用户级 HKCU   : AutoDownload = $v  [成功]"
} catch {
    $results += "用户级 HKCU   : 写入失败 - $($_.Exception.Message)"
}

try {
    if (Test-Admin) {
        $v = Set-AutoDownload -Path $HklmKey
        $results += "系统级 HKLM   : AutoDownload = $v  [成功]"
    } else {
        $results += "系统级 HKLM   : 已跳过（缺少管理员权限）"
    }
} catch {
    $results += "系统级 HKLM   : 写入失败 - $($_.Exception.Message)"
}

$body = ($results -join "`n")
$allOk = ($results | Where-Object { $_ -match '\[成功\]' }).Count -eq 2

$footer = "`n`n说明：AutoDownload = 2 表示不再自动下载/安装商店应用更新。`n" +
          "如需恢复自动更新，删除上面两处 AutoDownload 值即可。"

if ($allOk) {
    Show-Msg ("已禁用 Microsoft Store 自动更新。`n`n" + $body + $footer)
} else {
    Show-Msg ("操作未完全成功。`n`n" + $body + $footer) 'Warning'
}

if (-not $NoUI -and -not $Elevated) {
    # 双击运行时窗口自动关闭
    exit 0
}
