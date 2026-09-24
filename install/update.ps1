param(
    [Alias("Host")]
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Database = "cbsrmt",
    [string]$User = "root",
    [ValidateRange(1, [long]::MaxValue)]
    [Nullable[long]]$UserId = $null
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Run-PsqlFile([string]$Path) {
    Write-Host "Applying $Path..."
    & psql -X -h $HostName -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -f $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Failed while applying $Path."
    }
}

Require-Command "psql"

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

Write-Host "CBS RMT PostgreSQL OpenAPI contract update"
Write-Host "Target: $User@$HostName`:$Port/$Database"
if ($null -ne $UserId) {
    Write-Host "Application user ID: $UserId"
}
Write-Host ""

& psql -X -h $HostName -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -tAc "SELECT 1;"
if ($LASTEXITCODE -ne 0) {
    throw "Unable to connect to PostgreSQL as '$User'."
}

Run-PsqlFile "migrations/001_extensions_and_schemas.sql"
Run-PsqlFile "migrations/007_account_users.sql"
Run-PsqlFile "migrations/006_roles_and_grants.sql"
Run-PsqlFile "migrations/008_cast_correction_audit.sql"
Run-PsqlFile "migrations/009_cast_billing.sql"
Run-PsqlFile "functions/import/promote_json.sql"
Run-PsqlFile "functions/api/catalog.sql"
Run-PsqlFile "functions/admin/catalog.sql"
Run-PsqlFile "tests/002_api_contract.sql"
Run-PsqlFile "tests/003_cast_corrections.sql"

if ($null -ne $UserId) {
    Write-Host ""
    Write-Host "Checking application user ID $UserId..."

    $userJson = & psql -X -h $HostName -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -tA -c "SELECT coalesce(api.get_user($UserId)::text, 'null');"
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to validate application user ID $UserId."
    }

    $userJson = $userJson.Trim()
    if ($userJson -eq "null") {
        Write-Warning "Application user ID $UserId does not currently exist in account.app_user."
    }
    else {
        Write-Host "Application user ID $UserId is available through api.get_user()."
        Write-Host $userJson
    }
}

Write-Host ""
Write-Host "PASS: OpenAPI-aligned database update completed successfully."
