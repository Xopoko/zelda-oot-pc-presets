[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(Mandatory, ParameterSetName='Install')] [string]$Bin,
    [Parameter(Mandatory)] [string]$Cache,
    [string]$NrRuntime,
    [Parameter(Mandatory, ParameterSetName='Install')] [string]$ReceiptPath,
    [Parameter(Mandatory, ParameterSetName='Resolve')] [switch]$ResolveRuntimeOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Assert-PinnedFile {
    param([string]$Path, $Pin)

    $file = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (!$file -or $file.PSIsContainer -or $file.Length -ne $Pin.bytes) {
        throw "Expected $($Pin.bytes) bytes for $($Pin.file). Check the selected file or cached download."
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Pin.sha256) {
        throw "SHA-256 mismatch for $($Pin.file). Expected $($Pin.sha256), got $actual."
    }
}

function Get-PinnedDownload {
    param($Pin)

    $path = Join-Path $Cache "$($Pin.sha256)-$($Pin.file)"
    if (Test-Path -LiteralPath $path) {
        Assert-PinnedFile $path $Pin
        return $path
    }

    $temporary = "$path.$([Guid]::NewGuid().ToString('N')).download"
    Write-Host "Downloading $($Pin.id) ..."
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Pin.url -OutFile $temporary
        Assert-PinnedFile $temporary $Pin
        try {
            [IO.File]::Move($temporary, $path)
        }
        catch [IO.IOException] {
            # Another install can complete the same download while this one runs.
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw }
            Assert-PinnedFile $path $Pin
        }
    }
    finally {
        Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue
    }
    return $path
}

function Expand-PinnedGraphicsArchive {
    param([string]$Path, $Pin)

    if ($Pin.archive -eq 'sfx-zip') {
        # ReShade's installer appends a ZIP with offsets relative to this point.
        # The enclosing installer is hash checked before any bytes are read here.
        $bytes = [IO.File]::ReadAllBytes($Path)
        $offset = [int]$Pin.zipOffset
        if ([BitConverter]::ToUInt32($bytes, $offset) -ne 0x04034B50) {
            throw 'The pinned ReShade installer has an unexpected ZIP header.'
        }
        $stream = [IO.MemoryStream]::new($bytes, $offset, $bytes.Length - $offset)
    }
    else {
        $stream = [IO.File]::OpenRead($Path)
    }

    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            foreach ($file in $Pin.entries) {
                $entry = $archive.GetEntry($file.file)
                if (!$entry -or $entry.Length -ne $file.bytes) {
                    throw "The archive $($Pin.file) is missing the expected entry $($file.file)."
                }
                $target = Join-Path $stage $file.file
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target)
                Assert-PinnedFile $target $file
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Resolve-PinnedRuntime {
    if ($NrRuntime) {
        # An explicitly supplied file always wins; never conceal a bad override
        # by downloading a replacement instead.
        $local = (Get-Item -LiteralPath $NrRuntime).FullName
        Assert-PinnedFile $local $manifest.nrRuntime
        return $local
    }
    $target = Join-Path $Cache "$($manifest.nrRuntime.sha256)-$($manifest.nrRuntime.file)"
    if (Test-Path -LiteralPath $target) {
        Assert-PinnedFile $target $manifest.nrRuntime
        return $target
    }
    [void][IO.Directory]::CreateDirectory($Cache)
    $archivePath = Get-PinnedDownload $manifest.nrRuntime.download
    $temporary = "$target.$([Guid]::NewGuid().ToString('N')).extracting"
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            # Extract only the exact pinned DLL, never the archive's other files.
            $entries = @($zip.Entries | Where-Object { $_.FullName -ceq $manifest.nrRuntime.download.entry })
            if ($entries.Count -ne 1 -or $entries[0].Length -ne $manifest.nrRuntime.bytes) {
                throw 'The pinned NR archive does not contain the expected single DLL entry.'
            }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $temporary)
        } finally { $zip.Dispose() }
        Assert-PinnedFile $temporary $manifest.nrRuntime
        try { [IO.File]::Move($temporary, $target) }
        catch [IO.IOException] {
            if (!(Test-Path -LiteralPath $target -PathType Leaf)) { throw }
            Assert-PinnedFile $target $manifest.nrRuntime
        }
    } finally { Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue }
    return $target
}

$repo = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $repo 'manifests/graphics.json') -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw 'Unsupported graphics manifest schema.' }
$Cache = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Cache)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
if ($ResolveRuntimeOnly) {
    Resolve-PinnedRuntime
    return
}
$Bin = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Bin)
$ReceiptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReceiptPath)

$files = @($manifest.nrRuntime)
foreach ($download in $manifest.downloads) {
    if ($download.archive -eq 'file') { $files += $download }
    else { $files += $download.entries }
}
$config = @('ReShade.ini', 'DepthOnly.ini', 'ZeldaDepthTap.fx', 'dlss5-bridge.cfg')
$names = @($files | ForEach-Object { $_.file }) + $config
foreach ($name in $names) {
    $target = Join-Path $Bin $name
    if ((Test-Path -LiteralPath $target) -or $target -eq $ReceiptPath) {
        throw "Graphics staging requires a fresh preset directory. Conflicting path: $target"
    }
}
if (Test-Path -LiteralPath $ReceiptPath) { throw "Graphics receipt already exists: $ReceiptPath" }

$runtime = Resolve-PinnedRuntime

$null = [IO.Directory]::CreateDirectory($Cache)
$null = [IO.Directory]::CreateDirectory($Bin)
$null = [IO.Directory]::CreateDirectory((Split-Path -Parent $ReceiptPath))
$stage = Join-Path $Bin ('.graphics-' + [Guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($stage)
$temporaryReceipt = "$ReceiptPath.$([Guid]::NewGuid().ToString('N')).tmp"
$installed = [Collections.Generic.List[string]]::new()
try {
    foreach ($download in $manifest.downloads) {
        $archivePath = Get-PinnedDownload $download
        if ($download.archive -eq 'file') {
            $destination = Join-Path $stage $download.file
            [IO.File]::Copy($archivePath, $destination)
            Assert-PinnedFile $destination $download
        }
        else {
            Expand-PinnedGraphicsArchive $archivePath $download
        }
    }
    $stagedRuntime = Join-Path $stage $manifest.nrRuntime.file
    [IO.File]::Copy($runtime, $stagedRuntime)
    Assert-PinnedFile $stagedRuntime $manifest.nrRuntime
    foreach ($name in $config) {
        [IO.File]::Copy((Join-Path $repo "presets/ultra-bin/$name"), (Join-Path $stage $name))
    }

    $receipt = [ordered]@{
        schemaVersion = 1
        preset = 'Ultra'
        nrRuntime = $manifest.nrRuntime
        files = @(foreach ($name in $names) {
            $path = Join-Path $stage $name
            [ordered]@{
                file = $name
                bytes = (Get-Item -LiteralPath $path).Length
                sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
    }
    [IO.File]::WriteAllText($temporaryReceipt, ($receipt | ConvertTo-Json -Depth 5))
    foreach ($name in $names) {
        $target = Join-Path $Bin $name
        [IO.File]::Move((Join-Path $stage $name), $target)
        $installed.Add($target)
    }
    [IO.File]::Move($temporaryReceipt, $ReceiptPath)
}
catch {
    foreach ($path in $installed) { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
    throw
}
finally {
    Remove-Item -LiteralPath $temporaryReceipt -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $stage -File | Remove-Item -ErrorAction SilentlyContinue
    [IO.Directory]::Delete($stage)
}

Write-Host 'Ultra components staged and verified. The community NR runtime has a known Authenticode HashMismatch.'
