# Schema Cleaner
Param (
[Parameter(Mandatory = $true)]
[String[]] $TargetDB,
[Parameter(Mandatory=$true)]
[String]$SchemaName,
[Switch]$Tablespace
)

foreach ($DBName in $TargetDB) {
    Write-Output "[$(Get-Date)] Processing $DBName"
    Write-Output "[$(Get-Date)] Checking current objects"
    Use-OracleDB -TargetDB $DBName -SQLQuery @"
SELECT object_type AS "ObjectType", COUNT(object_name) AS "ObjectCount" 
FROM dba_objects 
WHERE owner = UPPER('$SchemaName')
GROUP BY object_type;
"@

    $SchemaObjects = Use-OracleDB -TargetDB $DBName -SQLQuery @"
SELECT object_type AS "ObjectType", owner||'.'||object_name AS "ObjectName"
FROM dba_objects
WHERE owner = UPPER('$SchemaName');
"@

    $DropperQuery=""
    foreach ($Item in $SchemaObjects | ? { $_.ObjectType -eq 'JOB' }) {
        $Type = $Item | Select -ExpandProperty ObjectType
        $Name = $Item | Select -ExpandProperty ObjectName
        $DropThis = @"
BEGIN
  dbms_scheduler.drop_job(job_name => '$Name');
END;
/
"@
        $DropperQuery += "$DropThis`n"
    }

    foreach ($Item in $SchemaObjects | ? { $_.ObjectType -in @('PACKAGE','PROCEDURE','FUNCTION','VIEW','MATERIALIZED VIEW') }) {
        $Type = $Item | Select -ExpandProperty ObjectType
        $Name = $Item | Select -ExpandProperty ObjectName
        $DropThis = "DROP $Type $Name;"
        $DropperQuery += "$DropThis`n"
    }
    foreach ($Item in $SchemaObjects | ? { $_.ObjectType -eq 'INDEX' } | ? { $_.ObjectName -notmatch "PK" }) {
        $Type = $Item | Select -ExpandProperty ObjectType
        $Name = $Item | Select -ExpandProperty ObjectName
        $DropThis = "DROP $Type $Name;"
        $DropperQuery += "$DropThis`n"
    }
    foreach ($Item in $SchemaObjects | ? { $_.ObjectType -eq 'TABLE' }) {
        $Type = $Item | Select -ExpandProperty ObjectType
        $Name = $Item | Select -ExpandProperty ObjectName
        $DropThis = "DROP $Type $Name CASCADE CONSTRAINTS;"
        $DropperQuery += "$DropThis`n"
    }
    #$DropperQuery
    if ($DropperQuery) {
        Write-Output "[$(Get-Date)] Cleaning up..."
        Use-OracleDB -TargetDB $DBName -SQLQuery $DropperQuery -PlainText -Confirm
    } else {
        Write-Output "[$(Get-Date)] Nothing to do..."
    }
    Write-Output "[$(Get-Date)] Checking remaining objects"
    $RemainingObjects = Use-OracleDB -TargetDB $DBName -SQLQuery @"
SELECT object_type AS "ObjectType", COUNT(object_name) AS "ObjectCount" 
FROM dba_objects 
WHERE owner = UPPER('$SchemaName')
GROUP BY object_type;
"@
    if (-not $RemainingObjects -and $Tablespace) {
        Write-Output "[$(Get-Date)] Checking tablespaces to drop"
        $TSToDrop = Use-OracleDB -TargetDB $DBName -SQLQuery "SELECT name FROM v`$tablespace WHERE name LIKE '%$SchemaName%';"
        if ($TSToDrop) {
            Write-Output "[$(Get-Date)] Found the following tablespaces to drop"
            Write-Output "$TSToDrop"
        }
        $DropperQuery=""
        foreach ($TS in $TSToDrop) {
            $DropperQuery += "`nDROP TABLESPACE $TS INCLUDING CONTENTS AND DATAFILES CASCADE CONSTRAINTS;"
        }
        if ($DropperQuery) {
            Use-OracleDB -TargetDB $DBName -SQLQuery $DropperQuery -PlainText -Confirm
        } else {
            Write-Output "[$(Get-Date)] Nothing to do..."
        }
    }
}
