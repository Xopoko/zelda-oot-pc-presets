#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Destination,
    [string]$DesktopPath = [Environment]::GetFolderPath('DesktopDirectory')
)

$ErrorActionPreference = 'Stop'

function Install-LauncherBootstrap([string]$Target, [string]$StampPath) {
    $source = Join-Path $PSScriptRoot 'LauncherBootstrap.cs'
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if (Test-Path -LiteralPath $Target) {
        if (Test-Path -LiteralPath $StampPath -PathType Leaf) {
            $stamp = Get-Content -LiteralPath $StampPath -Raw | ConvertFrom-Json
            if ($stamp.sourceSha256 -eq $sourceHash -and
                (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -eq $stamp.executableSha256) {
                return
            }
        }
        throw 'The installed ZeldaLauncher.exe differs from this package. Use the matching package source or a new installation folder.'
    }

    $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw 'The Windows .NET Framework x64 compiler is required to create desktop shortcuts.'
    }
    $temporary = Join-Path $root ('ZeldaLauncher-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $compiler
        $startInfo.Arguments = '/nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /out:"{0}" "{1}"' -f $temporary, $source
        $startInfo.WorkingDirectory = $root
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
                throw ('Could not compile ZeldaLauncher.exe. ' + $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
            }
        }
        finally { $process.Dispose() }

        $stamp = @{sourceSha256=$sourceHash; executableSha256=(Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash}
        New-Item -ItemType Directory -Path (Split-Path -Parent $StampPath) -Force | Out-Null
        [IO.File]::Move($temporary, $Target)
        try { $stamp | ConvertTo-Json | Set-Content -LiteralPath $StampPath -Encoding UTF8 }
        catch {
            Remove-Item -LiteralPath $Target -Force
            throw
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
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
Install-LauncherBootstrap $bootstrap (Join-Path $root 'receipts\launcher-bootstrap.json')
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
    # Preserve existing shortcuts from another install. Reuse this install's link.
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
