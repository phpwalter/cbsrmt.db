param(
    [Alias("Host")]
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Database = "cbsrmt",
    [string]$User = "root",
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Required command 'python' was not found in PATH."
}

if (-not $ValidateOnly -and [string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
    $securePassword = Read-Host "PostgreSQL password for $User" -AsSecureString
    $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
    }
}

$VenvPython = Join-Path $Root ".venv/Scripts/python.exe"
if (-not (Test-Path $VenvPython)) {
    $VenvPython = "python"
}

$Dsn = "host=$HostName port=$Port dbname=$Database user=$User"
$argsList = @(
    (Join-Path $Root "tools/apply_cast_corrections.py"),
    "--dsn", $Dsn,
    "--data-dir", (Join-Path $Root "data")
)
if ($ValidateOnly) {
    $argsList += "--validate-only"
}

& $VenvPython @argsList
if ($LASTEXITCODE -ne 0) {
    throw "Cast correction promotion failed."
}

Write-Host "PASS: cast corrections validated and promoted."
