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

$sql = @"
SELECT admin.set_cast_character(
    :episode_number::integer,
    :person_id::integer,
    :'character_name',
    NULLIF(:'source','')
);
"@

& psql -X -h $HostName -p $Port -U $User -d $Database -v ON_ERROR_STOP=1 -v "episode_number=$EpisodeNumber" -v "person_id=$PersonId" -v "character_name=$CharacterName" -v "source=$Source" -c $sql

if ($LASTEXITCODE -ne 0) {
    throw "Failed to update cast character."
}
