param(
    [Parameter(Mandatory=$true)]
    [int]$EpisodeNumber,
    [Parameter(Mandatory=$true)]
    [int]$PersonId,
    [Parameter(Mandatory=$true)]
    [string]$CharacterName,
    [string]$Source = "",
    [Alias("Host")]
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Database = "cbsrmt",
    [string]$User = "root"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw "Required command 'psql' was not found in PATH."
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

function ConvertTo-PgLiteral([string]$Value) {
    if ($null -eq $Value) {
        return "NULL"
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

$characterLiteral = ConvertTo-PgLiteral $CharacterName
$sourceLiteral = if ([string]::IsNullOrWhiteSpace($Source)) {
    "NULL"
}
else {
    ConvertTo-PgLiteral $Source
}

$sql = @"
SELECT admin.set_cast_character(
    $EpisodeNumber,
    $PersonId,
    $characterLiteral,
    $sourceLiteral
);
"@

& psql -X -h $HostName -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -c $sql

if ($LASTEXITCODE -ne 0) {
    throw "Failed to update cast character."
}
