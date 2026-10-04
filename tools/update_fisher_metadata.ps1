param(
    [Alias("Host")]
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Database = "cbsrmt",
    [string]$User = "root",
    [string]$Source = "data/fisher_rubric_dataset_updated.json",
    [string]$Report = "reports/fisher-metadata-update-report.json",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

$Python = Join-Path $Root ".venv/Scripts/python.exe"
if (-not (Test-Path $Python)) {
    throw "Python virtual environment not found at $Python. Run install/fresh_install.ps1 once or create the venv and install requirements.txt."
}

$SourcePath = if ([System.IO.Path]::IsPathRooted($Source)) {
    $Source
}
else {
    Join-Path $Root $Source
}

$ReportPath = if ([System.IO.Path]::IsPathRooted($Report)) {
    $Report
}
else {
    Join-Path $Root $Report
}

if (-not (Test-Path $SourcePath)) {
    throw "Fisher dataset not found: $SourcePath"
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
    (Join-Path $Root "tools/import_fisher_data.py"),
    "--dsn", $Dsn,
    "--source", $SourcePath,
    "--report", $ReportPath,
    "--metadata-only"
)

if (-not $Apply) {
    $args += "--dry-run"
    Write-Host "Running Fisher metadata update in DRY-RUN mode." -ForegroundColor Yellow
    Write-Host "No database changes will be committed." -ForegroundColor Yellow
    Write-Host "Use -Apply to commit verified updates." -ForegroundColor Yellow
}
else {
    Write-Host "Applying Fisher metadata updates to database..." -ForegroundColor Cyan
}

& $Python @args
if ($LASTEXITCODE -ne 0) {
    throw "Fisher metadata update failed."
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run complete. Review:" -ForegroundColor Green
    Write-Host "  $ReportPath"
}
else {
    Write-Host ""
    Write-Host "Fisher metadata update complete." -ForegroundColor Green
    Write-Host "Report:" -ForegroundColor Green
    Write-Host "  $ReportPath"
}
