#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Nup,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$WorkRoot,
    [ValidateRange(0, 256)][int]$Jobs = 0,
    [string]$DownloadCache
)

$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$manifestPath = Join-Path $PSScriptRoot '../manifests/hookshot-2.1.0.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'Downloads.ps1')

function Get-FullLocalPath([string]$Path) {
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ($fullPath -notmatch '^[a-zA-Z]:\\') {
        throw "Use an absolute path on a local Windows drive: $Path"
    }
    return $fullPath
}

function Assert-PlainDirectory([string]$Path) {
    $item = Get-Item -Force -LiteralPath $Path
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a directory without a junction or symbolic link: $Path"
    }
}

function Assert-Hashes([string]$Root, $Files) {
    foreach ($file in $Files.PSObject.Properties) {
        Assert-FileHash (Join-Path $Root $file.Name) $file.Value
    }
}

function Expand-BuilderArchive([string]$Archive, [string]$Staging, $Part) {
    $archiveDestination = $Part.PSObject.Properties['destination']
    $archiveRoot = $Part.PSObject.Properties['root']
    $base = if ($archiveDestination) { Join-Path $Staging $archiveDestination.Value } else { $Staging }
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $segments = $name.TrimEnd('/').Split('/')
            if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000) {
                throw "Symbolic link in builder archive: $name"
            }
            foreach ($segment in $segments) {
                if ($segment -in @('', '.', '..') -or $segment -match '[\x00-\x1f<>:"|?*]|[ .]$' -or
                    $segment -match '^(CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\.|$)') {
                    throw "Invalid Windows path in builder archive: $name"
                }
            }
            if ($archiveRoot) {
                if ($segments[0] -cne $archiveRoot.Value) {
                    throw "Unexpected archive root in $name"
                }
                $segments[0] = $Part.rename
            }

            # LLVM includes nested headers beyond the legacy Win32 path limit.
            $output = '\\?\' + $base + '\' + ($segments -join '\')
            if ($name.EndsWith('/')) {
                [IO.Directory]::CreateDirectory($output) | Out-Null
                continue
            }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
            $src = $entry.Open()
            try {
                $dst = [IO.File]::Open($output, [IO.FileMode]::CreateNew)
                try { $src.CopyTo($dst) } finally { $dst.Dispose() }
            } finally { $src.Dispose() }
        }
    } finally { $zip.Dispose() }
}

function Initialize-Builder([string]$Work, [string]$Cache) {
    $builder = Join-Path $Work "builder-$($manifest.release)"
    $marker = Join-Path $builder '.manifest-sha256'
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    if (Test-Path -LiteralPath $builder) {
        Assert-PlainDirectory $builder
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
            (Get-Content -Raw -LiteralPath $marker).Trim() -ne $manifestHash) {
            throw "The builder cache belongs to a different package. Choose a new WorkRoot or move this folder aside: $builder"
        }
        Assert-Hashes $builder $manifest.builderFiles
        return (Join-Path $builder 'HookshotBuilder/tools')
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stage = Join-Path $Work ('.builder-stage-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    foreach ($part in $manifest.parts) {
        $name = [IO.Path]::GetFileName(([uri]$part.url).AbsolutePath)
        $zip = Get-PinnedDownload $part.url (Join-Path $Cache $name) $part.sha256 $part.bytes
        Write-Host "Extracting $([IO.Path]::GetFileName($zip))"
        Expand-BuilderArchive $zip $stage $part
    }
    Assert-Hashes $stage $manifest.builderFiles

    # The bundled Python processes spawn compilers and other console programs.
    # Scope console suppression to builds started by this script.
    $siteCustomize = @'
import os

if os.name == "nt" and os.environ.get("ZELDA_PRESETS_BACKGROUND_BUILD") == "1":
    import subprocess

    original_popen_init = subprocess.Popen.__init__

    def popen_without_console(self, *args, **kwargs):
        kwargs["creationflags"] = kwargs.get("creationflags", 0) | subprocess.CREATE_NO_WINDOW
        original_popen_init(self, *args, **kwargs)

    subprocess.Popen.__init__ = popen_without_console
'@
    $sitePath = Join-Path $stage 'HookshotBuilder/tools/python/Lib/sitecustomize.py'
    if (Test-Path -LiteralPath $sitePath) { throw "Unexpected sitecustomize.py in $stage" }
    [IO.File]::WriteAllText($sitePath, $siteCustomize, $utf8)
    [IO.File]::WriteAllText((Join-Path $stage '.manifest-sha256'), $manifestHash + "`n", $utf8)
    Assert-PlainDirectory $stage
    # Both paths are immediate children of the checked work directory.
    if ((Split-Path -Parent $stage) -ne $Work -or (Split-Path -Parent $builder) -ne $Work) {
        throw 'The builder stage resolved outside the work directory.'
    }
    [IO.Directory]::Move($stage, $builder)
    return (Join-Path $builder 'HookshotBuilder/tools')
}

function Invoke-ConsoleProgram([string]$File, [string[]]$Arguments, [string]$WorkingDirectory) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $File
    # Escape for the Windows C runtime argv parser. No shell interprets these values.
    $info.Arguments = ($Arguments | ForEach-Object {
        '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
    }) -join ' '
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    foreach ($key in @($info.EnvironmentVariables.Keys)) {
        if ($key -match '^(HOOKSHOT_|HOS_|A64_|RX_)' -or $key -eq 'WGPU_NATIVE') {
            $info.EnvironmentVariables.Remove($key)
        }
    }
    $info.EnvironmentVariables['ZELDA_PRESETS_BACKGROUND_BUILD'] = '1'
    $info.EnvironmentVariables['HOOKSHOT_NO_UPDATE_CHECK'] = '1'

    $process = [Diagnostics.Process]::Start($info)
    try {
        $stderr = $process.StandardError.ReadToEndAsync()
        while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
            Write-Host $line
        }
        $process.WaitForExit()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($errors) { Write-Host $errors }
        return $process.ExitCode
    } finally { $process.Dispose() }
}

if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'Hookshot needs 64-bit Windows.'
}
$inputNup = Get-Item -LiteralPath $Nup
if ($inputNup.PSIsContainer -or $inputNup.Extension -ne '.nup') {
    throw "Select your own supported .nup file: $Nup"
}
$Destination = (Get-FullLocalPath $Destination).TrimEnd('\')
$WorkRoot = (Get-FullLocalPath $WorkRoot).TrimEnd('\')
if ($Destination -match '^[a-zA-Z]:$' -or $WorkRoot -match '^[a-zA-Z]:$' -or
    $WorkRoot -eq $Destination -or $WorkRoot.StartsWith($Destination + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Use a dedicated empty Destination folder and a separate WorkRoot.'
}
if (Test-Path -LiteralPath $Destination) {
    Assert-PlainDirectory $Destination
    if (Get-ChildItem -Force -LiteralPath $Destination | Select-Object -First 1) {
        throw "Build destination is not empty: $Destination"
    }
}
if ($DownloadCache) { $DownloadCache = (Get-FullLocalPath $DownloadCache).TrimEnd('\') }
else { $DownloadCache = Join-Path $WorkRoot 'downloads' }
if ($DownloadCache -match '^[a-zA-Z]:$' -or $DownloadCache -eq $Destination -or
    $DownloadCache.StartsWith($Destination + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Use a DownloadCache outside the build destination.'
}
[IO.Directory]::CreateDirectory($WorkRoot) | Out-Null
[IO.Directory]::CreateDirectory($DownloadCache) | Out-Null
Assert-PlainDirectory $WorkRoot
Assert-PlainDirectory $DownloadCache

$lockPath = Join-Path $WorkRoot '.build.lock'
try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
catch [IO.IOException] { throw "Another build has this work directory open: $WorkRoot" }
try {
    $toolsRoot = Initialize-Builder $WorkRoot $DownloadCache
    $python = Join-Path $toolsRoot 'python/python.exe'
    $makeGame = Join-Path $toolsRoot 'nx2/make_game.py'
    $work = Join-Path $WorkRoot 'compile-work'
    $checkLog = Join-Path $WorkRoot 'nup-check.log'
    $common = @('-I', '-B', $makeGame, '--nup', $inputNup.FullName, '--work', $work)
    $checkExit = Invoke-ConsoleProgram $python ($common + @('--check', '--log', $checkLog)) $toolsRoot
    $probe = Get-Content -Raw -LiteralPath $checkLog
    $title = [regex]::Escape($manifest.game.titleId)
    $build = [regex]::Escape($manifest.game.buildId)
    if ($checkExit -ne 0 -or $probe -notmatch "(?m)^@@check ok .*\b$build\b" -or
        $probe -notmatch "(?m)^title \d+: $title v$($manifest.game.nupVersion)\b") {
        throw "Expected Zelda $($manifest.game.version), title $title, NUP v$($manifest.game.nupVersion), build $build. See $checkLog"
    }

    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $buildLog = Join-Path $WorkRoot 'hookshot-build.log'
    Write-Host "Building Hookshot $($manifest.release). Progress log: $buildLog"
    $buildArgs = $common + @('--out', $Destination, '--no-prepare-shaders', '--log', $buildLog, '--jobs', [string]$Jobs)
    $buildExit = Invoke-ConsoleProgram $python $buildArgs $toolsRoot
    if ($buildExit -ne 0 -or -not (Select-String -LiteralPath $buildLog -Pattern '^@@done ' -Quiet)) {
        throw "Hookshot build did not complete. See $buildLog"
    }
    foreach ($path in 'bin/hookshot.exe', 'bin/hookshot_vk.dll', 'image.bin', 'hookshot_shaders.bin', 'romfs') {
        if (-not (Test-Path -LiteralPath (Join-Path $Destination $path))) {
            throw "Build output is missing $path in $Destination"
        }
    }

    $resultPath = Join-Path $WorkRoot 'build-receipt.json'
    $result = [pscustomobject]@{
        ResultPath = $resultPath
        GameRoot = $Destination
        ToolsPython = $python
        HookshotRelease = $manifest.release
        Game = $manifest.game
        NupBytes = $inputNup.Length
        CheckLog = $checkLog
        BuildLog = $buildLog
    }
    [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 4) + "`n", $utf8)
    $result
} finally { $lock.Dispose() }
