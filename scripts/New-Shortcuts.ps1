#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Destination,
    [string]$DesktopPath = [Environment]::GetFolderPath('DesktopDirectory')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $Destination).ProviderPath
$rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$desktop = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DesktopPath)
[void][IO.Directory]::CreateDirectory($desktop)
$launcher = Join-Path $root 'Launch.ps1'
if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) { throw "Launcher missing at $launcher." }
$receipt = Get-Content -LiteralPath (Join-Path $root 'install.json') -Raw | ConvertFrom-Json
if ($receipt.schemaVersion -ne 1) { throw 'Unknown installation receipt version.' }

$shell = New-Object -ComObject WScript.Shell
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
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
    $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Preset {1} -NoConsole' -f $launcher, $preset

    # Preserve existing shortcuts from another install. Reuse this install's link.
    $index = 1
    while ($true) {
        $name = $names[$preset]
        if ($index -gt 1) { $name += " ($index)" }
        $path = Join-Path $desktop "$name.lnk"
        $exists = Test-Path -LiteralPath $path
        $shortcut = $shell.CreateShortcut($path)
        if (!$exists -or ($shortcut.TargetPath -eq $powershell -and $shortcut.Arguments -eq $arguments)) {
            break
        }
        $index++
    }

    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $root
    $shortcut.IconLocation = "$exe,0"
    $shortcut.Description = $names[$preset]
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    [pscustomobject]@{ Preset = $preset; Path = $path }
}
