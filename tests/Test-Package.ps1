#requires -Version 5.1
# Offline package checks. Pass -Python to also run the scene-patch tests.
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

function Expect-Refusal([hashtable]$Arguments, [string]$Pattern) {
    try { & (Join-Path $root 'Install.ps1') @Arguments }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected refusal: $Pattern"
}

# The installer must refuse these before building, downloading or touching existing data.
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('zelda-package-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $nup = Join-Path $temporary 'game [test].nup'
    [IO.File]::WriteAllText($nup, 'not a game')
    $existing = Join-Path $temporary 'existing installation'
    New-Item -ItemType Directory -Path $existing | Out-Null
    $marker = Join-Path $existing 'save-marker.txt'
    [IO.File]::WriteAllText($marker, 'preserve me')

    Expect-Refusal @{Nup=$nup; Destination=$existing} 'Destination is not empty'
    if ([IO.File]::ReadAllText($marker) -ne 'preserve me') { throw 'Existing data changed.' }

    $wrongNrDestination = Join-Path $temporary 'wrong nr'
    Expect-Refusal @{Nup=$nup; Destination=$wrongNrDestination; NrRuntime=$nup} 'NrRuntime is not the pinned'
    if (Test-Path -LiteralPath $wrongNrDestination) { throw 'A wrong -NrRuntime created a partial installation.' }

    Expect-Refusal @{Nup=$nup; Destination=(Join-Path $root '.local/test-install')} 'outside this source checkout'

    # A relative destination follows PowerShell's location, not the process CWD.
    Push-Location $temporary
    try { Expect-Refusal @{Nup=$nup; Destination='existing installation'} 'Destination is not empty' }
    finally { Pop-Location }
}
finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
Write-Host 'PASS: PowerShell syntax, JSON manifests and installer refusals.'

if ($Python) {
    & $Python -I -B (Join-Path $PSScriptRoot 'test_scene_patch.py')
    if ($LASTEXITCODE -ne 0) { throw 'Scene-patch tests failed.' }
}
& (Join-Path $PSScriptRoot 'Test-Downloads.ps1')
& (Join-Path $PSScriptRoot 'Test-NrResolution.ps1')
& (Join-Path $PSScriptRoot 'Test-LauncherDefaults.ps1')
