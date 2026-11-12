#requires -Version 5.1
# Offline negative-path checks. The real cold-download check is documented separately.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'scripts/Install-Graphics.ps1'
$pin = (Get-Content -Raw -LiteralPath (Join-Path $root 'manifests/graphics.json') | ConvertFrom-Json).nrRuntime
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zelda-nr-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
function Expect-NrRefusal([hashtable]$Arguments, [string]$Pattern) {
    $caught = $false
    try { & $module @Arguments | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $caught = $true
    }
    if (!$caught) { throw "Expected NR refusal: $Pattern" }
}
try {
    $badOverride = Join-Path $temporary 'wrong.dll'
    [IO.File]::WriteAllText($badOverride, 'wrong')
    $emptyCache = Join-Path $temporary 'cache-not-created'
    Expect-NrRefusal @{ResolveRuntimeOnly=$true;Cache=$emptyCache;NrRuntime=$badOverride} 'Expected .* bytes'
    if (Test-Path -LiteralPath $emptyCache) { throw 'A bad explicit override triggered a download/cache write.' }

    $corruptCache = Join-Path $temporary 'corrupt cache'
    [void][IO.Directory]::CreateDirectory($corruptCache)
    $badCached = Join-Path $corruptCache "$($pin.sha256)-$($pin.file)"
    [IO.File]::WriteAllText($badCached, 'corrupt')
    Expect-NrRefusal @{ResolveRuntimeOnly=$true;Cache=$corruptCache} 'Expected .* bytes'
    if ([IO.File]::ReadAllText($badCached) -ne 'corrupt' -or @(Get-ChildItem -LiteralPath $corruptCache).Count -ne 1) {
        throw 'A rejected cache entry was overwritten or silently replaced.'
    }

    $existingBin = Join-Path $temporary 'existing bin'
    [void][IO.Directory]::CreateDirectory($existingBin)
    $marker = Join-Path $existingBin 'ReShade64.dll'
    [IO.File]::WriteAllText($marker, 'preserve existing graphics')
    Expect-NrRefusal @{Bin=$existingBin;Cache=$emptyCache;ReceiptPath=(Join-Path $temporary 'receipt.json')} 'fresh preset directory'
    if ((Test-Path -LiteralPath $emptyCache) -or [IO.File]::ReadAllText($marker) -ne 'preserve existing graphics') {
        throw 'Conflicting preset was modified or caused a download.'
    }
    Write-Host 'PASS: bad override, corrupt NR cache and existing graphics fail without fallback or overwrite.'
} finally {
    $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($temporary))
    if ($parent -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')) { throw 'Unexpected test directory.' }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
