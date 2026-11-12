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

. (Join-Path $PSScriptRoot 'Downloads.ps1')
$encoder = (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../manifests/prompts.json') | ConvertFrom-Json).astcenc
$archive = Join-Path $cachePath ([IO.Path]::GetFileName(([uri]$encoder.url).AbsolutePath))
$archive = Get-PinnedDownload $encoder.url $archive $encoder.sha256

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
    # Double trailing backslashes so they don't escape the closing quote.
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
    [IO.File]::WriteAllText($receiptFile, $result)
} finally {
    [IO.File]::Delete($encoderPath)
}
