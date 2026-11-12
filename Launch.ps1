#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Native', 'Ultra')]
    [string]$Preset = 'Native',
    [string]$InstallRoot = $PSScriptRoot,
    [string]$Profile,
    [switch]$NoConsole
)

$ErrorActionPreference = 'Stop'
$presetName = $Preset.ToLowerInvariant()
$launcherLog = $null

function Resolve-InstalledPath([string]$RelativePath) {
    if (!$RelativePath -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw 'The installation receipt contains an invalid path.'
    }
    $resolved = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (!$resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An installation receipt path points outside the installation.'
    }
    return $resolved
}

function Write-LaunchLog([string]$Message) {
    $line = '{0:o} {1}' -f [DateTime]::UtcNow, $Message
    Add-Content -LiteralPath $launcherLog -Encoding UTF8 -Value $line
    if (!$NoConsole) { Write-Host $Message }
}

function Read-CurrentLog([string]$Path) {
    $file = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($file -and $file.LastWriteTimeUtc -ge $started) {
        return (Get-Content -LiteralPath $Path -Tail 240 -ErrorAction SilentlyContinue) -join "`n"
    }
    return ''
}

function Get-LastRuntimeDestroy([string]$BridgeTail) {
    $matches = [regex]::Matches($BridgeTail, '(?m)^.*destroying the effect runtime.*$')
    if ($matches.Count -gt 0) { return $matches[$matches.Count - 1].Value }
    return ''
}

function Reset-EffectRuntime($Window, [string]$BeforeDestroy) {
    # Hookshot handles WM_SIZE even in its borderless fullscreen mode.
    if (![ZeldaOotLauncher.WindowControl]::Shrink($Window)) { return $false }
    try {
        Write-LaunchLog "Requested a temporary 20-pixel resize of game PID $($gameProcess.Id)."
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        $teardownObserved = $false
        while (!$gameProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            $afterDestroy = Get-LastRuntimeDestroy (Read-CurrentLog $bridgeLog)
            if ($afterDestroy -and $afterDestroy -ne $BeforeDestroy) {
                $teardownObserved = $true
                Write-LaunchLog 'Observed Vulkan effect runtime teardown.'
                break
            }
            Start-Sleep -Milliseconds 250
        }
        if (!$teardownObserved -and !$gameProcess.HasExited) {
            Write-LaunchLog 'No Vulkan effect runtime teardown was logged within 15 seconds.'
        }
    }
    finally {
        if (!$gameProcess.HasExited) {
            if (![ZeldaOotLauncher.WindowControl]::Restore($Window)) {
                throw 'Could not restore the game window. Press F11 twice to restore fullscreen.'
            }
            Write-LaunchLog "Requested restoration of the ${resolution} fullscreen size."
        }
    }
    return $true
}

function Wait-NeuralRendering {
    if (!('ZeldaOotLauncher.WindowControl' -as [type])) {
        Add-Type -Path (Join-Path $root 'scripts\LauncherWindow.cs')
    }
    $size = $resolution.Split('x')
    $width = [int]$size[0]
    $height = [int]$size[1]
    $dimensions = [regex]::Escape($resolution)
    $deliveredPattern = 'Vulkan frame \d+ delivered \(' + $dimensions + '\)'
    $successPattern = 'inline feature 18 evaluation succeeded \(count=(\d+), NR input ' +
        $dimensions + ' \(guides ' + $dimensions + '\), output ' + $dimensions + ' \[native\]\)'
    $deadline = $started.AddMinutes(8)
    $resetRequested = $false
    $hooksReady = $false
    $delivered = $false
    while (!$gameProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $reshadeTail = Read-CurrentLog $reshadeLog
        $bridgeTail = Read-CurrentLog $bridgeLog
        $hooksReady = $hooksReady -or ($reshadeTail -match 'D3D12 NGX hooks installed')
        $delivered = $delivered -or ($bridgeTail -match $deliveredPattern)
        $evaluation = [regex]::Matches($reshadeTail, $successPattern)
        $confirmed = $evaluation.Count -gt 0 -and
            [int]$evaluation[$evaluation.Count - 1].Groups[1].Value -ge 60

        if ($delivered -and $confirmed) {
            $window = [ZeldaOotLauncher.WindowControl]::Find($gameProcess.Id, $width, $height)
            if ($window) {
                Write-LaunchLog "DLSS 5 Feature 18 confirmed at ${resolution}, at least 60 successful evaluations."
                return
            }
        }

        # A first evaluation is evidence that the initial creation was already hooked.
        if (!$resetRequested -and $evaluation.Count -eq 0 -and $hooksReady -and $delivered) {
            $window = [ZeldaOotLauncher.WindowControl]::Find($gameProcess.Id, $width, $height)
            if ($window) {
                $resetRequested = Reset-EffectRuntime $window (Get-LastRuntimeDestroy $bridgeTail)
            }
        }
        Start-Sleep -Milliseconds 600
    }
    if ($gameProcess.HasExited) {
        if ($gameProcess.ExitCode -eq 0) {
            Write-LaunchLog 'The game closed before DLSS 5 activation was verified.'
            return
        }
        throw "Hookshot exited with code $($gameProcess.ExitCode) during startup. See $game\hookshot_log.txt."
    }
    throw "DLSS 5 activation at ${resolution} was not confirmed. The game is still open. Check $reshadeLog and $bridgeLog."
}

try {
    $root = (Resolve-Path -LiteralPath $InstallRoot).ProviderPath
    $rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $logDirectory = Join-Path $root 'logs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $launcherLog = Join-Path $logDirectory "launch-$presetName.log"
    $receiptPath = Join-Path $root 'install.json'
    if (!(Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw 'This folder has no completed installation. Run Install.ps1 first.'
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schemaVersion -ne 1 -or $receipt.resolution -notmatch '^[1-9]\d{2,4}x[1-9]\d{2,4}$') {
        throw 'This launcher does not recognize the installation receipt.'
    }
    $resolution = $receipt.resolution
    $selected = $receipt.presets.$presetName
    if (!$selected -or $selected.available -ne $true) {
        throw "The $Preset preset is not installed."
    }
    $game = Resolve-InstalledPath $selected.gameRoot
    $romfs = Resolve-InstalledPath $receipt.romfs
    $profilePath = Resolve-InstalledPath $receipt.profile
    if ($Profile) {
        $profileItem = Get-Item -LiteralPath $Profile
        if ($profileItem -isnot [IO.DirectoryInfo]) { throw '-Profile must be a filesystem directory.' }
        $profilePath = $profileItem.FullName
    }
    $bin = Join-Path $game 'bin'
    $exe = Join-Path $bin 'hookshot.exe'
    if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Hookshot is missing at $exe." }
    if (!(Test-Path -LiteralPath $romfs -PathType Container)) { throw "ROMFS is missing at $romfs." }
    if (!(Test-Path -LiteralPath $profilePath -PathType Container)) { throw "The save profile is missing at $profilePath." }
    if ($presetName -eq 'ultra') {
        foreach ($dependency in @('ReShade64.dll', 'ReShade64.json', 'nvngx_dlssnr.dll', 'nvngx_dlss.dll', 'dlss5-bridge.addon64', 'renodx-dlss5.addon64')) {
            if (!(Test-Path -LiteralPath (Join-Path $bin $dependency) -PathType Leaf)) {
                throw "Ultra is missing $dependency. See the installation guide."
            }
        }
    }

    $mutex = [Threading.Mutex]::new($false, 'Local\ZeldaOotPresetsGameLaunch')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(3000) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked -or (Get-Process -Name hookshot -ErrorAction SilentlyContinue)) {
            throw 'Hookshot is already starting or running. Close it before switching presets.'
        }

        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $exe
        $startInfo.WorkingDirectory = $game
        # Windows paths cannot contain quotes. Double final backslashes for the closing quote.
        $startInfo.Arguments = '--user "{0}" --romfs "{1}"' -f ($profilePath -replace '(\\+)$', '$1$1'), ($romfs -replace '(\\+)$', '$1$1')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        foreach ($name in @($startInfo.EnvironmentVariables.Keys)) {
            if ($name -match '^(HOS_|HOOKSHOT_|RX_|A64_|RESHADE_|VK_.*LAYER)' -or $name -eq 'DISABLE_VK_LAYER_reshade_1') {
                $startInfo.EnvironmentVariables.Remove($name)
            }
        }
        if ($presetName -eq 'ultra') {
            $startInfo.EnvironmentVariables['VK_IMPLICIT_LAYER_PATH'] = $bin
            $startInfo.EnvironmentVariables['RESHADE_BASE_PATH_OVERRIDE'] = $bin
            $bridgeLog = Join-Path $bin 'dlss5-bridge.log'
            $reshadeLog = Join-Path $bin 'ReShade.log'
            # These files belong to the finished session. Keep one prior run so a stale
            # success marker cannot be mistaken for activation in this launch.
            foreach ($path in @($bridgeLog, $reshadeLog)) {
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    Move-Item -LiteralPath $path -Destination "$path.previous" -Force
                }
            }
        }
        else {
            $startInfo.EnvironmentVariables['VK_LOADER_LAYERS_DISABLE'] = 'VK_LAYER_reshade'
            $startInfo.EnvironmentVariables['DISABLE_VK_LAYER_reshade_1'] = '1'
        }
        $started = [DateTime]::UtcNow
        $gameProcess = [Diagnostics.Process]::Start($startInfo)
        Write-LaunchLog "Started $Preset, PID $($gameProcess.Id), profile $profilePath."
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }

    if ($presetName -eq 'ultra') { Wait-NeuralRendering }
    elseif ($gameProcess.WaitForExit(1500) -and $gameProcess.ExitCode -ne 0) {
        throw "Hookshot exited with code $($gameProcess.ExitCode) during startup. See $game\hookshot_log.txt."
    }
}
catch {
    $message = $_.Exception.Message
    if ($launcherLog) {
        try { Write-LaunchLog "Error: $message" } catch { Write-Verbose $_.Exception.Message }
    }
    if ($NoConsole) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($message, 'Zelda Ocarina of Time', 'OK', 'Error')
    }
    throw
}
