# Hash-checked downloads shared by the installer scripts. Dot-source this file.

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Assert-FileHash([string]$Path, [string]$Sha256, [long]$Bytes = -1, [string]$Name = [IO.Path]::GetFileName($Path)) {
    $file = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (!$file -or $file.PSIsContainer) { throw "Missing $Name at $Path" }
    if ($Bytes -ge 0 -and $file.Length -ne $Bytes) {
        throw "Expected $Bytes bytes for $Name, found $($file.Length): $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Sha256) { throw "SHA-256 mismatch for ${Name}: expected $Sha256, got $actual ($Path)" }
}

# Moves a verified temporary file into the cache. Another installer sharing the
# cache may have finished the same file first; accept it if it verifies.
function Move-VerifiedFile([string]$Temporary, [string]$Path, [string]$Sha256, [long]$Bytes = -1) {
    try { [IO.File]::Move($Temporary, $Path) }
    catch [IO.IOException] {
        if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw }
        Assert-FileHash $Path $Sha256 $Bytes
    }
}

# Returns $Path, downloading $Url there first if needed. A cached file that
# fails verification is reported, never overwritten.
function Get-PinnedDownload([string]$Url, [string]$Path, [string]$Sha256, [long]$Bytes = -1) {
    if (Test-Path -LiteralPath $Path) {
        Assert-FileHash $Path $Sha256 $Bytes
        return $Path
    }
    $name = [IO.Path]::GetFileName($Path)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).partial"
    $ProgressPreference = 'SilentlyContinue'  # the progress bar makes Invoke-WebRequest very slow in 5.1
    if ($Bytes -ge 0) { Write-Host ('Downloading {0} ({1:N1} MiB)' -f $name, ($Bytes / 1MB)) }
    else { Write-Host "Downloading $name" }
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temporary
        Assert-FileHash $temporary $Sha256 $Bytes $name
        Move-VerifiedFile $temporary $Path $Sha256 $Bytes
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    return $Path
}
