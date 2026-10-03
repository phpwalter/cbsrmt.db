param(
    [Alias("Host")]
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Database = "cbsrmt",
    [string]$User = "root",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

$Python = Join-Path $Root ".venv/Scripts/python.exe"
if (-not (Test-Path $Python)) {
    throw "Python virtual environment not found at $Python. Create the venv and install requirements.txt."
}

if ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
    $securePassword = Read-Host "PostgreSQL password for $User" -AsSecureString
    $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
    }
}

$Dsn = "host=$HostName port=$Port dbname=$Database user=$User password=$env:PGPASSWORD"

$args = @(
    (Join-Path $Root "tools/update_canonical_episodes.py"),
    "--dsn", $Dsn,
    "--source", (Join-Path $Root "data/canonical_episodes.json"),
    "--report", (Join-Path $Root "reports/canonical-episode-update-report.json")
)

if ($DryRun) {
    $args += "--dry-run"
}

& $Python @args
if ($LASTEXITCODE -ne 0) {
    throw "Canonical episode update failed."
}
