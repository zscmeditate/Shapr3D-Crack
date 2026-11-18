# Shapr3D In-Memory Patcher v2 - Fixed
param([switch]$Launch)

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Shapr3D In-Memory Patcher v2 (PS)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# P/Invoke
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class K32 {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualProtectEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flNewProtect, out uint lpflOldProtect);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out uint lpNumberOfBytesWritten);
    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
}
public class PSA {
    [DllImport("psapi.dll", SetLastError=true)]
    public static extern bool EnumProcessModules(IntPtr hProcess, IntPtr[] lphModule, uint cb, out uint lpcbNeeded);
    [DllImport("psapi.dll", CharSet=CharSet.Unicode)]
    public static extern uint GetModuleFileNameEx(IntPtr hProcess, IntPtr hModule, StringBuilder lpBaseName, uint nSize);
}
"@

$PROCESS_CREATE_THREAD = 0x0002
$PROCESS_QUERY_INFORMATION = 0x0400
$PROCESS_VM_OPERATION = 0x0008
$PROCESS_VM_WRITE = 0x0020
$PROCESS_VM_READ = 0x0010

# 0. 快捷方式模式：自动启动 Shapr3D 并等待加载完成
if ($Launch) {
    $logPath = Join-Path $PSScriptRoot "patch_last_run.log"
    try { Start-Transcript -Path $logPath -Append | Out-Null } catch {}

    $running = Get-Process | Where-Object { $_.ProcessName -match "^Shapr" } | Select-Object -First 1
    if (-not $running) {
        Write-Host "[0/6] Launching Shapr3D..."
        $pkg = Get-AppxPackage -Name "Shapr3D.Shapr3D*" | Select-Object -First 1
        if (-not $pkg) {
            Write-Host "  Shapr3D not installed!" -ForegroundColor Red
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show("Shapr3D 未安装，无法启动。", "Shapr3D 补丁") | Out-Null
            } catch {}
            exit 1
        }
        Start-Process ("shell:AppsFolder\{0}!App" -f $pkg.PackageFamilyName)
    } else {
        Write-Host "[0/6] Shapr3D already running (PID=$($running.Id))"
    }

    # 等待 Shapr3D.dll 被加载进进程
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        $p = Get-Process | Where-Object { $_.ProcessName -match "^Shapr" } | Select-Object -First 1
        if ($p) {
            $hasDll = $false
            try { $hasDll = [bool]($p.Modules | Where-Object { $_.ModuleName -eq "Shapr3D.dll" }) } catch {}
            if ($hasDll) { break }
        }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Milliseconds 1200
    Write-Host ""
}

# 1. 查找 Shapr3D 进程
Write-Host "[1/6] Looking for Shapr3D process..." -ForegroundColor Yellow
$shaprProc = Get-Process | Where-Object { $_.ProcessName -match "^Shapr" } | Select-Object -First 1
if (-not $shaprProc) {
    Write-Host "  Shapr3D NOT found! Please open Shapr3D first." -ForegroundColor Red
    exit 1
}
$shaprPid = $shaprProc.Id
Write-Host "  Found! PID=$shaprPid" -ForegroundColor Green

# 2. 打开进程（需要 VM_WRITE 权限）
Write-Host "[2/6] Opening process..." -ForegroundColor Yellow
$access = $PROCESS_CREATE_THREAD -bor $PROCESS_QUERY_INFORMATION -bor $PROCESS_VM_OPERATION -bor $PROCESS_VM_WRITE -bor $PROCESS_VM_READ
$hProcess = [K32]::OpenProcess($access, $false, $shaprPid)
if ($hProcess -eq [IntPtr]::Zero) {
    $err = [K32]::GetLastError()
    Write-Host "  OpenProcess FAILED! Error=0x$($err.ToString('X8'))" -ForegroundColor Red
    Write-Host "  Try: Run PowerShell as Administrator" -ForegroundColor Red
    exit 1
}
Write-Host "  Handle: $hProcess" -ForegroundColor Green

# 3. 找 Shapr3D.dll 基址
Write-Host "[3/6] Finding Shapr3D.dll..." -ForegroundColor Yellow
$dummy = New-Object IntPtr[] 1
$needed = 0
[PSA]::EnumProcessModules($hProcess, $dummy, 8, [ref]$needed) | Out-Null
$modCount = [Math]::Floor($needed / 8)
$modules = New-Object IntPtr[] $modCount
[PSA]::EnumProcessModules($hProcess, $modules, $needed, [ref]$needed) | Out-Null

$targetBase = [IntPtr]::Zero
for ($i = 0; $i -lt $modCount; $i++) {
    $sb = New-Object System.Text.StringBuilder 512
    [PSA]::GetModuleFileNameEx($hProcess, $modules[$i], $sb, 512) | Out-Null
    $path = $sb.ToString()
    $name = [IO.Path]::GetFileName($path)
    Write-Host "  [$i] $name (base=$($modules[$i]))"
    
    # C++ 源码匹配逻辑: szModName[len-5]=='D' && szModName[len-1]=='l'
    # 即文件名倒数第5位是 'D'，最后一位是 'l' → 匹配 "Shapr3D.dll"
    $fileNameOnly = [IO.Path]::GetFileNameWithoutExtension($path)  # "Shapr3D"
    if ($name -eq "Shapr3D.dll" -or ($fileNameOnly.Length -ge 5 -and $fileNameOnly[$fileNameOnly.Length - 5] -eq 'D')) {
        $targetBase = $modules[$i]
        Write-Host "  *** MATCHED Shapr3D.dll! ***" -ForegroundColor Cyan
        break
    }
}

if ($targetBase -eq [IntPtr]::Zero) {
    Write-Host "  Shapr3D.dll not found in module list! Trying Shapr.Native.dll..." -ForegroundColor Yellow
    for ($i = 0; $i -lt $modCount; $i++) {
        $sb = New-Object System.Text.StringBuilder 512
        [PSA]::GetModuleFileNameEx($hProcess, $modules[$i], $sb, 512) | Out-Null
        $path = $sb.ToString()
        if ([IO.Path]::GetFileName($path) -eq "Shapr.Native.dll") {
            $targetBase = $modules[$i]
            Write-Host "  Using Shapr.Native.dll base." -ForegroundColor Yellow
            break
        }
    }
}

if ($targetBase -eq [IntPtr]::Zero) {
    Write-Host "  No suitable DLL found! Using main module." -ForegroundColor Red
    $targetBase = $modules[0]
}

$baseAddr = $targetBase.ToInt64()
Write-Host "  Using base: 0x$($baseAddr.ToString('X16'))" -ForegroundColor Green

# 4. 应用补丁
Write-Host "[4/6] Applying patches..." -ForegroundColor Yellow

function Patch-Mem {
    param($hProc, [long]$addr, [byte[]]$data, [string]$desc)
    
    Write-Host ""
    Write-Host "  >>> $desc"
    $absAddr = [IntPtr]::new($addr)
    
    # VirtualProtectEx - PAGE_EXECUTE_READWRITE (0x40)
    $oldProt = 0
    $vpSize = [Math]::Max(0x10000, [uint32]$data.Length)
    if (-not [K32]::VirtualProtectEx($hProc, $absAddr, $vpSize, 0x40, [ref]$oldProt)) {
        $err = [K32]::GetLastError()
        Write-Host "    VirtualProtectEx FAILED! Error=0x$($err.ToString('X8'))" -ForegroundColor Red
        return $false
    }
    Write-Host "    VirtualProtectEx OK"
    
    # WriteProcessMemory
    $written = 0
    if (-not [K32]::WriteProcessMemory($hProc, $absAddr, $data, [uint32]$data.Length, [ref]$written)) {
        $err = [K32]::GetLastError()
        Write-Host "    WriteProcessMemory FAILED! Error=0x$($err.ToString('X8'))" -ForegroundColor Red
        return $false
    }
    Write-Host "    WriteProcessMemory OK! Wrote $written bytes" -ForegroundColor Green
    
    # 恢复保护
    [void][K32]::VirtualProtectEx($hProc, $absAddr, $vpSize, $oldProt, [ref]$oldProt)
    return $true
}

# Patch offsets from C++ source code
$patches = @(
    @{ Offset = 0x28AC84F; Data = [byte[]]@(0xE9, 0x18, 0x02, 0x00, 0x00); Desc = "Patch 1: JMP +0x28AC84F" },
    @{ Offset = 0x28ACA76; Data = [byte[]]@(0xBA, 0x0E);                     Desc = "Patch 2: MOV DX,0x0E +0x28ACA76" },
    @{ Offset = 0x1A9CE00; Data = [byte[]]@(0x32, 0xC0, 0xFE, 0xC0, 0xC3);  Desc = "Patch 3: XOR pattern +0x1A9CE00" },
    @{ Offset = 0x28B84E0; Data = [byte[]]@(0x48, 0x33, 0xC0);              Desc = "Patch 4: XOR EAX,EAX +0x28B84E0" },
    @{ Offset = 0x28B8527; Data = [byte[]]@(0x90, 0x90, 0x90, 0x90, 0x90, 0x90); Desc = "Patch 5: NOP x6 +0x28B8527" },
    @{ Offset = 0x226FA63; Data = [byte[]]@(0x90, 0x90);                     Desc = "Patch 6: NOP x2 +0x226FA63" }
)

$successCount = 0
foreach ($p in $patches) {
    $absAddr = $baseAddr + $p.Offset
    Write-Host "    Address: base + 0x$($p.Offset.ToString('X')) = 0x$($absAddr.ToString('X16'))"
    if (Patch-Mem $hProcess $absAddr $p.Data $p.Desc) {
        $successCount++
    }
}

# 5. 清理
Write-Host ""
Write-Host "[5/6] Cleaning up..." -ForegroundColor Yellow
[K32]::CloseHandle($hProcess) | Out-Null

# 6. 结果
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Patches applied: $successCount / $($patches.Count)" -ForegroundColor $(if($successCount -eq $patches.Count){'Green'}else{'Red'})
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
if ($successCount -eq $patches.Count) {
    Write-Host "All patches applied successfully!" -ForegroundColor Green
    Write-Host "If Shapr3D is still showing trial, try:" -ForegroundColor Yellow
    Write-Host "  1. Open a FREE project first" -ForegroundColor Yellow
    Write-Host "  2. Close and reopen Shapr3D" -ForegroundColor Yellow
}

# 快捷方式模式：隐藏运行时只在失败时弹窗提示
if ($Launch) {
    try { Stop-Transcript | Out-Null } catch {}
    if ($successCount -ne $patches.Count) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $msg = "补丁未能全部应用（$successCount/$($patches.Count)）。`n日志: $PSScriptRoot\patch_last_run.log"
            [System.Windows.Forms.MessageBox]::Show($msg, "Shapr3D 补丁") | Out-Null
        } catch {}
    }
}
