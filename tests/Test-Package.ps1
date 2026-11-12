#requires -Version 5.1
[CmdletBinding()]
param([string]$Python)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = @()
Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    $errors += $parseErrors
}
if ($errors.Count) { throw ($errors | Out-String) }
Get-ChildItem -LiteralPath (Join-Path $root 'manifests') -Filter '*.json' | ForEach-Object {
    $null = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
}

# Exercise refusal before a build or download, proving existing data is retained.
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zelda-package-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$nup = Join-Path $temporary 'game [test].nup'
[IO.File]::WriteAllText($nup, 'not a game')
$existing = Join-Path $temporary 'existing installation'
New-Item -ItemType Directory -Path $existing | Out-Null
$marker = Join-Path $existing 'save-marker.txt'
[IO.File]::WriteAllText($marker, 'preserve me')
function Expect-Refusal([hashtable]$Arguments, [string]$Pattern) {
    $caught = $false
    try { & (Join-Path $root 'Install.ps1') @Arguments }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $caught = $true
    }
    if (!$caught) { throw "Expected refusal: $Pattern" }
}
Expect-Refusal @{Nup=$nup; Destination=$existing} 'Destination is not empty'
if ([IO.File]::ReadAllText($marker) -ne 'preserve me') { throw 'Existing data changed.' }
$missingNrDestination = Join-Path $temporary 'missing nr'
Expect-Refusal @{Nup=$nup; Destination=$missingNrDestination; Preset='Both'} 'Ultra needs'
if (Test-Path -LiteralPath $missingNrDestination) { throw 'Missing NR created a partial installation.' }
$wrongNrDestination = Join-Path $temporary 'wrong nr'
Expect-Refusal @{Nup=$nup; Destination=$wrongNrDestination; Preset='Both'; NrRuntime=$nup} 'NR runtime is not'
if (Test-Path -LiteralPath $wrongNrDestination) { throw 'Wrong NR created a partial installation.' }
Expect-Refusal @{Nup=$nup; Destination=(Join-Path $root '.local/test-install')} 'outside this source checkout'
# A relative path must follow PowerShell's location, not the host process CWD.
Push-Location $temporary
try { Expect-Refusal @{Nup=$nup; Destination='existing installation'} 'Destination is not empty' }
finally { Pop-Location }
if ($Python) {
    & $Python -I -B (Join-Path $PSScriptRoot 'test_scene_patch.py')
    if ($LASTEXITCODE -ne 0) { throw 'Scene-patch behavioral checks failed.' }
}
Write-Host 'PASS: PowerShell syntax, JSON, save-preserving refusal, NR preflight and source-checkout isolation.'
# The directory contains only this test's tiny text fixtures. Verify its parent first.
if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($temporary)) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')) {
    throw 'Unexpected test temporary directory.'
}
Remove-Item -LiteralPath $temporary -Recurse -Force
