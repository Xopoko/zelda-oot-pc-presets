using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class LauncherBootstrap
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 1)
            return ShowError("Choose the Native or Ultra preset.");

        string preset;
        if (String.Equals(args[0], "Native", StringComparison.OrdinalIgnoreCase))
            preset = "Native";
        else if (String.Equals(args[0], "Ultra", StringComparison.OrdinalIgnoreCase))
            preset = "Ultra";
        else
            return ShowError("Choose the Native or Ultra preset.");

        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "Launch.ps1");
            if (!File.Exists(script))
                return ShowError("Launch.ps1 is missing. Run the installer to create a complete installation.");

            string system = Environment.GetFolderPath(Environment.SpecialFolder.System);
            ProcessStartInfo start = new ProcessStartInfo
            {
                FileName = Path.Combine(system, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""
                    + script + "\" -Preset " + preset + " -NoConsole",
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            // PowerShell 5.1 builds its own module search path.
            start.EnvironmentVariables.Remove("PSModulePath");
            using (Process child = Process.Start(start))
            {
                if (child == null) return ShowError("Windows PowerShell could not be started.");
            }
            return 0;
        }
        catch (Exception error)
        {
            return ShowError(error.Message);
        }
    }

    private static int ShowError(string message)
    {
        MessageBox.Show(message, "Zelda Ocarina of Time", MessageBoxButtons.OK, MessageBoxIcon.Error);
        return 1;
    }
}
