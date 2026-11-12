[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Python,
    [Parameter(Mandatory = $true)][string]$Romfs,
    [Parameter(Mandatory = $true)][string]$Options,
    [Parameter(Mandatory = $true)][string]$Output,
    [Parameter(Mandatory = $true)][string]$Cache,
    [Parameter(Mandatory = $true)][string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$pythonPath = (Resolve-Path -LiteralPath $Python).ProviderPath
$romfsPath = (Resolve-Path -LiteralPath $Romfs).ProviderPath
$optionsPath = (Resolve-Path -LiteralPath $Options).ProviderPath
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
$cachePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Cache)
$receiptFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReceiptPath)
if ((Test-Path -LiteralPath $outputPath) -or (Test-Path -LiteralPath $receiptFile)) {
    throw 'Choose a new prompt mod folder and a new receipt file.'
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../manifests/prompts.json') | ConvertFrom-Json
$encoder = $manifest.astcenc
[void][IO.Directory]::CreateDirectory($cachePath)
$archive = Join-Path $cachePath ([IO.Path]::GetFileName(([uri]$encoder.url).AbsolutePath))
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    $download = "$archive.$([guid]::NewGuid().ToString('N')).partial"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $encoder.url -OutFile $download
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $encoder.sha256) {
            throw "The astcenc $($encoder.version) download does not match its pinned SHA-256."
        }
        try {
            [IO.File]::Move($download, $archive)
        } catch [IO.IOException] {
            if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw }
        }
    } finally {
        [IO.File]::Delete($download)
    }
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $encoder.sha256) {
    throw "The astcenc cache archive has an unexpected SHA-256. Remove the file and retry: $archive"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$encoderPath = Join-Path $cachePath ("astcenc-" + [guid]::NewGuid().ToString('N') + '.exe')
try {
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entry = $zip.GetEntry($encoder.entry)
        if (-not $entry) { throw "Missing $($encoder.entry) in the pinned astcenc archive." }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $encoderPath)
    } finally {
        $zip.Dispose()
    }

    $script = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../tools/prompts/build.py'))
    $arguments = @('-B', '-E', $script, '--romfs', $romfsPath, '--options', $optionsPath,
        '--output', $outputPath, '--astcenc', $encoderPath)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $pythonPath
    # These arguments are fixed flags and Windows paths. Preserve any trailing backslashes.
    $start.Arguments = ($arguments | ForEach-Object { '"' + ($_ -replace '(\\+)$', '$1$1') + '"' }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $result = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Keyboard prompt generation failed: $errorText" }
    } finally {
        $process.Dispose()
    }

    $receipt = $result | ConvertFrom-Json
    if ($receipt.font_glyphs.Count -ne 35 -or $receipt.atlas_masks.Count -ne 10) {
        throw 'Keyboard prompt generation returned incomplete glyph or atlas coverage.'
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($receiptFile))
    $receiptStream = [IO.File]::Open($receiptFile, [IO.FileMode]::CreateNew)
    try {
        $writer = [IO.StreamWriter]::new($receiptStream)
        try { $writer.Write($result) } finally { $writer.Dispose() }
    } finally {
        $receiptStream.Dispose()
    }
} finally {
    [IO.File]::Delete($encoderPath)
}
