#requires -Version 5.1
# Offline checks for scripts/Downloads.ps1, using file:// URLs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Downloads.ps1')
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zelda-download-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try {
    $source = Join-Path $temporary 'source.bin'
    [IO.File]::WriteAllText($source, 'payload')
    $url = ([uri]$source).AbsoluteUri
    $sha = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $cache = Join-Path $temporary 'cache'

    $path = Join-Path $cache 'good.bin'
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # Only Windows PowerShell's Invoke-WebRequest accepts file:// URLs.
        [void](Get-PinnedDownload $url $path $sha 7 6>$null)
        if ([IO.File]::ReadAllText($path) -ne 'payload') { throw 'Download content differs.' }
        foreach ($case in @(@{Sha=('0' * 64); Bytes=7; Pattern='SHA-256 mismatch'}, @{Sha=$sha; Bytes=8; Pattern='Expected 8 bytes'})) {
            try { [void](Get-PinnedDownload $url (Join-Path $cache 'bad.bin') $case.Sha $case.Bytes 6>$null); throw 'accepted' }
            catch { if ($_.Exception.Message -notmatch $case.Pattern) { throw } }
        }
        $left = @(Get-ChildItem -LiteralPath $cache | ForEach-Object { $_.Name })
        if ($left.Count -ne 1 -or $left[0] -ne 'good.bin') { throw "Unexpected cache contents: $left" }
    }
    else {
        [void][IO.Directory]::CreateDirectory($cache)
        Copy-Item -LiteralPath $source -Destination $path
    }
    # A verified cached file is reused without touching the URL.
    [void](Get-PinnedDownload 'file:///missing' $path $sha 7)

    [IO.File]::WriteAllText($path, 'damaged')
    try { [void](Get-PinnedDownload $url $path $sha 7); throw 'accepted' }
    catch { if ($_.Exception.Message -notmatch 'SHA-256 mismatch') { throw } }
    if ([IO.File]::ReadAllText($path) -ne 'damaged') { throw 'A corrupt cached file was overwritten.' }
    Write-Host 'PASS: downloads are verified, cached, and never overwrite a bad cache entry.'
}
finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
