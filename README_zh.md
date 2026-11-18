# Shapr3d 26.203.12356.0 #cf7bf415

从 5.603.6875.0 #40c93214 版本开始，出现了新的补丁方式。之前的漏洞已被 Shapr3D 团队封堵。
但仍有几种方法可以解锁试用版。  
此处的资料和信息是关于如何修补 Shapr3d 可执行文件以移除试用限制的指南，所有内容仅用于学习和教育目的。

# 使用方法（感谢 5six2JZ TomTom）

请仔细按照每一步操作

* 下载并安装 Visual Studio 2019 可再发行组件。我安装的版本：16.9，架构：x64，发布日期：2021/3/2。
* Visual Studio 2019 安装完成后，重启电脑。
* 在 Windows 安全中心 > 病毒和威胁防护中，关闭所有保护（可选，仅当补丁程序被检测为病毒时才需要）
* 进入 sl4v3k 仓库的 x64/Release 文件夹，点击链接：Shapr3D-inmemory-patcher-2.exe。**切勿右键点击链接并选择"另存为..."（这是我犯过的错误，因为右键保存 patcher-2.exe 文件时，浏览器下载的 patcher-2.exe 将无法正常运行。你会收到以下错误：无法在此电脑上运行 或 与 64 位 Windows 版本不兼容。
* 因此，只需**左键点击** Shapr3D-inmemory-patcher-2.exe 链接，你会看到代码和 Blame 标签页。点击屏幕右侧的"下载原始文件"图标，即可下载可正常工作的 Shapr3D-inmemory-patcher-2.exe 文件。
* 现在，进入 C 盘并创建一个新文件夹，命名为 patch（目录路径为 C:\patch）
* 将刚下载的 Shapr3D-inmemory-patcher-2.exe 放入 C:\patch 中
* 打开 Shapr3d 应用程序并保持运行
* 以**管理员身份**打开命令提示符（CMD）
* 输入：`cd\`（按回车键）
* 输入：`cd\patch`（按回车键）
* 输入：`Shapr3D-inmemory-patcher-2.exe`（按回车键）
* 如果看到 "Shapr found!"，说明补丁已成功应用。
* 关闭命令提示符
* 尽情使用吧！
* **注意：从 5.961.9619.0 版本起，你需要先打开一个免费项目来刷新视图状态，才能解锁其他项目！**

# VC 可再发行组件

别忘了从微软官网安装 Visual Studio 2019 可再发行组件。

# 自动更新

别忘了禁用 Microsoft Store 应用的自动更新，因为更新可能会在没有通知的情况下发生并破坏补丁。

# 自动化脚本（本仓库新增）

`patcher.ps1` 是原 C++ 补丁的 PowerShell 实现，输出更详细，并支持自动启动：

```powershell
# 仅对已运行的 Shapr3D 打补丁
powershell -ExecutionPolicy Bypass -File .\patcher.ps1

# 自动启动 Shapr3D，等待 Shapr3D.dll 加载后自动打补丁（配合桌面快捷方式使用）
powershell -ExecutionPolicy Bypass -File .\patcher.ps1 -Launch
```

- 内存补丁，**Shapr3D 每次重启后都需要重新执行**
- `-Launch` 模式日志写入 `patch_last_run.log`
- 安装包放在 `installer/` 目录（已在 `.gitignore` 中忽略，不入库）

## 快捷方式生成器

双击 `Create-Shapr3D-Shortcut.exe`，会自动检测 Shapr3D 的 AppX 安装位置，在桌面创建
`Shapr3D (自动补丁).lnk`（使用 Shapr3D 图标）。以后用该快捷方式启动，会自动打补丁。

- 程序需与 `patcher.ps1` 放在同一目录
- 源码：`tools/CreateShortcut.cs`
- 重新编译：
  ```powershell
  C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /target:winexe /out:Create-Shapr3D-Shortcut.exe /r:System.Windows.Forms.dll tools\CreateShortcut.cs
  ```


