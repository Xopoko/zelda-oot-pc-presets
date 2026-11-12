#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Destination,
    [string]$DesktopPath = [Environment]::GetFolderPath('DesktopDirectory')
)

$ErrorActionPreference = 'Stop'

# Compiles ZeldaLauncher.exe, a console-free wrapper that starts Launch.ps1.
function Install-LauncherBootstrap([string]$Target) {
    if (Test-Path -LiteralPath $Target -PathType Leaf) { return }
    $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw 'The Windows .NET Framework x64 compiler is required to create desktop shortcuts.'
    }
    $source = Join-Path $PSScriptRoot 'LauncherBootstrap.cs'
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $compiler
    $startInfo.Arguments = '/nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /out:"{0}" "{1}"' -f $Target, $source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            Remove-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
            throw ('Could not compile ZeldaLauncher.exe. ' + $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
        }
    }
    finally { $process.Dispose() }
}

$root = (Resolve-Path -LiteralPath $Destination).ProviderPath
$rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$desktop = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DesktopPath)
[void][IO.Directory]::CreateDirectory($desktop)
$launcher = Join-Path $root 'Launch.ps1'
if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) { throw "Launcher missing at $launcher." }
$receipt = Get-Content -LiteralPath (Join-Path $root 'install.json') -Raw | ConvertFrom-Json
if ($receipt.schemaVersion -ne 1) { throw 'Unknown installation receipt version.' }

$bootstrap = Join-Path $root 'ZeldaLauncher.exe'
Install-LauncherBootstrap $bootstrap
$shell = New-Object -ComObject WScript.Shell
$names = [ordered]@{
    Native = 'Zelda Ocarina of Time - Native Quality'
    Ultra = 'Zelda Ocarina of Time - Ultra DLSS 5'
}

foreach ($preset in $names.Keys) {
    $key = $preset.ToLowerInvariant()
    $selected = $receipt.presets.$key
    if (!$selected -or $selected.available -ne $true) { continue }
    if (!$selected.gameRoot -or [IO.Path]::IsPathRooted($selected.gameRoot)) {
        throw 'The installation receipt contains an invalid preset path.'
    }
    $exe = [IO.Path]::GetFullPath((Join-Path $root "$($selected.gameRoot)\bin\hookshot.exe"))
    if (!$exe.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        !(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Invalid Hookshot path for $preset." }
    # Don't overwrite another installation's shortcut; add " (2)" etc. instead.
    $index = 1
    while ($true) {
        $name = $names[$preset]
        if ($index -gt 1) { $name += " ($index)" }
        $path = Join-Path $desktop "$name.lnk"
        $exists = Test-Path -LiteralPath $path
        $shortcut = $shell.CreateShortcut($path)
        if (!$exists -or ($shortcut.TargetPath -eq $bootstrap -and $shortcut.Arguments -eq $preset)) {
            break
        }
        $index++
    }

    $shortcut.TargetPath = $bootstrap
    $shortcut.Arguments = $preset
    $shortcut.WorkingDirectory = $root
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Description = $names[$preset]
    $shortcut.WindowStyle = 1
    $shortcut.Save()
    [pscustomobject]@{ Preset = $preset; Path = $path }
}
