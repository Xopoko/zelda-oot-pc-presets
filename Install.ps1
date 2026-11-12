#requires -Version 5.1
<#!
.SYNOPSIS
Build an isolated Zelda installation from your own supported NUP.
.EXAMPLE
.\Install.ps1 -Nup 'D:\My games\game.nup' -Destination 'D:\Games\ZeldaPresets'
.EXAMPLE
.\Install.ps1 -Nup 'D:\My games\game.nup' -Destination 'D:\Games\ZeldaPresets' -Preset Native
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Nup,
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'ZeldaOotPresets'),
    [ValidateSet('Native','Ultra','Both')][string]$Preset = 'Both',
    [string]$NrRuntime,
    [ValidatePattern('^(auto|[0-9]{3,5}x[0-9]{3,5})$')][string]$Resolution = 'auto',
    [ValidateSet('en-US','en-GB','fr','fr-CA','de','it','es','es-419','pt-BR','nl','pl','ru','ja','ko','zh-Hans','zh-Hant')][string]$Language = 'en-US',
    [ValidateRange(0,128)][int]$Jobs = 0,
    [ValidateRange(0,98304)][int]$TextureBudgetMB = 0,
    [string]$DownloadCache,
    [string]$ImportProfile,
    [switch]$NoShortcuts,
    [string]$ShortcutDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$packageVersion = '1.1.0'
$source = $PSScriptRoot
$graphicsScript = Join-Path $source 'scripts/Install-Graphics.ps1'
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
$sourcePrefix = [IO.Path]::GetFullPath($source).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if ($Destination.TrimEnd('\','/') -eq $source.TrimEnd('\','/') -or $Destination.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Choose an installation folder outside this source checkout.'
}
if (!(Test-Path -LiteralPath $Nup -PathType Leaf)) { throw "NUP not found: $Nup" }
$Nup = (Resolve-Path -LiteralPath $Nup).Path
if (Test-Path -LiteralPath $Destination) {
    if (@(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0) {
        throw 'Destination is not empty. To preserve saves and settings, use a NEW folder. See docs/INSTALL.md for upgrades.'
    }
}
if (!$DownloadCache) { $DownloadCache = Join-Path $Destination 'downloads' }
$DownloadCache = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DownloadCache)
$needUltra = $Preset -ne 'Native'
if ($needUltra -and $NrRuntime) {
    # Check a local runtime before creating anything.
    $NrRuntime = & $graphicsScript -ResolveRuntimeOnly -Cache $DownloadCache -NrRuntime $NrRuntime
}
if ($ImportProfile) {
    $ImportProfile = (Resolve-Path -LiteralPath $ImportProfile).Path
    if (!(Test-Path -LiteralPath (Join-Path $ImportProfile 'save') -PathType Container)) {
        throw '-ImportProfile must be the profile folder containing save/, not save/ itself.'
    }
}
if ($Resolution -eq 'auto') {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ZeldaDisplaySize {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
}
'@
    [void][ZeldaDisplaySize]::SetProcessDPIAware()
    $Resolution = '{0}x{1}' -f [ZeldaDisplaySize]::GetSystemMetrics(0),[ZeldaDisplaySize]::GetSystemMetrics(1)
}
$parts = $Resolution.Split('x')
$width = [int]$parts[0]; $height = [int]$parts[1]
if ($width -gt 5120 -or $height -gt 2160 -or $width -lt 1280 -or $height -lt 720 -or $width % 2 -or $height % 2) {
    throw 'Supported output sizes are even dimensions from 1280x720 through 5120x2160. Choose the physical resolution of the display used for fullscreen.'
}
if ($PSVersionTable.PSEdition -eq 'Core' -and !$IsWindows) { throw 'This installer requires Windows x64.' }
if (![Environment]::Is64BitOperatingSystem) { throw 'Windows x64 is required.' }
if (Get-Process -Name hookshot -ErrorAction SilentlyContinue) { throw 'Close Hookshot before installing or importing a save profile.' }
if (!$NoShortcuts -and !(Test-Path -LiteralPath (Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe') -PathType Leaf)) {
    throw 'The built-in Windows .NET Framework x64 compiler is missing. Use -NoShortcuts to install with the PowerShell launcher, or repair Windows .NET Framework.'
}
if (!$NoShortcuts -and $ShortcutDirectory) {
    $ShortcutDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ShortcutDirectory)
    [void][IO.Directory]::CreateDirectory($ShortcutDirectory)
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$receipts = Join-Path $Destination 'receipts'
New-Item -ItemType Directory -Path $receipts -Force | Out-Null
$installState = [ordered]@{schemaVersion=1; packageVersion=$packageVersion; status='installing'; preset=$Preset; resolution=$Resolution; startedUtc=[DateTime]::UtcNow.ToString('o')}
function Save-InstallState {
    $installState | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'installation-status.json') -Encoding UTF8
}
Save-InstallState

try {
    if ($needUltra -and !$NrRuntime) {
        # Download the NR runtime before the long build so a bad download fails early.
        Write-Host 'Downloading the Ultra NR runtime.'
        $NrRuntime = & $graphicsScript -ResolveRuntimeOnly -Cache $DownloadCache
    }
    Write-Host '1/5 Preparing the pinned Hookshot toolchain and your NUP. The first build can take 30 minutes or longer.'
    $buildArgs = @{ Nup=$Nup; Destination=(Join-Path $Destination 'base'); WorkRoot=(Join-Path $Destination 'build'); Jobs=$Jobs; DownloadCache=$DownloadCache }
    $build = & (Join-Path $source 'scripts/Build-Hookshot.ps1') @buildArgs
    if (!$build -or !$build.ToolsPython) { throw 'The build step returned no result.' }
    $python = $build.ToolsPython
    $base = $build.GameRoot
    $selected = @('native')
    if ($Preset -eq 'Ultra') { $selected = @('ultra') }
    elseif ($Preset -eq 'Both') { $selected = @('native','ultra') }

    Write-Host '2/5 Creating presets and patching the scene-width cap.'
    $runtimeFiles = @('image.bin','hookshot_shaders.bin','hookshot_computes.bin','hookshot_pipeline_states_shipped.bin','hookshot_version.txt','.hookshot_romfs','.hookshot_romfs_checked')
    foreach ($name in $selected) {
        $game = Join-Path $Destination $name
        $bin = Join-Path $game 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        foreach ($file in $runtimeFiles) {
            $runtimeSource = Join-Path $base $file
            if (Test-Path -LiteralPath $runtimeSource -PathType Leaf) { Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $game $file) }
        }
        foreach ($file in @('hookshot.exe','hookshot_vk.dll','SDL2.dll','SDL3.dll')) {
            Copy-Item -LiteralPath (Join-Path $base "bin/$file") -Destination (Join-Path $bin $file)
        }
        & $python -I -B (Join-Path $source 'tools/patch_scene.py') (Join-Path $game 'image.bin') --receipt (Join-Path $receipts "scene-$name.json")
        if ($LASTEXITCODE -ne 0) { throw "Scene cap patch failed for $name" }
        Copy-Item -LiteralPath (Join-Path $source 'presets/quality.ini') -Destination (Join-Path $game 'hookshot_options.ini')
        $config = [IO.File]::ReadAllText((Join-Path $source 'presets/quality-env.txt')).TrimEnd()
        $aspect = ($width / [double]$height).ToString('0.0000000000', [Globalization.CultureInfo]::InvariantCulture)
        $config += "`nHOS_OUTPUT_RES=$Resolution`nHOS_ASPECT=$aspect`n"
        if ($TextureBudgetMB -gt 0) { $config += "RX_VK_VRAM_MB=$TextureBudgetMB`n" }
        [IO.File]::WriteAllText((Join-Path $game 'hookshot_env.txt'), $config, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $game 'language.txt'), "$Language`n", [Text.UTF8Encoding]::new($false))
    }

    Write-Host '3/5 Generating keyboard and mouse prompts.'
    $first = Join-Path $Destination $selected[0]
    $mod = Join-Path $first 'mods/Keyboard prompts'
    & (Join-Path $source 'scripts/Build-Prompts.ps1') -Python $python -Romfs (Join-Path $base 'romfs') -Options (Join-Path $first 'hookshot_options.ini') -Output $mod -Cache $DownloadCache -ReceiptPath (Join-Path $receipts 'keyboard-prompts.json') | Out-Host
    foreach ($name in ($selected | Select-Object -Skip 1)) {
        $mods = Join-Path $Destination "$name/mods"
        New-Item -ItemType Directory -Path $mods -Force | Out-Null
        Copy-Item -LiteralPath $mod -Destination $mods -Recurse
    }
    if ($needUltra) {
        Write-Host '4/5 Installing Ultra components.'
        & $graphicsScript -Bin (Join-Path $Destination 'ultra/bin') -Cache $DownloadCache -NrRuntime $NrRuntime -ReceiptPath (Join-Path $receipts 'graphics.json') | Out-Host
    } else { Write-Host '4/5 Skipped: Ultra not selected.' }

    Write-Host '5/5 Creating the save folder, launcher and shortcuts.'
    $profile = Join-Path $Destination 'profile'
    New-Item -ItemType Directory -Path $profile -Force | Out-Null
    if ($ImportProfile) {
        if (Get-Process -Name hookshot -ErrorAction SilentlyContinue) {
            throw 'Hookshot was opened during the build. Close it before copying saves. The source profile is untouched.'
        }
        Copy-Item -LiteralPath (Join-Path $ImportProfile 'save') -Destination $profile -Recurse
        $backup = Join-Path $Destination 'backups/imported-save'
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $ImportProfile 'save') -Destination $backup -Recurse
    } else { New-Item -ItemType Directory -Path (Join-Path $profile 'save') -Force | Out-Null }
    New-Item -ItemType Directory -Path (Join-Path $Destination 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'Launch.ps1') -Destination $Destination
    Copy-Item -LiteralPath (Join-Path $source 'scripts/LauncherWindow.cs') -Destination (Join-Path $Destination 'scripts')
    $manifest = [ordered]@{
        schemaVersion=1; packageVersion=$packageVersion; hookshotVersion='2.1.0'; guestBuild='e0f3ccfa';
        resolution=$Resolution; romfs='base/romfs'; profile='profile';
        presets=[ordered]@{native=@{gameRoot='native';available=($selected -contains 'native')};ultra=@{gameRoot='ultra';available=($selected -contains 'ultra')}};
        createdUtc=[DateTime]::UtcNow.ToString('o')
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Destination 'install.json') -Encoding UTF8
    if (!$NoShortcuts) {
        $shortcutArgs = @{Destination=$Destination}
        if ($ShortcutDirectory) { $shortcutArgs.DesktopPath=$ShortcutDirectory }
        & (Join-Path $source 'scripts/New-Shortcuts.ps1') @shortcutArgs | Out-Host
    }
    $installState.status = 'installed'
    Save-InstallState
    Write-Host "Installed: $Destination"
    Write-Host 'Start the game from a desktop shortcut. The first visit to each scene compiles shaders.'
} catch {
    $installState.status = 'failed'
    $installState['error'] = $_.Exception.Message
    Save-InstallState
    throw
}
