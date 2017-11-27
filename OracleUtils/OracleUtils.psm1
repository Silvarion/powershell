<#
.Synopsis
   Oracle Utilities for using within PowerShell
.DESCRIPTION
   This Module has functions to ping Oracle Databases, query them and get performance reports  automatically.
.EXAMPLE
   Import-Module \Path\to\OracleUtils.psm1
.NOTES
    This is my first Module for PowerShell, so any comments and suggestions are more than welcome. 
.FUNCTIONALITY
    This Module is mean to be used by Oracle DBAs who want to leverage the PS interface and SQL*Plus integration in order to work with Oracle Databases
#>

<#
.Synopsis
   Checks that the ORACLE_HOME is set. Returns $true if it is or $false otherwise.
.DESCRIPTION
   This functions returns $true if the ORACLE_HOME variable is set or $false otherwise
.EXAMPLE
if (Test-OracleEnv) {
    <Some commands>
}
.FUNCTIONALITY
#>
function Test-OracleEnv {
    [CmdletBinding()]
    [Alias("oratest")]
    [OutputType([boolean])]
    Param()
    Process {
        if ($env:ORACLE_HOME.Length -gt 0) {
            if ($(Get-ChildItem -Path "$env:ORACLE_HOME/bin" -Filter "sqlplus*").Exists) {
                $true
            } else {
                $false
            }
        } else {
            $false
        }
    }
}

<#
.Synopsis
   Checks that the database is reachable by leveraging TNS Ping
.DESCRIPTION
   This functions returns $true if the tnsping is successful, $false otherwise
.EXAMPLE
    if (Ping-OracleDB -TargetDB orcl) {
        Write-Logger -Notice -Message "Database pinged successfully"
        <Some commands>
    }
.EXAMPLE
    if (Ping-OracleDB -TargetDB orcl | Select -Property PingStatus) {
        Write-Logger -Notice -Message "Database pinged successfully"
        <Some commands>
    } else {
        Write-Logger -Warning Ping-OracleDB -TargetDB orcl | Select -Property PingResult
    }
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBS to verify the reachability of a DB
#>
function Ping-OracleDB
{
    [CmdletBinding()]
    [Alias("oraping")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # Flag to get full output or only boolean
        [Switch]$Full
    )
    Begin {
        if (-not (Test-OracleEnv)) {
            Write-Logger -Critical "No ORACLE_HOME detected, please make sure your Oracle Environment is set"
            exit
        }
    }
    Process {
        foreach ($DBName in $TargetDB) {
            if ($Full) {
                $Pinged=$(tnsping $DBName)
                $PingBool=$Pinged[-1].Contains('OK')
                $DBProps= [ordered]@{
                    [String]'DBName'=$DBName
                    [String]'PingResult'=$Pinged[-1]
                    'PingStatus'=$PingBool
                }
                $DBObj = New-Object -TypeName PSObject -Property $DBProps
                Write-Output $DBObj
            } else {
                $Pinged=$(tnsping $DBName)
                $Pinged[-1].contains('OK')
            }
        }
    }
}

<#
.Synopsys
    Returns a DB object
.DESCRIPTION
   This function returns a PSObject "OracleDatabase" with the database info
.EXAMPLE
    Get-OracleServices -TargetDB myorcl
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBAs to retrieve a full list of active services in a DB
#>
function Get-OracleDBInfo {
    [CmdletBinding()]
    [Alias("orainfo")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0)]
        # This can be only 1 database or a list of databases
        [Alias("d")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt
    )
    Process {
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName information" -CurrentOperation "Pinging database" -PercentComplete 10
                if (Ping-OracleDB -TargetDB $TargetDB) {
                    Write-Progress -Activity "Gathering $DBName information" -CurrentOperation "Querying database" -PercentComplete 20
                    $Output = @'
SET LINESIZE 9999
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF
COLUMN unique_name FORMAT a11
COLUMN global_name FORMAT a11
SELECT dbid FROM v$database;
SELECT db_unique_name FROM v$database;
SELECT global_name FROM global_name;
SELECT listagg(instance_name,',') WITHIN GROUP (ORDER BY 1) FROM gv$instance;
SELECT listagg(host_name,',') WITHIN GROUP (ORDER BY 1) FROM gv$instance;
SELECT listagg(NAME,',') WITHIN GROUP (ORDER BY 1) FROM v$active_services WHERE NAME NOT LIKE 'SYS%';
SELECT listagg(NAME,',') WITHIN GROUP (ORDER BY 1) FROM v$services WHERE NAME NOT LIKE 'SYS%';
SELECT listagg(USERNAME,',') WITHIN GROUP (ORDER BY 1) FROM dba_users WHERE USERNAME NOT LIKE 'SYS%';
'@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    Write-Progress -Activity "Gathering $DBName information" -CurrentOperation "Analysing output" -PercentComplete 50
                    $ErrorInOutput=$false
                    foreach ($Line in $Output) {
                        if ($Line.Contains("ORA-")) {
                            $ErrorInOutput=$true
                            $Line = "$($Line.Substring(0,25))..." 
                            $DBProps=[ordered]@{
                                [String]'DBName'=[String]$DBName
                                [String]'DBID'=""
                                [String]'GlobalName'=""
                                [String]'UniqueName'=""
                                [String]'InstanceName'=""
                                [String]'HostName'=""
                                [String]'ActiveServices'=""
                                [String]'Services'=""
                                [String]'Users'=""
                                [String]'ErrorMsg'=$Line
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                            Break
                        }
                    }
                    if (-not $ErrorInOutput) {
                        Write-Progress -Activity "Gathering $DBName information" -CurrentOperation "Building output object" -PercentComplete 85
                        $DBProps = [ordered]@{
                            [String]'DBName'=$DBName
                            [String]'DBID'=$Output[0]
                            [String]'UniqueName'=$Output[1]
                            [String]'GlobalName'=$Output[2]
                            [String]'Instances'=$Output[3]
                            [String]'Hosts'=$Output[4]
                            [String]'ActiveServices'=$Output[5]
                            [String]'Services'=$Output[6]
                            [String]'Users'=$Output[7]
                            [String]'ErrorMsg'=""
                        }
                        $DBObj=New-Object -TypeName PSObject -Property $DBProps
                        Write-Output $DBObj
                    }
                } else { 
                    $DBProps = [ordered]@{
                        [String]'DBName'=[String]$DBName
                        [String]'DBID'=""
                        [String]'GlobalName'=""
                        [String]'UniqueName'=""
                        [String]'InstanceName'=""
                        [String]'HostName'=""
                        [String]'ActiveServices'=""
                        [String]'Services'=""
                        [String]'Users'=""
                        [String]'ErrorMsg'=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj=New-Object -TypeName PSObject -Property $DBProps
                    Write-Output $DBObj
                }
            }
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
    }
}


<#
.Synopsis
   Returns the Active Services in an Oracle DB
.DESCRIPTION
   This function returns the Active Services in an Oracle DB
.EXAMPLE
    Get-OracleServices -TargetDB myorcl
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBAs to retrieve a full list of active services in a DB
#>
function Get-OracleServices
{
    [CmdletBinding()]
    [Alias("orasrvc")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # Swtich to get output as table instead of lists
        [Switch]$Table,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt
    )
    Process {
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "Pinging $DBName databases" -PercentComplete 0
                if (Ping-OracleDB -TargetDB $DBName) {
                    Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                    $Output = @'
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF
COLUMN unique_name FORMAT a11
COLUMN global_name FORMAT a11
SELECT name 
FROM v$active_services 
WHERE name NOT LIKE ('SYS%') 
ORDER BY 1;
'@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "Analizing $DBName output" -PercentComplete 35
                    $ErrorInOutput=$false
                    foreach ($Line in $Output) {
                        if (($Line.Contains("ORA-")) -or
                            ($Line.Contains("TNS-"))) {
                            $ErrorInOutput=$true
                            $DBProps=[ordered]@{
                                [String]'DBName'=[String]$DBName
                                [String]'Services'=""
                                [String]'ErrorMsg'=$Line
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                            Break
                        }
                    }
                    if (-not $ErrorInOutput) {
                        Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "Building $DBName output" -PercentComplete 65
                        if ($Table) {
                            foreach ($Line in $($Output -split "`t")) {
                                if ($Line.trim().Length -gt 0) {
                                    $DBProps=[ordered]@{
                                        'DBName'=$DBName
                                        'Services'=$Line
                                        'ErrorMsg'=""
                                    }
                                }
                                $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                                Write-Output $DBObj
                            }
                        } else {
                            $DBProps=[ordered]@{
                                'DBName'=$DBName
                                'Services'=$Output
                                'ErrorMsg'=""
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                        }
                    }
                } else { 
                    $DBProps=[ordered]@{
                        'DBName'=$DBName
                        'Services'=""
                        'ErrorMsg'=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                    Write-Output $DBObj
                }
            }
            Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "$DBName done" -PercentComplete 85
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
    }
}

<#
.Synopsis
   Returns the Active Services in an Oracle DB
.DESCRIPTION
   This function returns the Active Services in an Oracle DB
.EXAMPLE
    Get-OracleServices -TargetDB myorcl
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBAs to retrieve a full list of active services in a DB
#>
function Get-OracleSize
{
    [CmdletBinding()]
    [Alias("orasize")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Size types
        [Parameter(Mandatory = $true)]
        [ValidateSet("Full","Storage","Tablespace","Table")]
        [String]$SizeType
    )
    Process {
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            $FileSystemQuery = @"
SELECT GLOBAL_NAME||','||substr(file_name,1,instr(file_name,'/',-1))||',used:'||round(SUM(user_bytes/1024/1024/1024),2)||',alloc:'||round(SUM(BYTES/1024/1024/1024),2)||',max:'||round(SUM(maxbytes/1024/1024/1024),2)
FROM dba_data_files, GLOBAL_NAME
GROUP BY global_name, substr(file_name,1,instr(file_name,'/',-1))
UNION ALL
SELECT global_name||','||NAME||',used:'||ROUND(space_used/1024/1024/1024,2)||',alloc:'||ROUND(space_limit/1024/1024/1024,2)||',max:'||ROUND(space_limit/1024/1024/1024,2)
FROM v`$recovery_file_dest, global_name;
"@
            $TableSpaceQuery = @"
SELECT global_name||','||tablespace_name ||',used:'||used_gb||',max:'||max_gb
FROM (
	SELECT global_name, df.tablespace_name
		, round(SUM(df.BYTES / 1024 / 1024 / 1024), 2) used_gb
		, round(SUM(df.maxbytes / 1024 / 1024 / 1024), 2) max_gb
	FROM dba_data_files df, dba_tablespaces ts, global_name
	WHERE df.tablespace_name = ts.tablespace_name
	GROUP BY global_name, df.tablespace_name, round(ts.max_size / 1024 / 1024 / 1024, 2)
	ORDER BY tablespace_name
);
"@
            $TableQuery = @"
SELECT global_name||','||x.owner||'.'||x.table_name||',used:'||round(SUM(bytes) / 1024 / 1024 / 1024, 2)||',num_rows:'||nvl(z.num_rows, 0)
	FROM ( SELECT b.segment_name table_name, b.owner, b.bytes
		FROM dba_segments b
		WHERE b.segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
		UNION ALL
		SELECT i.table_name, i.owner, s.bytes
		FROM dba_indexes i, dba_segments s
		WHERE s.segment_name = i.index_name
			AND s.owner = i.owner
			AND s.segment_type IN ('INDEX', 'INDEX PARTITION', 'INDEX SUBPARTITION')
		UNION ALL
		SELECT l.table_name, l.owner, s.bytes
		FROM dba_lobs l, dba_segments s
		WHERE s.segment_name = l.segment_name
			AND s.owner = l.owner
			AND s.segment_type IN ('LOBSEGMENT', 'LOB PARTITION')
		UNION ALL
		SELECT l.table_name, l.owner, s.bytes
		FROM dba_lobs l, dba_segments s
		WHERE s.segment_name = l.index_name
			AND s.owner = l.owner
			AND s.segment_type = 'LOBINDEX'
		) x, dba_tables z, global_name
	WHERE z.table_name = x.table_name
		AND z.owner = x.owner
	GROUP BY
		global_name, trunc(SYSDATE), x.table_name, x.owner, nvl(z.num_rows, 0)
	HAVING round(SUM(BYTES) / 1024 / 1024 / 1024, 2) >= 1;
"@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Pinging $DBName databases" -PercentComplete 0
                $ASMQuery = @"
SELECT global_name||','||disk_group||',used:'||SUM(used_gb)||',alloc:'||SUM(alloc_gb)||',max:'||MIN(max_gb)
FROM (
    WITH file_hierarchy AS (
        SELECT SYS_CONNECT_BY_PATH(NAME,' ') as name, group_number, file_number, file_incarnation
        FROM v`$asm_alias
        CONNECT BY PRIOR reference_index = parent_index
    )
    SELECT TRIM(SUBSTR(fh.name,1,INSTR(fh.name,' ',2))) AS db_name, dg.name as DISK_GROUP, ROUND(af.BYTES/1024/1024/1024,2) AS USED_GB, ROUND(af.SPACE/1024/1024/1024,2) AS ALLOC_GB, ROUND(dg.TOTAL_MB/1024,2) AS MAX_GB
    FROM v`$asm_diskgroup dg
    JOIN v`$asm_file af
        ON (af.group_number = dg.group_number)
        JOIN file_hierarchy fh
        ON (af.file_number = fh.file_number
        AND dg.group_number = fh.group_number)
    WHERE dg.NAME IN (
        SELECT TRIM(REPLACE(value,'+',' ')) 
        FROM v$`spparameter 
        WHERE UPPER(name) IN ('DB_CREATE_FILE_DEST','DB_RECOVERY_FILE_DEST')
    )
), global_name
WHERE db_name NOT IN ('DATAFILE','CONTROLFILE','FLASHBACK','ARCHIVELOG','ONLINELOG','CHANGETRACKING','PARAMETERFILE')
AND  UPPER(db_name) = UPPER('$DBName')
GROUP BY global_name,db_name, disk_group
ORDER BY DB_NAME;
"@
                $FullASMQuery = @"
SELECT db_name||','||disk_group||',used:'||SUM(used_gb)||',alloc:'||SUM(alloc_gb)||',max:'||MIN(max_gb)
FROM (
    WITH file_hierarchy AS (
        SELECT SYS_CONNECT_BY_PATH(NAME,' ') as name, group_number, file_number, file_incarnation
        FROM v`$asm_alias
        CONNECT BY PRIOR reference_index = parent_index
    )
    SELECT TRIM(SUBSTR(fh.name,1,INSTR(fh.name,' ',2))) AS db_name, dg.name as DISK_GROUP, ROUND(af.BYTES/1024/1024/1024,2) AS USED_GB, ROUND(af.SPACE/1024/1024/1024,2) AS ALLOC_GB, ROUND(dg.TOTAL_MB/1024,2) AS MAX_GB
    FROM v`$asm_diskgroup dg
    JOIN v`$asm_file af
        ON (af.group_number = dg.group_number)
        JOIN file_hierarchy fh
        ON (af.file_number = fh.file_number
        AND dg.group_number = fh.group_number)
    WHERE dg.NAME IN (
        SELECT TRIM(REPLACE(value,'+',' ')) 
        FROM v`$spparameter 
        WHERE UPPER(name) IN ('DB_CREATE_FILE_DEST','DB_RECOVERY_FILE_DEST')
    )
)
WHERE db_name NOT IN ('DATAFILE','CONTROLFILE','FLASHBACK','ARCHIVELOG','ONLINELOG','CHANGETRACKING','PARAMETERFILE','TEMPFILE')
AND db_name IS NOT NULL
GROUP BY db_name, disk_group
ORDER BY DB_NAME;
"@
                if (Ping-OracleDB -TargetDB $DBName) {
                    Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                    Switch ($SizeType) {
                        "Full" {
                            if ($(Get-OracleInstances -TargetDB $DBName -Table).Length -gt 1) {
                                $Query = $ASMQuery
                            } else {
                                $Query = $FileSystemQuery
                            }
                        }
                        "Storage" {
                            if ($(Get-OracleInstances -TargetDB $DBName -Table).Length -gt 1) {
                                $Query = $FullASMQuery
                            } else {
                                $Query = $FileSystemQuery
                            }
                        }
                    }
                    if ($SizeType -eq "Table") {
                        $Query = $TableQuery
                    } else {
                        if ($FullSize) {
                            if ($(Get-OracleInstances -TargetDB $DBName -Table).Length -gt 1) {
                                $Query = $ASMQuery
                            } else {
                                $Query = $FileSystemQuery
                            }
                        }
                        if ($TablespaceSize) {
                            $Query = $TableSpaceQuery
                        }
                    }
                    $Output = @"
SET PAGESIZE 0
SET HEADING OFF
SET FEEDBACK OFF
$Query
"@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Analizing $DBName output" -PercentComplete 35
                    $ErrorInOutput=$false
                    foreach ($Line in $Output) {
                        if (($Line.Contains("ORA-")) -or
                            ($Line.Contains("TNS-"))) {
                            $ErrorInOutput=$true
                            $DBProps=[ordered]@{
                                [String]'DBName'=[String]$DBName
                                [String]'Size'=""
                                [String]'ErrorMsg'=$Line
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                            Break
                        }
                    }
                    if (-not $ErrorInOutput) {
                        Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Building $DBName output" -PercentComplete 65
                        foreach ($Line in $($Output -split "`t")) {
                            if ($Line.trim().Length -gt 0) {
                                if ($SizeType -eq "Full") {
                                    $DBProps=[ordered]@{
                                        'DBName'=$($Line -split ',')[0]
                                        'Path'=$($Line -split ',')[1]
                                        'Used'=[float]$($($Line -split ',')[2] -split ':')[1]
                                        'Allocated'=[float]$($($Line -split ',')[3] -split ':')[1]
                                        'Max'=[float]$($($Line -split ',')[4] -split ':')[1]
                                        'ErrorMsg'=""
                                    }
                                } elseif ($SizeType -eq "Storage") {
                                    $DBProps=[ordered]@{
                                        'DBName'=$($Line -split ',')[0]
                                        'Path'=$($Line -split ',')[1]
                                        'Used'=[float]$($($Line -split ',')[2] -split ':')[1]
                                        'Allocated'=[float]$($($Line -split ',')[3] -split ':')[1]
                                        'Max'=[float]$($($Line -split ',')[4] -split ':')[1]
                                        'ErrorMsg'=""
                                    }
                                } elseif ($SizeType -eq "Tablespace") {
                                    $DBProps=[ordered]@{
                                        'DBName'=$($Line -split ',')[0]
                                        'Path'=$($Line -split ',')[1]
                                        'Used'=[float]$($($Line -split ',')[2] -split ':')[1]
                                        'Max'=[float]$($($Line -split ',')[3] -split ':')[1]
                                        'ErrorMsg'=""
                                    }
                                } elseif ($SizeType -eq "Table") {
                                    $DBProps=[ordered]@{
                                        'DBName'=$($Line -split ',')[0]
                                        'Path'=$($Line -split ',')[1]
                                        'Used'=[float]$($($Line -split ',')[2] -split ':')[1]
                                        'Max'=[float]$($($Line -split ',')[3] -split ':')[1]
                                        'ErrorMsg'=""
                                    }
                                }

                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                        }
                    }
                } else { 
                    $DBProps=[ordered]@{
                        'DBName'=$DBName
                        'Services'=""
                        'ErrorMsg'=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                    Write-Output $DBObj
                }
            }
            Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "$DBName done" -PercentComplete 85
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
    }
}

<#
.Synopsis
   Returns the status of Database Vault
.DESCRIPTION
   This function returns the status of Database Vault in an Oracle DB
.EXAMPLE
    Get-OracleVaultStatus -TargetDB myorcl
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBAs to retrieve the status of Database Vault in an Oracle DB
#>
function Get-OracleVaultStatus
{
    [CmdletBinding()]
    [Alias("oravault")]
    [OutputType([String[]])]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt
    )
    Process {
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                if (Ping-OracleDB -TargetDB $TargetDB) {
                    $Output=@'
COLUMN name FORMAT a21
COLUMN status FORMAT a5
SET HEADING OFF
SET FEEDBACK OFF
SELECT comp_name as name||':'||status||':'||modified
FROM dba_registry
WHERE comp_name LIKE '%Label%'
OR comp_name LIKE '%Vault%';
'@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    if ($Output.Contains("ORA-")) {
                        $Output = "$($Output.Substring(0,75))..." 
                    }
                    foreach ($Line in [String[]]$($Output -split "`n")) {
                        $DBProps=[ordered]@{
                            'DBName'=$DBName
                            'Component'=$($Line -split ':')[0]
                            'Status'=$($Line -split ':')[1]
                            'Modified'=$($Line -split ':')[2]
                            'ErrorMsg'=""
                        }
                        $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                        Write-Output $DBObj
                        $Counter++
                    }
                } else { 
                    $DBProps=[ordered]@{
                        'DBName'=$DBName
                        'Component'=""
                        'ErrorMsg'=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                    Write-Output $DBObj
                }
            }
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
    }
}

<#
.Synopsis
    Query an Oracle database to get the global name
.DESCRIPTION
    This function returns the global name of the database
.EXAMPLE
    Get-OracleGlobalName -TargetDB <DB NAME> [-ErrorLog]
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OracleName {
    [CmdletBinding()]
    [Alias("oraname")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [Alias("DBName")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                if (($DBName)) {
                    if (Ping-OracleDB -TargetDB $DBName) {
					    Write-Debug "Database pinged successfully"
                        # Using here-string to pipe the SQL query to SQL*Plus
                        $Output=@"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET LINESIZE 999
SET TRIM ON
SET WRAP OFF
SET HEADING OFF
SELECT global_name FROM global_name;
SELECT db_unique_name FROM v`$database;
SELECT instance_name FROM v`$instance;
SELECT host_name FROM v`$instance;
exit
"@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                        $ErrorInOutput=$false
                        foreach ($Line in $Output) {
                            if ($Line.Contains("ORA-")) {
                                $ErrorInOutput=$true
                                $Line = "$($Line.Substring(0,25))..." 
                                $DBProps=[ordered]@{
                                    [String]'DBName'=$DBName
                                    [String]'GlobalName'=""
                                    [String]'UniqueName'=""
                                    [String]'InstanceName'=""
                                    [String]'HostName'=""
                                    [String]'ErrorMsg'=$Output
                                }
                                $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                                Write-Output $DBObj
                                Break
                            }
                        }
                        if (-not $ErrorInOutput) {
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'GlobalName'=$Output[0]
                                [String]'UniqueName'=$Output[1]
                                [String]'InstanceName'=$Output[2]
                                [String]'HostName'=$Output[3]
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                        }
                    } else {
                    $ErrorMsg=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                        $DBProps=[ordered]@{
                            'DBName'=[String]$DBName
                            'GlobalName'=[String]"--------"
                            'UniqueName'=[String]"--------"
                            'InstanceName'=[String]"--------"
                            'HostName'=[String]$ErrorMsg
                        }
                        $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                        Write-Output $DBObj                
                    }
                }
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    Query an Oracle database to get the names of all its instances
.DESCRIPTION
    This function returns instance names for a target oracle database
.EXAMPLE
    Get-OracleInstance -TargetDB <DB NAME> -SQLScript <Path/to/file.sql> [-ErrorLog]
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OracleInstances {
    [CmdletBinding()]
    [Alias("orainst")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="Target Oracle Database name")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Swtich to get output as table instead of lists
        [Switch]$Table,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ( $DBName in $TargetDB) {
                if (Ping-OracleDB -TargetDB $DBName) {
		            Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    $Output = @'
SET HEADING OFF
SET PAGESIZE 0
SELECT instance_name from gv$instance ORDER BY 1;
exit
'@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    $ErrorInOutput=$false
                    foreach ($Line in $Output) {
                        if ($Line.Contains("ORA-")) {
                            $ErrorInOutput=$true
                            $Line = "$($Line.Substring(0,25))..." 
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'InstanceName'=""
                                [String]'ErrorMsg'=$Line
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                            Break
                        }
                    }
                    if (-not $ErrorInOutput) {
                        if ($Table) {
                            foreach ($Line in $($Output -split "`t")) {
                                if ($Line.trim().Length -gt 0) {
                                    $DBProps=[ordered]@{
                                        [String]'DBName'=$DBName
                                        [String]'InstanceName'=$Line
                                        [String]'ErrorMsg'=""
                                    }
                                }
                                $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                                Write-Output $DBObj
                            }
                        } else {
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'InstanceName'=$Output
                                [String]'ErrorMsg'=""
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                        }
                    }
                } else { 
                    $DBProps = [ordered]@{
                        [String]'DBName'=$DBName
                        [String]'InstanceName'=""
                        [String]'ErrorMsg'=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj=New-Object -TypeName PSObject -Property $DBProps
                    Write-Output $DBObj
                }
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    Query an Oracle database to get the names of all its hosts
.DESCRIPTION
    This function returns host names for a target oracle database
.EXAMPLE
    Get-OracleHosts -TargetDB <DB NAME> [-ErrorLog]
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OracleHosts {
    [CmdletBinding()]
    [Alias("orahost")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="Target Oracle Database name")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Swtich to get output as table instead of lists
        [Switch]$Table,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                if (Ping-OracleDB -TargetDB $DBName) {
			        Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    $Output = @'
SET HEADING OFF
SET PAGESIZE 0
SELECT host_name from gv$instance ORDER BY 1;
exit
'@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    $ErrorInOutput=$false
                    foreach ($Line in $Output) {
                        if ($Line.Contains("ORA-")) {
                            $ErrorInOutput=$true
                            $Line = "$($Line.Substring(0,25))..." 
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'Hosts'=""
                                [String]'ErrorMsg'=$Line
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                            Break
                        }
                    }
                    if (-not $ErrorInOutput) {
                        if ($Table) {
                            foreach ($Line in $($Output -split "`t")) {
                                if ($Line.trim().Length -gt 0) {
                                    $DBProps=[ordered]@{
                                        [String]'DBName'=$DBName
                                        [String]'Hosts'=$Line
                                        [String]'ErrorMsg'=""
                                    }
                                }
                                $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                                Write-Output $DBObj
                            }
                        } else {
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'Hosts'=$Output
                                [String]'ErrorMsg'=""
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                        }
                    }
                } else { 
                    $DBProps = [ordered]@{
                        [String]'DBName'=$DBName
                        [String]'Hosts'=""
                        [String]'ErrorMsg'=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj=New-Object -TypeName PSObject -Property $DBProps
                    Write-Output $DBObj
                }
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    Query an Oracle database to get the names of all its hosts
.DESCRIPTION
    This function returns host names for a target oracle database
.EXAMPLE
    Get-OracleHosts -TargetDB <DB NAME> [-ErrorLog]
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OracleUsers {
    [CmdletBinding()]
    [Alias("orauser")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="Target Oracle Database name")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Swtich to get output as table instead of lists
        [Switch]$Table,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering Users on $DBName..." -CurrentOperation "Pinging Database" -PercentComplete 10
                if (Ping-OracleDB -TargetDB $DBName) {
			        Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    Write-Progress -Activity "Gathering Users on $DBName..." -CurrentOperation "Querying Database" -PercentComplete 30
                    $Output = @'
SET HEADING OFF
SET PAGESIZE 0
SET LINESIZE 999
SET FEEDBACK OFF
SELECT username||':'||account_status
FROM dba_users 
WHERE username NOT IN ('SYS','SYSTEM','SYSAUX','DBSNMP') 
ORDER BY 1;
exit
'@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    Write-Progress -Activity "Gathering Users on $DBName..." -CurrentOperation "Checking Output" -PercentComplete 50 -Id 100
                    $ErrorInOutput=$false
                    foreach ($Line in $Output) {
                        if ($Line.Contains("ORA-")) {
                            $ErrorInOutput=$true
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'Users'=""
                                [String]'ErrorMsg'=$Line
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                            Break
                        }
                    }
                    if (-not $ErrorInOutput) {
                        Write-Progress -Activity "Gathering Users on $DBName..." -CurrentOperation "Building Output Object" -PercentComplete 90 -id 100
                        if ($Table) {
                            $TotalRows = $Output.Length
                            $Counter = 0
                            Write-Progress -Activity "Building users table from $DBName..." -CurrentOperation "Pinging Database" -PercentComplete $(($Counter++ / ($TotalRows)*100)) -ParentId 100
                            foreach ($Line in $($Output -split "`t")) {
                                if ($Line.trim().Length -gt 0) {
                                    $DBProps=[ordered]@{
                                        [String]'DBName'=$DBName
                                        [String]'Users'=$($Line -split ':')[0]
                                        [String]'Status'=$($Line -split ':')[1]
                                        [String]'ErrorMsg'=""
                                    }
                                }
                                $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                                Write-Progress -Activity "Building users table from $DBName..." -CurrentOperation "Adding User $($DBObj.Users)" -PercentComplete $(($Counter++ / ($TotalRows)*100)) -ParentId 100
                                Write-Output $DBObj
                            }
                        } else {
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'Users'=$Output
                                [String]'ErrorMsg'=""
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                        }
                    }
                } else { 
                    $DBProps = [ordered]@{
                        [String]'DBName'=$DBName
                        [String]'Users'=""
                        [String]'ErrorMsg'=[String]$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj=New-Object -TypeName PSObject -Property $DBProps
                    Write-Output $DBObj
                }
            }
            Write-Progress -Activity "Gathering Users on $DBName..." -CurrentOperation "Writing Object" -PercentComplete 99 -Id 100
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{
        Write-Progress -Activity "Gathering Users on $DBName..." -Completed
    }
}

<#
.Synopsis
    Query an Oracle database to get the DBID
.DESCRIPTION
    This function returns the DBID of the target database
.EXAMPLE
    Get-OracleInstance -TargetDB <DB NAME>  [-ErrorLog]
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OracleDBID {
    [CmdletBinding()]
    [Alias("oradbid")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                if (Ping-OracleDB($DBName)) {
					Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                   $Output =  @'
SET HEADING OFF
SET PAGESIZE 0
SELECT dbid FROM v$database;
exit
'@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"
                    $ErrorInOutput=$false
                    foreach ($Line in $Output) {
                        if ($Line.Contains("ORA-")) {
                            $ErrorInOutput=$true
                            $Line = "$($Line.Substring(0,25))..." 
                            $DBProps=[ordered]@{
                                [String]'DBName'=$DBName
                                [String]'DBID'=""
                                [String]'ErrorMsg'=[String]$Line
                            }
                            $DBObj = New-Object -TypeName PSOBject -Property $DBProps
                            Write-Output $DBObj
                            Break
                        }
                    }
                    if (-not $ErrorInOutput) {
                        $DBProps = [ordered]@{
                            [String]'DBName'=$TargetDB
                            [String]'DBID'=$Output
                            [String]'ErrorMsg'=""
                        }
                        $DBObj=New-Object -TypeName PSObject -Property $DBProps
                        Write-Output $DBObj
                    }
                } else { 
                    $DBProps = [ordered]@{
                        [String]'DBName'=$DBName
                        [String]'DBID'=""
                        [String]'ErrorMsg'=$(Ping-OracleDB -TargetDB $TargetDB -Full | Select -ExpandProperty PingResult)
                    }
                    $DBObj=New-Object -TypeName PSObject -Property $DBProps
                    Write-Output $DBObj
                }
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    
.DESCRIPTION
    
.EXAMPLE
    
.ROLE
    
#>
function Get-OracleSnapshot {
    [CmdletBinding()]
    [Alias("orasnap")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # This is the time for the permoance snapshot
        [Parameter(Mandatory=$true,
            HelpMessage="Snapshot approximate time")]
        [datetime]$TimeStamp,
        # Parameter that defines if it's a starting or ending snapshot
        [Parameter(Mandatory=$true)]
        [ValidateSet("start","end")]
        [String]$Mark,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
			Write-Debug "Database pinged successfully"
            if ($Mark -eq "start") {
                $StrTimeStamp = $TimeStamp.AddSeconds(50).ToString("yyyy-MM-dd HH:mm:ss")
                Write-Debug $TimeStamp
                # Using here-string to pipe the SQL query to SQL*Plus
                @"
SET HEADING OFF
SET PAGESIZE 0
SELECT max(snap_id)
FROM dba_hist_snapshot
WHERE begin_interval_time <= TO_TIMESTAMP('$StrTimeStamp','YYYY-MM-DD HH24:MI:SS')
AND end_interval_time > TO_TIMESTAMP('$StrTimeStamp','YYYY-MM-DD HH24:MI:SS');
EXIT
"@ | &"sqlplus" "-S" "/@$TargetDB"
            } else {
                $StrTimeStamp = $TimeStamp.ToString("yyyy-MM-dd HH:mm:ss")
                Write-Debug $TimeStamp
                # Using here-string to pipe the SQL query to SQL*Plus
                @"
SET HEADING OFF
SET PAGESIZE 0
SELECT min(snap_id)
FROM dba_hist_snapshot
WHERE end_interval_time >= TO_TIMESTAMP('$StrTimeStamp','YYYY-MM-DD HH24:MI:SS')
AND begin_interval_time < TO_TIMESTAMP('$StrTimeStamp','YYYY-MM-DD HH24:MI:SS');
EXIT
"@ | &"sqlplus" "-S" "/@$TargetDB"
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    
.DESCRIPTION
    
.EXAMPLE
    
.ROLE
    
#>
function Get-OracleSnapshotTime {
    [CmdletBinding()]
    [Alias("orasnaptime")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            HelpMessage="Oracle Database ID")]
        [bigint]$DBID,
        # This is the snapshot to use to query the time
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$Snapshot,
        # Mark that defines if the snapshot is upper or lower boundary to the analysis
        [Parameter(Mandatory=$true)]
        [ValidateSet("start","end")]
        [String]$Mark,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            # Using here-string to pipe the SQL query to SQL*Plus
            if ($Mark -eq "start") {
                @"
SET HEADING OFF
SET PAGESIZE 0
SELECT TO_CHAR(MAX(begin_interval_time),'YYYY-MM-DD HH24:MI:SS')
FROM dba_hist_snapshot 
WHERE snap_id = $Snapshot
AND dbid = $DBID;
EXIT
"@ | &"sqlplus" "-S" "/@$TargetDB"
            } else {
                @"
SET HEADING OFF
SET PAGESIZE 0
SELECT TO_CHAR(MAX(end_interval_time),'YYYY-MM-DD HH24:MI:SS')
FROM dba_hist_snapshot 
WHERE snap_id = $Snapshot
AND dbid = $DBID;
EXIT
"@ | &"sqlplus" "-S" "/@$TargetDB"
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    
.DESCRIPTION
    
.EXAMPLE
    
.ROLE
    
#>
function Get-OracleADDMInstanceReport {
    [CmdletBinding()]
    [Alias("oraaddm")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Instance name")]
        [String]$Instance,
        # This is the DBID of the target database
        [Parameter(Mandatory=$true,
            HelpMessage="Oracle Database ID")]
        [bigint]$DBID,
        # This is the starting snapshot for the Report scope
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$StartSnapshot,
        # This is the ending snapshot for the Report scope
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$EndSnapshot,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            $InstNumber = $Instance.Substring($Instance.Length-1)
            # Using here-string to pipe the SQL query to SQL*Plus
            @"
define  db_name      = '$TargetDB';
define  dbid         = $DBID;
define  inst_num     = $InstNumber;
define  inst_name    = '$Instance';
define  num_days     = 3;
define  begin_snap   = $StartSnapshot;
define  end_snap     = $EndSnapshot;
define  report_type  = 'html';
define  report_name  = 'addm_${Instance}_${StartSnapshot}_${EndSnapshot}_report.txt'
@@?/rdbms/admin/addmrpti.sql
exit;
EXIT
"@ | &"sqlplus" "-S" "/@$TargetDB"
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    
.DESCRIPTION
    
.EXAMPLE
    
.FUNCTIONALITY
    
#>
function Get-OracleAWRReport {
    [CmdletBinding()]
    [Alias("oraawr")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            HelpMessage="Oracle Database ID")]
        [bigint]$DBID,
        # This is the starting snapshot for the Report scope
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$StartSnapshot,
        # This is the ending snapshot for the Report scope
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$EndSnapshot,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
			Write-Logger -Notice -Message "Launching AWR Global Report"
            # Using here-string to pipe the SQL query to SQL*Plus
            @"
define  db_name      = '$TargetDB';
define  dbid         = $DBID;
define  num_days     = 3;
define  begin_snap   = $StartSnapshot;
define  end_snap     = $EndSnapshot;
define  report_type  = 'html';
define  report_name  = 'awr_${TargetDB}_${StartSnapshot}_${EndSnapshot}_global_report.html'
@@?/rdbms/admin/awrgrpt.sql
exit;
EXIT
"@ | &"sqlplus" "-S" "/@$TargetDB"
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    
.DESCRIPTION
    
.EXAMPLE
    
.FUNCTIONALITY
    
#>
function Get-OracleAWRInstanceReport {
    [CmdletBinding()]
    [Alias("oraawrisnt")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Instance name")]
        [String]$Instance,
        # This is the DBID of the target database
        [Parameter(Mandatory=$true,
            HelpMessage="Oracle Database ID")]
        [bigint]$DBID,
        # This is the starting snapshot for the Report scope
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$StartSnapshot,
        # This is the ending snapshot for the Report scope
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$EndSnapshot,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            $InstNumber = $Instance.Substring($Instance.Length-1)
            # Using here-string to pipe the SQL query to SQL*Plus
            @"
define  db_name      = '$TargetDB';
define  dbid         = $DBID;
define  inst_num     = $InstNumber;
define  inst_name    = '$Instance';
define  num_days     = 3;
define  begin_snap   = $StartSnapshot;
define  end_snap     = $EndSnapshot;
define  report_type  = 'html';
define  report_name  = 'awr_${Instance}_${StartSnapshot}_${EndSnapshot}_report.html'
@@?/rdbms/admin/awrrpti.sql
exit;
EXIT
"@ | &"sqlplus" "-S" "/@$TargetDB"
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    Generate AWR and/or ADDM report sets from an oracle database
.DESCRIPTION
    This function defines the required variables to generate automatically AWR and ADDM report sets.
.EXAMPLE
    Get-OraclePerfReports  [-AWR] [-ADDM] -TargetDB <DB NAME> [-ErrorLog]
.FUNCTIONALITY
       This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OraclePerfReports {
    [CmdletBinding(
    SupportsShouldProcess=$true)]
    [Alias("oraperf")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="Target Oracle Database names")]
        [String]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # This is the starting time for the performance snapshot
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [datetime]$StartTime,
        # This is the ending time for the performance snapshot
        [Parameter(Mandatory=$true,
            HelpMessage="Ending snapshot approximate time")]
        [datetime]$EndTime,
        # Switch to turn on ADDM report package
        [Switch]$ADDM,
        # Switch to turn on AWR report package
        [Switch]$AWR,
        # Switch to create compressed report sets
        [Switch]$Compress,
        # Switch to send email report sets
        [Switch]$SendMail,
        [String[]]$EmailAddress,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin {
        if (-not $ADDM -and -not $AWR) {
            $ADDM = $true
            $AWR = $true
        }
    }
    Process {
        Write-Logger -Info -Message "PS Oracle Performance Reports Generator"
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            if (Ping-OracleDB -TargetDB $TargetDB) {
				Write-Logger -Notice -Message "Database pinged successfully"
                Write-Logger -Info -Message "Gathering DBID"
                [String]$TempStr = Get-OracleDBID -TargetDB $TargetDB | Select -ExpandProperty DBID
                [bigint]$DBID = $TempStr.Trim(' ')
                Write-Logger -Notice -Message "DBID for $TargetDB : $DBID"
                Write-Logger -Info -Message "Getting Snapshot numbers"
                [String]$StrSnapshot = Get-OracleSnapshot -TargetDB $TargetDB -TimeStamp $StartTime.AddSeconds(59).ToString("yyyy-MM-dd HH:mm:ss") -Mark start
                [bigint]$StartSnapshot = [bigint]$StrSnapshot.trim(' ')
                [String]$StrSnapshot = Get-OracleSnapshot -TargetDB $TargetDB -TimeStamp $EndTime.ToString("yyyy-MM-dd HH:mm:ss") -Mark end
                [bigint]$EndSnapshot = [bigint]$StrSnapshot.trim(' ')
				Write-Logger -Notice -Message "Starting Snapshot: $StartSnapshot | Ending Snapshot: $EndSnapshot"
                Write-Logger -Info -Message "Getting Snapshot times"
                [String]$StartSnapTime = Get-OracleSnapshotTime -TargetDB $TargetDB -DBID $DBID -Snapshot $StartSnapshot -Mark start
                [String]$EndSnapTime = Get-OracleSnapshotTime -TargetDB $TargetDB -DBID $DBID -Snapshot $EndSnapshot -Mark end
                Write-Logger -Notice -Message "Starting Snapshot Time: $StartSnapTime | Ending Snapshot Time: $EndSnapTime"
                Write-Logger -Info -Message "Getting Oracle database instances"
                $Instances = Get-OracleInstances -TargetDB $TargetDB
                if ($AWR) {
                    Write-Logger -Info -Message "Generating AWR Report Set"
                    $ORAOutput = Get-OracleAWRReport -TargetDB $TargetDB -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                    foreach ($Instance in $Instances) {
                        if ($Instance.Length -gt 0) {
                            Write-Logger -Notice -Message "Launching AWR Instance Report for $Instance"
                            $ORAOutput = Get-OracleAWRInstanceReport -TargetDB $TargetDB -Instance $Instance -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                        }
                    }
                    if ($Compress) {
                        Write-Logger -Info -Message "Compressing AWR reports set"
                        zip -9m AWR_${TargetDB}_${StartSnapshot}_${EndSnapshot}_reports.zip awr*.htm*
                    }
                }
                if ($ADDM) {
                    Write-Logger -Info -Message "Generating ADDM Report Set"
                    foreach ($Instance in $Instances) {
                        if ($Instance.Length -gt 0) {
                            Write-Logger -Notice -Message "Launching ADDM Instance #$InstNumber Report for $Instance"
                            $ORAOutput = Get-OracleADDMInstanceReport -TargetDB $TargetDB -Instance $Instance -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                        }
                    }
                    if ($Compress) {
                        Write-Logger -Info -Message "Compressing ADDM reports set"
                        zip -9m ADDM_${TargetDB}_${StartSnapshot}_${EndSnapshot}_reports.zip addm*.*
                    }
                }
                if ($SendMail) {
                   if ($EmailAddress.Length -lt 6) {
                        Write-Warning "Please enter a valid email address"
                        Read-Host -Prompt "Email to send the reports to" -OutVariable $EmailAddress
                    }
                    if ($Compress) {
                        $ReportFiles = Get-ChildItem -Path . -Name *reports.zip
                    } else {
                        $ReportFiles = Get-ChildItem -Path . -Name *report.*
                    }
                    $searcher = [adsisearcher]"(samaccountname=$env:USERNAME)"
                    $FromAddress = $searcher.FindOne().Properties.mail
                    Send-MailMessage -Attachments $ReportFiles -From $FromAddress -To $FromAddress -Subject "Reports Test" -Body "Some message" -SmtpServer "<YOUR SMTP SERVER>" -Credential (Get-Credential) -UseSsl
                }
            }
        }
    }
    End{}
}

<#
.Synopsis
    This will run a SQL script or command on one or more Oracle databases by leveraging SQL*Plus
.DESCRIPTION
    This function runs a SQL script on a Oracle Database and returns the output from the script
.EXAMPLE
    Run-OracleScript -TargetDB orcl -SQLScript 'C:\path\to\file.sql' -Dump -DumpFile C:\path\to\dump\file.out> -ErrorLog
.EXAMPLE
    Run-OracleScript -TargetDB <DB NAME> -SQLQuery "SELECT 1 FROM DUAL;" -Dump -DumpFile C:\path\to\dump\file.out> -ErrorLog
.FUNCTIONALITY
    This cmdlet is mean to be used by Oracle DBAs to query databases or run scripts.
#>
function Use-OracleDB {
    [CmdletBinding(
        DefaultParameterSetName='BySQLQuery',
        SupportsShouldProcess=$true)]
    [Alias("oraquery")]
    Param (
        # It can run the script on several databases at once
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # It can run several scripts at once
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ParameterSetName='BySQLFile',
            Position=1,
            HelpMessage="Path to SQL file to run on the databases")]
        [String[]]$SQLScript,

        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ParameterSetName='BySQLQuery',
            Position=1,
            HelpMessage="SQL query to run on the databases")]
        [String[]]$SQLQuery,
        [Parameter(
            HelpMessage="Dump results to an output file")]
        [Switch]$Dump,
        [Parameter(
            HelpMessage="Dump results to an output file")]
        [String]$DumpFile,
        # Switch to force get HTML output
        [Parameter(
            HelpMessage="Flags the output to be HTML")]
        [Switch]$HTML,
        [Parameter(
            HelpMessage="Flags the output to be clean without feedback or headers or anything else")]
        [Switch]$Silent,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{
        if (-not $Silent) {Write-Logger -Underlined -Message "Welcome to the Use-OracleDB Function"}

    }
    Process{
        if($HTML) {
            # Oracle HTML Header that formats HTML output from the Oracle Database
            $OracleHtmlHeader = @'
<html>
<head>
<style type='text/css'>
body {font:normal 10pt Arial,Helvetica,sans-serif; color:black; background:White;}
p {
    font:10pt Arial,Helvetica,sans-serif;
    color:black;
    background:White;
}
table,tr,td {
    font:10pt Arial,Helvetica,sans-serif;
    color:Black;
    background:#e7e7f7;
    padding:0px 0px 0px 0px;
    margin:0px 0px 0px 0px;
}
th {
    font:bold 10pt Arial,Helvetica,sans-serif;
    color:blue; 
    background:#cccc99;
    padding:0px 0px 0px 0px;
}
h1 {
    font:16pt Arial,Helvetica,Geneva,sans-serif;
    color:#336699; 
    background-color:White; 
    border-bottom:1px solid #cccc99; 
    margin-top:0pt; margin-bottom:0pt;
    padding:0px 0px 0px 0px;
} 
h2 {
    font:bold 10pt Arial,Helvetica,Geneva,sans-serif; 
    color:#336699;
    background-color:White; 
    margin-top:4pt; 
    margin-bottom:0pt;
} 
a {
    font:9pt Arial,Helvetica,sans-serif;
    color:#663300; 
    background:#ffffff; 
    margin-top:0pt; 
    margin-bottom:0pt;
    vertical-align:top;}
</style>
</head>
<body>
'@
# Oracle HTML Tail to close the body and html tags on the HTML output from the Oracle Database
            $OracleHtmlTail = "</body></html>"
        }
        if ($Silent) {
            $PipelineSettings=@"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET LINESIZE 999
SET TRIM ON
SET WRAP OFF
SET HEADING OFF
"@
        }
        if (-not $Silent) {Write-Logger -Info -Message "Checking Oracle variables..."}
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            foreach ($DBName in $TargetDB) {
                if (-not $Silent) {Write-Logger -Info -Message "Trying to reach database $DBName..."}
                if (Ping-OracleDB -TargetDB $DBName) {
                    if (-not $Silent) {Write-Logger -Notice -Message "Database $DBName is reachable"}
                    if (-not $Silent) {Write-Logger -Info -Message "Checking Run-Mode..."}
                    if ($PSCmdlet.ParameterSetName -eq 'BySQLFile') {
                        if (-not $Silent) {Write-Logger -Info -Message "Running on Script Mode"}
                        if (-not $Silent) {Write-Logger -Info -Message "Checking script for settings and exit string"}
                        $tmpScript = Get-Content -Path $SQLScript
                        $toExecute = "$env:TEMP/runthis_$PID.sql"
                        "-- AUTOGENERATED TEMPORARY FILE" | Out-File -Encoding ASCII $toExecute
                        if ($HTML) {
                        Write-Logger -Notice -Message "Adding HTML output setting"
                        if (-not $Silent) {"SET MARKUP HTML ON" | Out-File -Encoding ASCII $toExecute -Append}
                        }
                        foreach ($line in $tmpScript) {
                            "$line" | Out-File -Encoding ASCII $toExecute -Append
                        }
                        if(-not $tmpScript[-1].ToLower().Contains("exit")) {
                        if (-not $Silent) {Write-Logger -Notice -Message "Adding EXIT command"}
                        "exit;" | Out-File -Encoding ASCII $toExecute -Append
                        }
                        if (-not $Silent) {Write-Logger -Info -Message "Running script. Please wait..."}
                        $Output = &"sqlplus" "-S" "$DBUser/$DBPass@$DBName" "@$toExecute"
                    } elseif ($PSCmdlet.ParameterSetName -eq 'BySQLQuery') {
                        if (-not $Silent) {Write-Logger -Info -Message "Running on Command Mode"}
                        if ($HTML) {
                            if (-not $Silent) {Write-Logger -Notice -Message "Adding HTML setting to the command line"}
                            $SQLQuery = @"
SET MARKUP HTML ON
$SQLQuery
"@
                        }
                        if (-not $Silent) {Write-Logger -Info -Message "Running query on the database..."}
                        $Output = @"
$PipelineSettings
$SQLQuery
exit;
"@ | &"sqlplus" "-S" "$DBUser/$DBPass@$DBName"

                    } else {
                        if (-not $Silent) {Write-Error "Please use either -SQLFile or -SQLQuery to provide what you need to run on the database"}
                        exit
                    }
                    if ($Dump) {
                        if ($DumpFile.Contains("htm")) {
                            $OracleHtmlHeader | Out-File $DumpFile
                        }
                        $Output | Out-File $DumpFile -Append
                        if ($DumpFile.Contains("htm")) {
                            $OracleHtmlTail | Out-File $DumpFile -Append
                        }
                    } else {
                        $Output
                    }
                } else {
                    Write-Error "Database $DBName not reachable"
                }
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{
        if (-not $Silent) {Write-Logger -Info -Message "Finished the runs, cleaning up..."}
        if($PSCmdlet.ParameterSetName -eq 'BySQLFile') {
            Remove-Item -Path $toExecute
        }
        if (-not $Silent) {Write-Logger -Info -Message "Thanks for using this script."}
    }
}


# SIG # Begin Signature block
# MIID9jCCAt6gAwIBAgIJAIxehrC8IAp5MA0GCSqGSIb3DQEBBQUAMIGiMQswCQYD
# VQQGEwJDUjEQMA4GA1UECBMHSGVyZWRpYTEQMA4GA1UEBxMHSGVyZWRpYTEUMBIG
# A1UEChMLSW5kZXBlbmRlbnQxEzARBgNVBAsTClBvd2Vyc2hlbGwxFjAUBgNVBAMT
# DUplc3VzIFNhbmNoZXoxLDAqBgkqhkiG9w0BCQEWHWpzYW5jaGV6LmNvbnN1bHRh
# bnRAZ21haWwuY29tMB4XDTE3MTEyNDE2Mzc1MloXDTI3MTEyNTE2Mzc1MlowgaIx
# CzAJBgNVBAYTAkNSMRAwDgYDVQQIEwdIZXJlZGlhMRAwDgYDVQQHEwdIZXJlZGlh
# MRQwEgYDVQQKEwtJbmRlcGVuZGVudDETMBEGA1UECxMKUG93ZXJzaGVsbDEWMBQG
# A1UEAxMNSmVzdXMgU2FuY2hlejEsMCoGCSqGSIb3DQEJARYdanNhbmNoZXouY29u
# c3VsdGFudEBnbWFpbC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDS04f1yYYM/O3YlvlLGtEldsS8jBPP/c5kxrZz23Zj2p7wa56nWVpaOZLjJtqM
# Za/F/h3kclyxAXP9Xq7NA+heARYvY+64EGZqa3abuTbRSCvGB+WII/3snegbuaTD
# Nfi6NhuYZZezK7gHchgXtkPRQAAveT6mHwx2mT+RBRJ6iiDvxi+oBYySS8PU7pEa
# t70vAfur4Bi8NtJSsTOr3aC85eRIPnfauGbSeH+CeEQvVEBH3wsqn3NQB6oOWUMA
# UoaV2Lfn2KtFw5tENpo7CRMBDm5ar4h9oOEb4mIm4bDpgKLej7HsxRX6KCrJshlJ
# I26p0Y2LvRCpv73qYe44rsLhAgMBAAGjLTArMAkGA1UdEwQCMAAwEQYJYIZIAYb4
# QgEBBAQDAgTwMAsGA1UdDwQEAwIFIDANBgkqhkiG9w0BAQUFAAOCAQEAfhABlQsA
# VlpUjhPNjUxvCW2K2YPzSrv09l/yg5oBPMG+XQ5q1ZGA8cm7YUXlgu73rZXOeYjm
# r5GFCI+1LP0ol1KHFGNxGXKB8iMStUPrZ4rLNR/ycOX0+ObOPmat6RECDattmpQl
# F6Fo1Nm5eevwaagkqIDsIh1Jqt8kYMSvdYHXJ409Lwh4wIE/LP1zS9k6l+ZdDGGG
# GG2Qb4VMncjCdR0Srp2zRL9xGUf4p9cZIAJOuLqTJDYEraS/+zsJMLwrkypYAZ9t
# 0zGUG75Wc2MSSKrT2xuLuQIRKne/aal0usKhffqwqZ3/fc9XGGPUTIFFMbvsqQFf
# kg9v3E07CsmxmQ==
# SIG # End signature block
