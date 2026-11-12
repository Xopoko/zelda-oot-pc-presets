#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'Launch.ps1'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$fixture = Join-Path $tempParent ('Zelda launcher defaults ' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    Copy-Item -LiteralPath $source -Destination $fixture
    $launcher = Join-Path $fixture 'Launch.ps1'
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # Run like the shortcut does (-File, no -InstallRoot) from another directory.
    # With no install.json the launcher exits early; without -NoConsole there is no dialog.
    $startInfo.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Preset Native' -f $launcher
    $startInfo.WorkingDirectory = $tempParent
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.EnvironmentVariables.Remove('PSModulePath')
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'The missing installation receipt test did not finish.'
        }
        $log = Join-Path $fixture 'logs\launch-native.log'
        if ($process.ExitCode -eq 0 -or !(Test-Path -LiteralPath $log -PathType Leaf) -or
            (Get-Content -LiteralPath $log -Raw) -notmatch 'This folder has no completed installation') {
            throw ('Launcher did not resolve its implicit installation root. ' +
                $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
        }
    }
    finally { $process.Dispose() }
    Write-Host 'PASS: Windows PowerShell -File uses the launcher directory when -InstallRoot is omitted.'
}
finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
