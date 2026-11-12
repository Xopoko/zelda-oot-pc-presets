#requires -Version 5.1
# Installs the pinned Ultra files from manifests/graphics.json into a preset's
# bin directory. -ResolveRuntimeOnly only fetches and verifies the NR runtime
# and returns its path, so Install.ps1 can fail before the long build.
[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(Mandatory, ParameterSetName='Install')][string]$Bin,
    [Parameter(Mandatory)][string]$Cache,
    [string]$NrRuntime,
    [Parameter(Mandatory, ParameterSetName='Install')][string]$ReceiptPath,
    [Parameter(Mandatory, ParameterSetName='Resolve')][switch]$ResolveRuntimeOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Downloads.ps1')

function Assert-Pin([string]$Path, $Pin) { Assert-FileHash $Path $Pin.sha256 $Pin.bytes $Pin.file }

function Get-Pin($Pin) {
    Get-PinnedDownload $Pin.url (Join-Path $Cache "$($Pin.sha256)-$($Pin.file)") $Pin.sha256 $Pin.bytes
}

function Expand-PinnedEntries([string]$Path, $Pin) {
    if ($Pin.archive -eq 'sfx-zip') {
        # ReShade's setup executable has a ZIP appended at a fixed offset.
        $bytes = [IO.File]::ReadAllBytes($Path)
        $offset = [int]$Pin.zipOffset
        if ([BitConverter]::ToUInt32($bytes, $offset) -ne 0x04034B50) {
            throw 'The pinned ReShade installer has an unexpected ZIP header.'
        }
        $stream = [IO.MemoryStream]::new($bytes, $offset, $bytes.Length - $offset)
    }
    else { $stream = [IO.File]::OpenRead($Path) }
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            foreach ($file in $Pin.entries) {
                $entry = $archive.GetEntry($file.file)
                if (!$entry) { throw "$($Pin.file) has no entry $($file.file)." }
                $target = Join-Path $Bin $file.file
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target)
                Assert-Pin $target $file
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Resolve-NrRuntime {
    $pin = $manifest.nrRuntime
    if ($NrRuntime) {
        # Never replace a bad explicit file with a download.
        $local = (Get-Item -LiteralPath $NrRuntime).FullName
        try { Assert-Pin $local $pin }
        catch { throw "-NrRuntime is not the pinned NR runtime 310.8.0 (see docs/DEPENDENCIES.md). $($_.Exception.Message)" }
        return $local
    }
    $target = Join-Path $Cache "$($pin.sha256)-$($pin.file)"
    if (Test-Path -LiteralPath $target) {
        Assert-Pin $target $pin
        return $target
    }
    $archivePath = Get-Pin $pin.download
    $temporary = "$target.$([guid]::NewGuid().ToString('N')).partial"
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $entry = $zip.GetEntry($pin.download.entry)
            if (!$entry) { throw "$($pin.download.file) has no entry $($pin.download.entry)." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $temporary)
        }
        finally { $zip.Dispose() }
        Assert-Pin $temporary $pin
        Move-VerifiedFile $temporary $target $pin.sha256 $pin.bytes
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    return $target
}

$repo = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -Raw -LiteralPath (Join-Path $repo 'manifests/graphics.json') | ConvertFrom-Json
$Cache = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Cache)
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if ($ResolveRuntimeOnly) { return Resolve-NrRuntime }

$Bin = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Bin)
$ReceiptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReceiptPath)
$config = 'ReShade.ini', 'DepthOnly.ini', 'ZeldaDepthTap.fx', 'dlss5-bridge.cfg'
$names = @($manifest.nrRuntime.file)
foreach ($download in $manifest.downloads) {
    if ($download.archive -eq 'file') { $names += $download.file }
    else { $names += @($download.entries | ForEach-Object { $_.file }) }
}
$names += $config

# Refuse before downloading anything if this would overwrite an existing preset.
foreach ($name in $names) {
    $target = Join-Path $Bin $name
    if (Test-Path -LiteralPath $target) {
        throw "Graphics staging requires a fresh preset directory. Conflicting path: $target"
    }
}
if (Test-Path -LiteralPath $ReceiptPath) { throw "Graphics receipt already exists: $ReceiptPath" }

$runtime = Resolve-NrRuntime
[void][IO.Directory]::CreateDirectory($Bin)
foreach ($download in $manifest.downloads) {
    $path = Get-Pin $download
    if ($download.archive -eq 'file') { [IO.File]::Copy($path, (Join-Path $Bin $download.file)) }
    else { Expand-PinnedEntries $path $download }
}
[IO.File]::Copy($runtime, (Join-Path $Bin $manifest.nrRuntime.file))
foreach ($name in $config) {
    [IO.File]::Copy((Join-Path $repo "presets/ultra-bin/$name"), (Join-Path $Bin $name))
}

$receipt = [ordered]@{
    schemaVersion = 1
    preset = 'Ultra'
    nrRuntime = $manifest.nrRuntime
    files = @(foreach ($name in $names) {
        $path = Join-Path $Bin $name
        [ordered]@{
            file = $name
            bytes = (Get-Item -LiteralPath $path).Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ReceiptPath))
[IO.File]::WriteAllText($ReceiptPath, ($receipt | ConvertTo-Json -Depth 5))
Write-Host 'Ultra components installed.'
