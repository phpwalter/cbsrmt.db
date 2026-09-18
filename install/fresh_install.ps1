param(
    [Alias("Host")]
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Database = "cbsrmt",
    [string]$User = "postgres",
    [switch]$Rebuild
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

Require-Command "psql"
Require-Command "python"

$PsqlArgs = @("-X", "-v", "ON_ERROR_STOP=1", "-h", $HostName, "-p", "$Port", "-U", $User, "-d", $Database)
$Dsn = "host=$HostName port=$Port dbname=$Database user=$User"

Write-Host "CBS RMT PostgreSQL fresh installer"
Write-Host "Target: $User@$HostName`:$Port/$Database"

$schemaCheckSql = "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname IN ('catalog','api','admin','stage','import'));"
$existing = (& psql @PsqlArgs -tA -c $schemaCheckSql).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect target database." }

if ($Rebuild) {
    Write-Host "Rebuild requested: dropping CBS RMT schemas only."
    & psql @PsqlArgs -c "DROP SCHEMA IF EXISTS admin, api, import, stage, catalog CASCADE;"
    if ($LASTEXITCODE -ne 0) { throw "Schema cleanup failed." }
} elseif ($existing -eq "t") {
    throw "CBS RMT schemas already exist. Re-run with -Rebuild to replace only CBS RMT schemas."
}

Write-Host "Installing schema and functions..."
& psql @PsqlArgs -f (Join-Path $Root "install/schema.sql")
if ($LASTEXITCODE -ne 0) { throw "Schema installation failed." }

$VenvPython = Join-Path $Root ".venv/Scripts/python.exe"
if (-not (Test-Path $VenvPython)) {
    Write-Host "Creating Python virtual environment..."
    & python -m venv (Join-Path $Root ".venv")
    if ($LASTEXITCODE -ne 0) { throw "Unable to create Python virtual environment." }
}

Write-Host "Installing loader dependency..."
& $VenvPython -m pip install --disable-pip-version-check -r (Join-Path $Root "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "Python dependency installation failed." }

Write-Host "Reconciling, staging, and importing JSON data..."
& $VenvPython (Join-Path $Root "tools/load_json.py") --dsn $Dsn --data-dir (Join-Path $Root "data")
if ($LASTEXITCODE -ne 0) { throw "JSON data import failed." }

Write-Host "Running integrity tests..."
& psql @PsqlArgs -f (Join-Path $Root "tests/001_integrity.sql")
if ($LASTEXITCODE -ne 0) { throw "Integrity tests failed." }

Write-Host "Running API contract tests..."
& psql @PsqlArgs -f (Join-Path $Root "tests/002_api_contract.sql")
if ($LASTEXITCODE -ne 0) { throw "API contract tests failed." }

Write-Host ""
Write-Host "Final database counts:"
& psql @PsqlArgs -c "SELECT (SELECT count(*) FROM catalog.episode) AS episodes, (SELECT count(*) FROM catalog.broadcast) AS broadcast_rows, (SELECT count(*) FROM catalog.broadcast WHERE broadcast_sequence IS NOT NULL) AS actual_broadcasts, (SELECT count(*) FROM catalog.person) AS people, (SELECT count(*) FROM catalog.genre) AS genres, (SELECT count(*) FROM catalog.adaptation) AS adaptations;"
if ($LASTEXITCODE -ne 0) { throw "Final verification query failed." }

Write-Host ""
Write-Host "PASS: CBS RMT PostgreSQL schema and data are installed and validated."
