using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

// Shapr3D 快捷方式生成器
// 自动检测 Shapr3D 的 AppX 安装位置，在桌面创建带 Shapr3D 图标的快捷方式，
// 快捷方式指向同目录下的 patcher.ps1 -Launch（启动后自动打内存补丁）。
internal static class Program
{
    private const string LnkName = "Shapr3D (自动补丁).lnk";
    private const string Title = "Shapr3D 快捷方式生成器";

    [STAThread]
    private static void Main()
    {
        try
        {
            string exeDir = Path.GetDirectoryName(Application.ExecutablePath);
            string patcher = FindPatcher(exeDir);
            if (patcher == null)
            {
                Show("未找到 patcher.ps1。\n\n请把本程序与 patcher.ps1 放在同一目录（或 patcher.ps1 在上一级目录）后重试。", MessageBoxIcon.Error);
                return;
            }

            string installDir;
            string familyName;
            if (!FindShapr3D(out installDir, out familyName))
            {
                Show("未检测到已安装的 Shapr3D。\n\n请先安装 Shapr3D 后重试。", MessageBoxIcon.Error);
                return;
            }

            string iconPath = Path.Combine(installDir, "Shapr3D.exe");
            string psExe = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(psExe)) psExe = @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";

            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            string lnkPath = Path.Combine(desktop, LnkName);
            if (File.Exists(lnkPath)) File.Delete(lnkPath);

            string args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + patcher + "\" -Launch";
            string workDir = Path.GetDirectoryName(patcher);
            string icon = File.Exists(iconPath) ? iconPath + ",0" : "";

            CreateShortcut(lnkPath, psExe, args, workDir, icon, "启动 Shapr3D 并自动应用内存补丁");

            Show("快捷方式已创建：\n" + lnkPath +
                 "\n\nShapr3D 版本目录：\n" + installDir +
                 "\n\n以后请用这个快捷方式启动 Shapr3D，每次启动都会自动打补丁。",
                 MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            Show("创建失败：" + ex.Message, MessageBoxIcon.Error);
        }
    }

    private static void Show(string text, MessageBoxIcon icon)
    {
        MessageBox.Show(text, Title, MessageBoxButtons.OK, icon);
    }

    // 查找 patcher.ps1：先本目录，再上一级目录
    private static string FindPatcher(string exeDir)
    {
        if (string.IsNullOrEmpty(exeDir)) return null;
        string p = Path.Combine(exeDir, "patcher.ps1");
        if (File.Exists(p)) return p;
        DirectoryInfo parent = Directory.GetParent(exeDir);
        if (parent != null)
        {
            p = Path.Combine(parent.FullName, "patcher.ps1");
            if (File.Exists(p)) return p;
        }
        return null;
    }

    // 通过 PowerShell 查询 AppX 包信息，失败则回退到扫描 WindowsApps 目录
    private static bool FindShapr3D(out string installDir, out string familyName)
    {
        installDir = null;
        familyName = null;

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -NonInteractive -Command \"$p = Get-AppxPackage -Name 'Shapr3D.Shapr3D*' | Select-Object -First 1; if ($p) { $p.InstallLocation + '|' + $p.PackageFamilyName }\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            using (Process proc = Process.Start(psi))
            {
                string output = proc.StandardOutput.ReadToEnd().Trim();
                proc.WaitForExit(15000);
                int bar = output.IndexOf('|');
                if (bar > 0)
                {
                    string dir = output.Substring(0, bar).Trim();
                    string fam = output.Substring(bar + 1).Trim();
                    if (Directory.Exists(dir))
                    {
                        installDir = dir;
                        familyName = fam;
                        return true;
                    }
                }
            }
        }
        catch { }

        // 回退：扫描 WindowsApps 目录
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps");
        if (!Directory.Exists(root)) return false;

        var candidates = new List<KeyValuePair<Version, string>>();
        foreach (string dir in Directory.GetDirectories(root, "Shapr3D.Shapr3D_*"))
        {
            string name = Path.GetFileName(dir);
            string[] parts = name.Split('_');
            if (parts.Length < 4) continue;

            Version v;
            if (!Version.TryParse(parts[1], out v)) continue;
            candidates.Add(new KeyValuePair<Version, string>(v, dir));
        }
        if (candidates.Count == 0) return false;

        candidates.Sort((a, b) => b.Key.CompareTo(a.Key));
        string bestDir = candidates[0].Value;
        string[] bestParts = Path.GetFileName(bestDir).Split('_');
        string publisherId = bestParts[bestParts.Length - 1];

        installDir = bestDir;
        familyName = bestParts[0] + "_" + publisherId;
        return true;
    }

    // 通过 WScript.Shell 创建 .lnk（COM 延迟绑定，无需互操作程序集）
    private static void CreateShortcut(string lnkPath, string target, string arguments,
                                       string workingDir, string iconLocation, string description)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null) throw new InvalidOperationException("无法创建 WScript.Shell 对象");

        object shell = Activator.CreateInstance(shellType);
        object shortcut = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnkPath });
        Type sc = shortcut.GetType();

        Func<string, object, bool> set = delegate(string prop, object value)
        {
            try { sc.InvokeMember(prop, BindingFlags.SetProperty, null, shortcut, new object[] { value }); return true; }
            catch { return false; }
        };

        set("TargetPath", target);
        set("Arguments", arguments);
        set("WorkingDirectory", workingDir);
        set("Description", description);
        if (!string.IsNullOrEmpty(iconLocation)) set("IconLocation", iconLocation);

        sc.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
    }
}
