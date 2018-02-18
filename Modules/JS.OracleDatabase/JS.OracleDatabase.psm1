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
   This function returns $true if the ORACLE_HOME variable is set or $false otherwise
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
   This function returns $true if the tnsping is successful, $false otherwise
.EXAMPLE
    if (Ping-OracleDB -TargetDB orcl) {
        Write-Output "Database pinged successfully"
        <Some commands>
    }
.EXAMPLE
    if (Ping-OracleDB -TargetDB orcl -Full | Select -Property PingStatus) {
        Write-Output "Database pinged successfully"
        <Some commands>
    } else {
        Write-Warning Ping-OracleDB -TargetDB orcl | Select -Property PingResult
    }
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBS to verify the reachability of a DB
#>
function Ping-OracleDB {
    [CmdletBinding()]
    [Alias("oraping")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # Flag to get full output or only boolean
        [Parameter(HelpMessage="Switch to get full output from the TNSPing Utility")]
        [Switch]$Full,
        # Parallelism degree desired
        [Parameter(HelpMessage="Parallelism degree for background jobs")]
        [int]$Parallelism = 1
    )
    Begin {
        if (-not (Test-OracleEnv)) {
            Write-Error -Category NotInstalled -Message "No ORACLE_HOME detected, please make sure your Oracle Environment is set" -RecommendedAction "Please install the Oracle Client Software, at least, and/or define your ORACLE_HOME environment variable pointing to the Oracle Client binary files."
            exit
        }
    }
    Process {
        $JobCount = 0
        While ($TargetDB.GetLength() -gt 0 -or $(Get-Job | ? { $_.Name -match "PingJob"}).ChildJobs.Count -gt 0 ) {
            if ($TargetDB.GetLength() -gt 0 -and $JobCount -lt $Parallelism) { # There are jobs in queue and open slots
                $DBName = $TargetDB.Get(0)
                $TargetDB.RemoveAt(0)
                Start-Job -Name "TNSPing_$DBName" -ArgumentList $DBName -ScriptBlock { tnsping $1 } | Out-Null
                $JobCount += 1
            } # There are jobs in queue - End
            if ($(Get-Job | ? { $_.Name -match "PingJob" -and $_.State -in @("Completed","Failed")}).ChildJobs.Count -gt 0) { # There are Completed jobs
                foreach ($JobName in $(Get-Job | ? { $_.Name -match "PingJob" -and $_.State -in @("Completed","Failed") })) {
                	$Pinged = Receive-Job $JobName
                    if ($Full) { # Full Output Switch
                        $PingBool=$Pinged[-1].Contains('OK')
                        $DBProps= [ordered]@{
                            [String]'DBName'=$DBName
                            [String]'PingResult'=$Pinged[-1]
                            [String]'Source'= $Pinged[-3]
                            [String]'Descriptor' = $($Pinged[-2] -split "Attempting to contact ")[1]
                            'PingStatus'=$PingBool
                        }
                        $DBObj = New-Object -TypeName PSObject -Property $DBProps
                        Write-Output $DBObj
                    } else { # Bool Output
                        $Pinged[-1].contains('OK')
                    } # EndIf - Full Output Switch
                    $JobCount -= 1
        		} # Job retrieval loop
            } # EndIf - There are Completed Jobs
        }
    }
}

<#
.Synopsys
    Returns a DB object
.DESCRIPTION
   This function returns a PSObject "OracleDatabase" with the database info
.EXAMPLE
    Get-OracleServices -TargetDB myorcl -List
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName information" -CurrentOperation "Pinging database" -PercentComplete 10
                if (Ping-OracleDB -TargetDB $TargetDB) {
                    Write-Progress -Activity "Gathering $DBName information" -CurrentOperation "Querying database" -PercentComplete 20
                    if ($DBUser) {
                        if (-not $DBPass) {
                            $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                            $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                        }
                        $LoginString = "${DBUser}/${DBPass}@${DBName}"
                        if ($DBUser -eq "SYS") {
                            $LoginString += " AS SYSDBA"
                        }

                    } else {
                        $LoginString = "/@$DBName"
                    }
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
'@ | &"sqlplus" "-S" "$LoginString"
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
function Get-OracleServices {
    [CmdletBinding()]
    [Alias("orasrvc")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Password if required
        [String]$DBPass,
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "Pinging $DBName databases" -PercentComplete 0
            $Query = @'
SELECT srv.name AS "ServiceName", NVL2(asrv.name,'ACTIVE','INACTIVE') AS "ServiceStatus", dsv.edition AS "EditionName"
FROM v$services srv
LEFT OUTER JOIN v$active_services asrv ON srv.name = asrv.name
JOIN dba_services dsv ON srv.name = dsv.name
WHERE srv.name NOT LIKE ('SYS%')
ORDER BY 1;
'@
            Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "Analizing $DBName output" -PercentComplete 35
            foreach ($DBName in $TargetDB) {
                if ($DBUser) {
                    if (-not $DBPass) {
                        $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                        $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                    }
                    if ($DBUser -eq "SYS") {
                        $LoginString += " AS SYSDBA"
                    }

                } else {
                    $LoginString = "/@$DBName"
                }
                Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
                }
            }
            Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "$DBName done" -PercentComplete 85
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
    }
}

<#
.Synopsis
   Returns the Sessions in an Oracle DB
.DESCRIPTION
   This function returns the Active Services in an Oracle DB
.EXAMPLE
    Get-OracleSessions -TargetDB myorcl -Username myDBAccount
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBAs to retrieve a full list of active services in a DB
#>
function Get-OracleSessions {
    [CmdletBinding()]
    [Alias("orasession")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # SQL filter to add in the WHERE section of the query
        [Parameter(HelpMessage="This must bu an ANSI SQL compliant WHERE clause")]
        [String]$SQLFilter,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Password if required
        [String]$DBPass,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt
    )
    Begin {
    }
    Process {
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            if ($SQLFilter) {
                if ($Query -contains "WHERE") {
                    if ($SQLFilter -match "^WHERE") {
                        $SQLFilter = $SQLFilter.Replace("WHERE","AND")
                    } else {
                        Write-Verbose "Filter is good"
                    }
                } else {
                Write-Verbose "No WHERE in the query"
                    if ($SQLFilter -match "^WHERE") {
                        Write-Verbose "Filter is good"
                    } else {
                        if ($SQLFilter -match "^AND") {
                            $SQLFilter = $SQLFilter.Replace("AND","WHERE")
                        } else {
                            $SQLFilter = "WHERE $SQLFilter"
                        }
                    }
                }
            }
            $Query = @"
SELECT q'{'}'||sid||','||serial#||',@'||inst_id||q'{'}' AS "Session"
    , service_name AS "ServiceName"
    , username AS "UserName"
    , status AS "Status"
    , osuser AS "OSUser"
    , machine AS "Machine"
    , program AS "Program"
    , module AS "Module"
    , sql_id AS "RunningSqlId"
FROM gv`$session
$SQLFilter;
"@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Users" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
                }
            }
            Write-Progress -Activity "Gathering $DBName Users" -CurrentOperation "$DBName done" -PercentComplete 85
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
    }
}

<#
.Synopsis
   Returns the Size an Oracle DB or its components, based on the paramaters passed
.DESCRIPTION
   This function returns the Active Services in an Oracle DB
.EXAMPLE
    Get-OracleSize -TargetDB myorcl -SizeType Full -Unit GB
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBAs to retrieve a full list of active services in a DB
#>
function Get-OracleSize {
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
        # Password if required
        [String]$DBPass,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Size types
        [Parameter(Mandatory = $true)]
        [ValidateSet("Full","Storage","Tablespace","Table")]
        [String]$SizeType,
        [ValidateSet("B","KB","MB","GB","TB","PB","EB","ZB")]
        [String]$Unit = "B"
    )
    Begin {
        Write-Verbose "Setting Unit value"
        $UnitValue = 1
        Switch ($Unit) {
            "B" {$UnitValue = 1 }
            "KB" { $UnitValue = 1024 }
            "MB" { $UnitValue = [Math]::Pow(1024,2) }
            "GB" { $UnitValue = [Math]::Pow(1024,3) }
            "TB" { $UnitValue = [Math]::Pow(1024,4) }
            "PB" { $UnitValue = [Math]::Pow(1024,5) }
            "EB" { $UnitValue = [Math]::Pow(1024,6) }
            "ZB" { $UnitValue = [Math]::Pow(1024,7) }
        }
        Write-Verbose "Unit Value: $UnitValue"
    }
    Process {
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            Write-Verbose "Building FileSystemQuery"
            $FileSystemQuery = @"
SELECT substr(file_name,1,instr(file_name,'/',-1)) AS "FileName"
    , ROUND(SUM(user_bytes)/$UnitValue,2) AS "Used$Unit"
    , ROUND(SUM(BYTES)/$UnitValue,2) AS "Allocated$Unit"
    , ROUND(SUM(maxbytes)/$UnitValue,2) AS "Max$Unit"
FROM dba_data_files, GLOBAL_NAME
GROUP BY substr(file_name,1,instr(file_name,'/',-1))
UNION ALL
SELECT NAME AS "FileName", space_used/$UnitValue AS "Used$Unit", space_limit/$UnitValue AS "Allocated$Unit", space_limit/$UnitValue AS "Max$Unit"
FROM v`$recovery_file_dest;
"@
            Write-Verbose "Building TablespaceQuery"
            $TableSpaceQuery = @"
SELECT ts.tablespace_name AS "Tablespace"
    , ROUND(size_info.used/$UnitValue,2) AS "Used_$Unit"
    , ROUND(size_info.alloc/$UnitValue,2) AS "Allocated_$Unit"
    , ROUND(size_info.maxb/$UnitValue,2) AS "Max_$Unit"
    , ROUND(size_info.pct_used,2) AS "Percent_Used"
FROM
      (
      select  a.tablespace_name,
             a.bytes_alloc alloc,
             nvl(b.bytes_free, 0) free,
             a.bytes_alloc - nvl(b.bytes_free, 0) used,
			1 - (nvl(b.bytes_free, 0) / A.bytes_alloc) pct_used,
             round(maxbytes) Maxb
      from  ( select  f.tablespace_name,
                     sum(f.bytes) bytes_alloc,
                     sum(decode(f.autoextensible, 'YES',f.maxbytes,'NO', f.bytes)) maxbytes
              from dba_data_files f
              group by tablespace_name) a,
            ( select  f.tablespace_name,
                     sum(f.bytes)  bytes_free
              from dba_free_space f
              group by tablespace_name) b
      where a.tablespace_name = b.tablespace_name (+)
      union all
      select h.tablespace_name,
             sum(h.bytes_free + h.bytes_used) alloc,
             sum((h.bytes_free + h.bytes_used) - nvl(p.bytes_used, 0)) free,
             sum(nvl(p.bytes_used, 0)) used,
             1 - sum((h.bytes_free + h.bytes_used) - nvl(p.bytes_used, 0)) / sum(h.bytes_used + h.bytes_free) pct_used,
             sum(decode(f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxb
      from   sys.v_`$TEMP_SPACE_HEADER h, sys.v_`$Temp_extent_pool p, dba_temp_files f
      where  p.file_id(+) = h.file_id
      and    p.tablespace_name(+) = h.tablespace_name
      and    f.file_id = h.file_id
      and    f.tablespace_name = h.tablespace_name
      group by h.tablespace_name
      ) size_info,
      sys.dba_tablespaces ts, sys.dba_tablespace_groups tsg, global_name
WHERE ts.tablespace_name = size_info.tablespace_name
and   ts.tablespace_name = tsg.tablespace_name (+);
"@
            Write-Verbose "Building TableQuery"
            $TableQuery = @"
SELECT x.owner||'.'||x.table_name AS "Table"
    , ROUND(SUM(bytes)/$UnitValue,2) AS "Size_$Unit"
    , nvl(z.num_rows, 0) AS "Num_Rows"
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
		trunc(SYSDATE), x.table_name, x.owner, nvl(z.num_rows, 0)
	HAVING SUM(BYTES) >= 1;
"@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Pinging $DBName databases" -PercentComplete 0
                Write-Verbose "Building ASMQuery"
                $ASMQuery = @"
SELECT disk_group AS "DiskGroup"
    , ROUND(SUM(used)/$UnitValue,2) AS "Used$Unit"
    , ROUND(SUM(alloc)/$UnitValue,2) AS "Allocated$Unit"
    , ROUND(MIN(maxb)/$UnitValue,2) AS "Max$Unit"
FROM (
    WITH file_hierarchy AS (
        SELECT SYS_CONNECT_BY_PATH(NAME,' ') as name, group_number, file_number, file_incarnation
        FROM v`$asm_alias
        CONNECT BY PRIOR reference_index = parent_index
    )
    SELECT TRIM(SUBSTR(fh.name,1,INSTR(fh.name,' ',2))) AS db_name, dg.name as DISK_GROUP, af.BYTES AS USED, af.SPACE AS ALLOC, dg.TOTAL_MB*1024*1024 AS MAXB
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
)
WHERE db_name NOT IN ('DATAFILE','CONTROLFILE','FLASHBACK','ARCHIVELOG','ONLINELOG','CHANGETRACKING','PARAMETERFILE')
AND  UPPER(db_name) = UPPER('$DBName')
GROUP BY db_name, disk_group
ORDER BY DB_NAME;
"@
                Write-Verbose "Building FullASMQuery"
                $FullASMQuery = @"
SELECT db_name AS "Database"
    , disk_group AS "DiskGroup"
    , ROUND(SUM(used)/$UnitValue,2) AS "Used_$Unit"
    , ROUND(SUM(alloc)/$UnitValue,2) AS "Allocated_$Unit"
    , ROUND(MIN(maxb)/$UnitValue,2) AS "Max_$Unit"
FROM (
    WITH file_hierarchy AS (
        SELECT SYS_CONNECT_BY_PATH(NAME,' ') as name, group_number, file_number, file_incarnation
        FROM v`$asm_alias
        CONNECT BY PRIOR reference_index = parent_index
    )
    SELECT TRIM(SUBSTR(fh.name,1,INSTR(fh.name,' ',2))) AS db_name, dg.name as DISK_GROUP, af.BYTES AS USED, af.SPACE AS ALLOC, dg.TOTAL_MB*1024*1024 AS MAXB
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
)
WHERE db_name NOT IN ('DATAFILE','CONTROLFILE','FLASHBACK','ARCHIVELOG','ONLINELOG','CHANGETRACKING','PARAMETERFILE')
GROUP BY db_name, disk_group
ORDER BY DB_NAME;
"@
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
                    "Tablespace" {
                        $Query = $TableSpaceQuery
                    }
                    "Table" {
                        $Query = $TableQuery
                    }
                }
                if ($DBUser) {
                    $LoginString = "${DBUser}/${DBPass}@${DBName}"
                } else {
                    $LoginString = "/@$DBName"
                }
                Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Analizing $DBName output" -PercentComplete 35
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
                }
            }
            Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "$DBName done" -PercentComplete 85
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
function Get-OracleOptions {
    [CmdletBinding()]
    [Alias("oraoptions")]
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
                    $Query=@'
SELECT comp_name AS "ComponentName"
    , status AS "Status"
    , modified AS "LastModified"
FROM dba_registry
ORDER BY 1;
'@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Sizes" -CurrentOperation "Pinging $DBName databases" -PercentComplete 0
                if ($DBUser) {
                    $LoginString = "${DBUser}/${DBPass}@${DBName}"
                } else {
                    $LoginString = "/@$DBName"
                }
                Write-Progress -Activity "Gathering $DBName Options and Statuses" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
                }
            }
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
    }
}

<#
.Synopsis
    Query an Oracle database to get global name, host name, db unique name and
.DESCRIPTION
    This function returns the global name of the database
.EXAMPLE
    Get-OracleGlobalName -TargetDB <DB NAME> [-ErrorLog]
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OracleNames {
    [CmdletBinding()]
    [Alias("oranames")]
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            foreach ($DBName in $TargetDB) {
                if (($DBName)) {
                    if ($DBUser) {
                        $LoginString = "${DBUser}/${DBPass}@${DBName}"
                    } else {
                        $LoginString = "/@$DBName"
                    }
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
"@ | &"sqlplus" "-S" "$LoginString"
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            $Query = @'
SELECT instance_number AS "InstanceNumber"
    , instance_name AS "InstanceName"
FROM gv$instance ORDER BY 1;
exit
'@
            foreach ($DBName in $TargetDB) {
                if ($DBUser) {
                    $LoginString = "${DBUser}/${DBPass}@${DBName}"
                } else {
                    $LoginString = "/@$DBName"
                }
                Write-Progress -Activity "Gathering $DBName Instances" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            $Query = @'

SELECT host_name AS "HostName"
    , instance_name as "InstanceName"
FROM gv$instance
ORDER BY 1;
'@
            foreach ($DBName in $TargetDB) {
                if ($DBUser) {
                    $LoginString = "${DBUser}/${DBPass}@${DBName}"
                } else {
                    $LoginString = "/@$DBName"
                }
                Write-Progress -Activity "Gathering $DBName Hosts" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
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
        # SQL filter to add in the WHERE section of the query
        [Parameter(HelpMessage="This must bu an ANSI SQL compliant WHERE clause")]
        [String]$SQLFilter,
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            Write-Progress -Activity "Gathering Users on $DBName..." -CurrentOperation "Querying Database" -PercentComplete 30
            if ($SQLFilter) {
                if ($Query -contains "WHERE") {
                    if ($SQLFilter -match "^WHERE") {
                        $SQLFilter = $SQLFilter.Replace("WHERE","AND")
                    } else {
                        Write-Verbose "Filter is good"
                    }
                } else {
                Write-Verbose "No WHERE in the query"
                    if ($SQLFilter -match "^WHERE") {
                        Write-Verbose "Filter is good"
                    } else {
                        if ($SQLFilter -match "^AND") {
                            $SQLFilter = $SQLFilter.Replace("AND","WHERE")
                        } else {
                            $SQLFilter = "WHERE $SQLFilter"
                        }
                    }
                }
            }
            $Query = @"
SELECT username AS "UserName"
    , external_name AS "ExternalName"
    , account_status AS "Status"
    , created AS "Created"
    , default_tablespace AS "Tablespace"
    , profile AS "ProfileName"
FROM dba_users
$SQLFilter;
"@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Users" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            $Query =  @'
SELECT dbid FROM v$database;
'@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName DBID" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
			Write-Debug "Database pinged successfully"
            if ($DBUser) {
                $LoginString = "${DBUser}/${DBPass}@${DBName}"
            } else {
                $LoginString = "/@$DBName"
            }
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
"@ | &"sqlplus" "-S" "$LoginString"
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
"@ | &"sqlplus" "-S" "$LoginString"
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            # Using here-string to pipe the SQL query to SQL*Plus
            if ($DBUser) {
                $LoginString = "${DBUser}/${DBPass}@${DBName}"
            } else {
                $LoginString = "/@$DBName"
            }
           if ($Mark -eq "start") {
                @"
SET HEADING OFF
SET PAGESIZE 0
SELECT TO_CHAR(MAX(begin_interval_time),'YYYY-MM-DD HH24:MI:SS')
FROM dba_hist_snapshot
WHERE snap_id = $Snapshot
AND dbid = $DBID;
EXIT
"@ | &"sqlplus" "-S" "$LoginString"
            } else {
                @"
SET HEADING OFF
SET PAGESIZE 0
SELECT TO_CHAR(MAX(end_interval_time),'YYYY-MM-DD HH24:MI:SS')
FROM dba_hist_snapshot
WHERE snap_id = $Snapshot
AND dbid = $DBID;
EXIT
"@ | &"sqlplus" "-S" "${DBUser}/${DBPass}@${TargetDB}"
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
}

<#
.Synopsis
    Returns Long running queries as per Schemas and SecondsLimit parameters
.DESCRIPTION

.EXAMPLE

.ROLE

#>
function Get-OracleLongOperations {
    [CmdletBinding()]
    [Alias("oralongops")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,
        # Target Schema
        [String[]]$UserName,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Seconds to start considering long running queries
        [int]$SecondsLimit = 0,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{
        if ($UserName) {
            if ($UserName.Count -eq 1) {
                $UserFilter = "AND username = '$Schema'"
            } elseif  ($UserName.Count -gt 1) {
                $UserFilter = "AND username IN ("
                foreach ($SchemaName in $UserName) {
                    $UserFilter += "'$SchemaName',"
                }
                $UserFilter = $UserFilter.TrimEnd(',') + ")"
            }
        } else {
                $UserFilter = "AND username LIKE '%'"
        }
    }
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            $Query = @"
SELECT s.username AS "UserName"
    , l.SID||':'||l.SERIAL# AS "Session"
    , l.opname AS "Operation"
    , l.TOTALWORK AS "Total"
    , l.SOFAR AS "Current"
    , l.SOFAR/l.TOTALWORK AS "Percent"
FROM gv`$session_longops l, gv`$session s
WHERE totalwork > 0
AND SOFAR/TOTALWORK < 1
AND l.SID = s.SID
AND l.serial# = s.serial#;
"@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Long Running SQLs" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
                }
            }
        }
    }
}

<#
.Synopsis
    Returns Long running queries as per Schemas and SecondsLimit parameters
.DESCRIPTION

.EXAMPLE

.ROLE

#>
function Get-OracleLongRunQueries {
    [CmdletBinding()]
    [Alias("oralongsql")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,
        # Target Schema
        [String[]]$UserName,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Seconds to start considering long running queries
        [int]$SecondsLimit = 0,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{
        if ($UserName) {
            if ($UserName.Count -eq 1) {
                $UserFilter = "AND username = '$Schema'"
            } elseif  ($UserName.Count -gt 1) {
                $UserFilter = "AND username IN ("
                foreach ($SchemaName in $UserName) {
                    $UserFilter += "'$SchemaName',"
                }
                $UserFilter = $UserFilter.TrimEnd(',') + ")"
            }
        } else {
                $UserFilter = "AND username LIKE '%'"
        }
    }
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            $Query = @"
SELECT ss.sql_id AS "SqlId"
    , q'{'}'||ss.sid||','||ss.serial#||'@'||ss.inst_id||q'{'}' AS "Session"
    , ss.username AS "UserName"
    , ss.machine AS "Machine"
    , ss.module AS "Module"
    , ss.action AS "Action"
    , ((sysdate-sql_exec_start)*24*60*60) AS "Seconds"
    , to_char(sql_exec_start,'HH24:MI:SS') AS "StartTime"
FROM gv`$session ss, gv`$sql sq
where ss.sql_id=sq.sql_id
and ss.inst_id=sq.inst_id
and status='ACTIVE'
$UserFilter
and (sysdate-sql_exec_start)*24*60*60 > $SecondsLimit;
"@
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Gathering $DBName Long Running SQLs" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUser $DBUser -DBPass $DBPass
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
                }
            }
        }
    }
}

<#
.Synopsis
    Returns SQL Id, Text and bind variables of a given SQL Id
.DESCRIPTION

.EXAMPLE

.ROLE

#>
function Get-OracleSQLText {
    [CmdletBinding()]
    [Alias("orasqltxt")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$True,
            Position=0,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$True,
            Position=1,
            HelpMessage="Target Oracle Database name")]
        [String]$SqlId,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Password if required
        [String]$DBPass,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{
    }
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $DBPass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
            }
            $Query = @"
SELECT sql_id AS "SqlId"
    , t.sql_text AS "SQLText"
    , b.name AS "BindName"
    , b.value_string AS "BindValue"
FROM
  v`$sql t
JOIN
  v`$sql_bind_capture b  using (sql_id)
WHERE
  b.value_string is not null
AND
  sql_id='$SqlId'
;
"@
            if ($DBUser) {
                Use-OracleDB -TargetDB $TargetDB -SQLQuery $Query -DBuser "$DBUser" -DBPass $DBPass
            } else {
                Use-OracleDB -TargetDB $TargetDB -SQLQuery $Query
            }
        }
    }
}

<#
.Synopsis
    Returns SQL Id, Text and bind variables of a given SQL Id
.DESCRIPTION

.EXAMPLE

.ROLE

#>
function Get-OracleDBVersion {
    [CmdletBinding()]
    [Alias("oraversion")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$True,
            Position=0,
            HelpMessage="Target Oracle Database name")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Password if required
        [String]$DBPass,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{
    }
    Process{
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            $Query = @"
SELECT VERSION, comments
FROM (
	SELECT VERSION, comments
	FROM SYS.registry`$history
	WHERE VERSION = (
		SELECT MAX(VERSION)
		FROM SYS.registry`$history
		)
	ORDER BY action_time DESC
	)
WHERE ROWNUM = 1;
"@
            foreach ($DBName in $TargetDB) {
                if ($DBUser) {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query -DBUSer "$DBUser" -DBPass "$DBPass"
                } else {
                    Use-OracleDB -TargetDB $DBName -SQLQuery $Query
                }
            }
        }
    }
}


<#
.Synopsis
    Creates a DB link on the target database
.DESCRIPTION

.EXAMPLE

.ROLE

#>
function Add-OracleDBLink {
    [CmdletBinding()]
    [Alias("add-dblink")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Schema Name
        [Parameter(Mandatory=$true,
            HelpMessage="Onwer schema for the DB Link")]
        [String]$SchemaName,
        # DB Link Name
        [Parameter(Mandatory=$true,
            HelpMessage="DB Link Name")]
        [String]$LinkName,
        # DB Link Username
        [Parameter(Mandatory=$true,
            HelpMessage="Username to connect to using the db link")]
        [String]$LinkUser,
        # DB Link Password
        [Parameter(HelpMessage="Password to use with the db link")]
        [String]$LinkPassword,
        # DB Link Password Promt flag
        [Parameter(HelpMessage="Ask for the password to use with the db link")]
        [Switch]$LinkPasswordPrompt,
        # DB Link Password Values
        [Parameter(HelpMessage="Password to use with the db link as in IDENTIFIED BY VALUES")]
        [String]$LinkPswdValues,
        # DB Link Host (Target database)
        [Parameter(Mandatory = $true,
            HelpMessage="DB Link target databasse name/descriptor")]
        [String]$LinkTarget
    )
    Process {
        if ($LinkPasswordPrompt) {
            $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $LinkUser at $LinkTarget"
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
            $LinkPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        }
        foreach ($DBName in $TargetDB) {
            if (Test-OracleEnv) {
                if ($PasswordPrompt) {
                    if ($DBUser.Length -eq 0) {
                        $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                    }
                    $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                    $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                }
                if ($LinkPswdValues) {
                    $CreateCommand = "CREATE DATABASE LINK $LinkName CONNECT TO $LinkUser IDENTIFIED BY VALUES '$LinkPswdValues' USING '$LinkTarget'"
                } elseif ($LinkPassword -and -not $LinkPswdValues) {
                    $CreateCommand = "CREATE DATABASE LINK $LinkName CONNECT TO $LinkUser IDENTIFIED BY `"$LinkPassword`" USING '$LinkTarget'"
                } else {
                    $LinkPass = Use-OracleDB -TargetDB $LinkTarget -SQLQuery @"
                    SET LINESIZE 5000
                    SELECT spare4 AS `"LinkPass`" FROM sys.user$ WHERE name = '$LinkUser';
"@ | Select -ExpandProperty LinkPass
                    $CreateCommand = "CREATE DATABASE LINK $LinkName CONNECT TO $LinkUser IDENTIFIED BY VALUES '$LinkPass' USING '$LinkTarget'"
                }

                $Query = @"
    ALTER SESSION SET CURRENT_SCHEMA=$SchemaName;
    CREATE OR REPLACE PROCEDURE CREATE_DB_LINK AS
	    begin
		    execute immediate q'{$CreateCommand}';
	    end CREATE_DB_LINK;
    /
    exec CREATE_DB_LINK;

    DROP PROCEDURE CREATE_DB_LINK;
"@
        Write-Verbose $Query
        Remove-OracleDBLink -TargetDB $DBName -LinkName $LinkName -SchemaName $SchemaName -ErrorAction SilentlyContinue
        Write-Verbose $Query
        $Output = Use-OracleDB -TargetDB $DBName -SQLQuery $Query -PlainText *>&1
        [String]$ResultText=""
        foreach ($line in $Output) {
            if ($line -imatch "^ORA-") {
                $ResultText = $line
            } elseif ($line -imatch "successfully") {
                $ResultText = "Creation successful!"
            }
        }
        $ResultProps = [ordered]@{ 'DBName' = $DBName;
            'SchemaName' = $SchemaName;
            'LinkName' = $LinkName;
            'TestResult' = $ResultText
        }
        $ResObj = New-Object -TypeName PSObject -Property $ResultProps
        Write-Output $ResObj
        Test-OracleDBLink -TargetDB $DBName -LinkName $LinkName -SchemaName $SchemaName
            }
        }
    }
}

<#
.Synopsis
    Creates a DB link on the target database
.DESCRIPTION

.EXAMPLE

.ROLE

#>
function Test-OracleDBLink {
    [CmdletBinding()]
    [Alias("test-dblink")]
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
        # Schema Name
        [Parameter(Mandatory=$true,
            HelpMessage="Onwer schema for the DB Link")]
        [String]$SchemaName,
        # DB Link Name
        [Parameter(Mandatory=$true,
            HelpMessage="DB Link Name")]
        [String]$LinkName
    )
    Process {
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            $Query = @"
ALTER SESSION SET CURRENT_SCHEMA=$SchemaName;
CREATE OR REPLACE FUNCTION TEST_DB_LINK RETURN VARCHAR2 AS
    v_result VARCHAR2(100);
begin
	SELECT 'CONNECTED TO '||global_name AS "TestResult" INTO v_result FROM global_name@$LinkName;
    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN SQLERRM;
end TEST_DB_LINK;
/
SELECT TEST_DB_LINK AS "TestResult" FROM dual;

--DROP FUNCTION TEST_DB_LINK;
"@
            #Write-Verbose $Query
            $Output = Use-OracleDB -TargetDB $TargetDB -SQLQuery $Query -PlainText *>&1
            [String]$ResultText=""
            foreach ($line in $Output) {
                if ($line -imatch "^CONNECTED") {
                    $ResultText = "$line "
                } elseif ($line -imatch "^ORA-") {
                    $ResultText = "TEST FAILED, check DB Link Target"
                }
            }
            $LinkData = Use-OracleDB -TargetDB $TargetDB -SQLQuery "SELECT username,host FROM dba_db_links WHERE owner = UPPER('$SchemaName') AND db_link = UPPER('$LinkName');"
            $ResultProps = [ordered]@{ 'DBName' = $DBName;
                'SchemaName' = $SchemaName;
                'LinkName' = $LinkName;
                'LinkUser' = $LinkData | Select -ExpandProperty USERNAME;
                'LinkTarget' = $LinkData | Select -ExpandProperty HOST;
                'TestResult' = $ResultText
            }
            $ResObj = New-Object -TypeName PSObject -Property $ResultProps
            Write-Output $ResObj
        }
    }
}


<#
.Synopsis
    Creates a DB link on the target database
.DESCRIPTION

.EXAMPLE

.ROLE

#>
function Remove-OracleDBLink {
    [CmdletBinding()]
    [Alias("rm-dblink")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Password if required
        [String]$DBPass,
        # Flag to ask for a password
        [Alias("p")]
        [Switch]$PasswordPrompt,
        # Schema Name
        [Parameter(Mandatory=$true,
            HelpMessage="Onwer schema for the DB Link")]
        [String]$SchemaName,
        # DB Link Name
        [Parameter(Mandatory=$true,
            HelpMessage="DB Link Name")]
        [String]$LinkName
    )
    Process {
        foreach ($DBName in $TargetDB) {
            if (Test-OracleEnv) {
                if ($PasswordPrompt) {
                    if ($DBUser.Length -eq 0) {
                        $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                    }
                    $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                    $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                }
            $Query = @"
    ALTER SESSION SET CURRENT_SCHEMA=$SchemaName;
    CREATE OR REPLACE PROCEDURE DROP_DB_LINK(P_NAME in varchar2) as
	    begin
		    execute immediate 'DROP DATABASE LINK '||P_NAME;
	    end DROP_DB_LINK;
    /
    exec DROP_DB_LINK('$LinkName');

    DROP PROCEDURE DROP_DB_LINK;
"@
    Write-Verbose $Query -Verbose
        $Output = Use-OracleDB -TargetDB $DBName -SQLQuery $Query -PlainText *>&1
        [String]$ResultText=""
        foreach ($line in $Output) {
            if ($line -imatch "^ORA-") {
                $ResultText = $line
            } elseif ($line -imatch "successfully") {
                $ResultText = "Drop successful!"
            }
        }
        $ResultProps = [ordered]@{ 'DBName' = $DBName;
            'SchemaName' = $SchemaName;
            'LinkName' = $LinkName;
            'TestResult' = $ResultText
        }
        $ResObj = New-Object -TypeName PSObject -Property $ResultProps
        Write-Output $ResObj
            }
        }
    }
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
        # Password if required
        [String]$DBPass,
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            if ($DBUser) {
                $LoginString = "${DBUser}/${DBPass}@$TargetDB"
            } else {
                $LoginString = "/@$TargetDB"
            }
            $InstNumber = $Instance.Substring($Instance.Length-1)
            Write-Verbose "Instance Number: $InstNumber"
            # Using here-string to pipe the SQL query to SQL*Plus
            $Output = @"
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
"@ | &"sqlplus" "-S" "$LoginString"
            Write-Debug "$Output"
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
        # Password if required
        [String]$DBPass,
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            if ($DBUser) {
                $LoginString = "${DBUser}/${DBPass}@$TargetDB"
            } else {
                $LoginString = "/@$TargetDB"
            }
			Write-Output "Launching AWR Global Report"
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
"@ | &"sqlplus" "-S" "$LoginString"
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
        # Password if required
        [String]$DBPass,
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            if ($DBUser) {
                $LoginString = "${DBUser}/${DBPass}@$TargetDB"
            } else {
                $LoginString = "/@$TargetDB"
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
"@ | &"sqlplus" "-S" "$LoginString"
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
        # Password if required
        [String]$DBPass,
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
        Write-Information "PS Oracle Performance Reports Generator"
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Pinging $TargetDB} Datbase"
            if (Ping-OracleDB -TargetDB $TargetDB) {
				Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Database pinged successfully"
                Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Gathering DBID"
                [String]$TempStr = Get-OracleDBID -TargetDB $TargetDB | Select -ExpandProperty DBID
                [bigint]$DBID = $TempStr.Trim(' ')
                Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "DBID for $TargetDB : $DBID"
                Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Getting Snapshot numbers"
                [String]$StrSnapshot = Get-OracleSnapshot -TargetDB $TargetDB -TimeStamp $StartTime.AddSeconds(59).ToString("yyyy-MM-dd HH:mm:ss") -Mark start
                [bigint]$StartSnapshot = [bigint]$StrSnapshot.trim(' ')
                [String]$StrSnapshot = Get-OracleSnapshot -TargetDB $TargetDB -TimeStamp $EndTime.ToString("yyyy-MM-dd HH:mm:ss") -Mark end
                [bigint]$EndSnapshot = [bigint]$StrSnapshot.trim(' ')
				Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Starting Snapshot: $StartSnapshot | Ending Snapshot: $EndSnapshot"
                Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Getting Snapshot times"
                [String]$StartSnapTime = Get-OracleSnapshotTime -TargetDB $TargetDB -DBID $DBID -Snapshot $StartSnapshot -Mark start
                [String]$EndSnapTime = Get-OracleSnapshotTime -TargetDB $TargetDB -DBID $DBID -Snapshot $EndSnapshot -Mark end
                Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Starting Snapshot Time: $StartSnapTime | Ending Snapshot Time: $EndSnapTime"
                Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Getting Oracle database instances"
                $Instances = Get-OracleInstances -TargetDB $TargetDB | Select -ExpandProperty InstanceName
                Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Instances found: $Instances"
                if ($AWR) {
                    Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Generating AWR Report Set"
                    $ORAOutput = Get-OracleAWRReport -TargetDB $TargetDB -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                    foreach ($Instance in $Instances) {
                        if ($Instance.Length -gt 0) {
                            Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Launching AWR Instance Report for $Instance"
                            $ORAOutput = Get-OracleAWRInstanceReport -TargetDB $TargetDB -Instance $Instance -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                        }
                    }
                    if ($Compress) {
                        Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Compressing AWR reports set"
                        zip -9m AWR_${TargetDB}_${StartSnapshot}_${EndSnapshot}_reports.zip awr*.htm*
                    }
                }
                if ($ADDM) {
                    Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Generating ADDM Report Set"
                    foreach ($Instance in $Instances) {
                        if ($Instance.Length -gt 0) {
                            Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Launching ADDM Instance #$InstNumber Report for $Instance"
                            $ORAOutput = Get-OracleADDMInstanceReport -TargetDB $TargetDB -Instance $Instance -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                        }
                    }
                    if ($Compress) {
                        Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Compressing ADDM reports set"
                        zip -9m ADDM_${TargetDB}_${StartSnapshot}_${EndSnapshot}_reports.zip addm*.*
                    }
                }
                if ($SendMail) {
                   if ($EmailAddress.Length -lt 6) {
                        Write-Progress -Activity "Generating Performance Reports" -CurrentOperation "Please enter a valid email address"
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
    Use-OracleDB -TargetDB orcl -SQLQuery "SELECT * FROM dba_tables WHERE owner = 'SYSMAN';" | Format-Table
.EXAMPLE
    Use-OracleDB -TargetDB orcl -SQLScript 'C:\path\to\file.sql' -Dump -DumpFile C:\path\to\dump\file.out> -ErrorLog
.EXAMPLE
    Use-OracleDB -TargetDB <DB NAME> -SQLQuery "SELECT 1 FROM DUAL;" -Dump -DumpFile C:\path\to\dump\file.out> -ErrorLog
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
        # Password if required
        [String]$DBPass,
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
        [String]$DumpFile,
        # Switch to force get HTML output
        [Parameter(
            HelpMessage="Flags the output to be HTML")]
        [Switch]$HTML,
        [Parameter(
            HelpMessage="Flags the output to be plain text")]
        [Switch]$PlainText,
        [Parameter(
            HelpMessage="Flags the output to be clean without feedback or headers or anything else")]
        [Switch]$Silent,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin {
        if ($DumpFile) {
            $Dump = $true
        }
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
        if (-not $PlainText -and -not $HTML) {
            $PipelineSettings=@"
SET PAGESIZE 50000
SET LINESIZE 32767
SET FEEDBACK OFF
SET VERIFY OFF
SET WRAP OFF
SET TRIM ON
SET NULL '- Null -'
SET COLSEP '|'
"@
        }
        Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Checking Oracle variables..."
        if (Test-OracleEnv) {
            if ($PasswordPrompt) {
                if ($DBUser.Length -eq 0) {
                    $DBUser = Read-Host -Prompt "Please enter the Username to connect to the DB"
                }
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Checking Run-Mode..."
                if ($DBUser) {
                    $LoginString = "${DBUser}/${DBPass}@${DBName}"
                    if ($DBUser -eq "SYS") {
                        $LoginString += " AS SYSDBA"
                    }
                } else {
                    $LoginString = "/@$DBName"
                }
                if ($PSCmdlet.ParameterSetName -eq 'BySQLFile') {
                    $PlainText=$true
                    Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Running on Script Mode"
                    Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Checking script for settings and exit string"
                    $tmpScript = Get-Content -Path $SQLScript
                    $toExecute = "$env:TEMP/runthis_$PID.sql"
                    "-- AUTOGENERATED TEMPORARY FILE" | Out-File -Encoding ASCII $toExecute
                    if ($HTML) {
                        Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Adding HTML output setting"
                        "SET MARKUP HTML ON" | Out-File -Encoding ASCII $toExecute -Append
                    }
                    foreach ($line in $tmpScript) {
                        "$line" | Out-File -Encoding ASCII $toExecute -Append
                    }
                    if(-not $tmpScript[-1].ToLower().Contains("exit")) {
                        Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Adding EXIT command"
                        "exit;" | Out-File -Encoding ASCII $toExecute -Append
                    }
                    Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Running script. Please wait..."
                    $Output = &"sqlplus" "-S" "$DBUser/$DBPass@$DBName" "@$toExecute"
                } elseif ($PSCmdlet.ParameterSetName -eq 'BySQLQuery') {
                    Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Running on Command Mode"
                    if ($HTML) {
                        Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Adding HTML setting to the command line"
                        $SQLQuery = @"
SET MARKUP HTML ON
$SQLQuery
"@
                    }
                    Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Running query on $DBName database..."
                    if ($PlainText) { Write-Output "Running query on $DBName database...`n$SQLQuery" }
                    $Output = @"
$PipelineSettings
$SQLQuery
exit;
"@ | &"sqlplus" "-S" "$LoginString"
                } else {
                    Write-Error "Please use either -SQLFile or -SQLQuery to provide what you need to run on the database"
                    exit
                } # ParameterSet BySQLFile or BySQLQuery
                foreach ($Line in $Output) {
                    Write-Verbose "Analizing $Line"
                    if ($Line -match "^ORA-" -or $Line -match "^SP2-" -or $Line -match "^PLS-") {
                        Write-Verbose "Found Error in Output"
                        $ErrorInOutput=$true
                        if ($PlainText) {
                            Write-Warning "$Line"
                        } else {
                            Write-Verbose "Query: $SQLQuery"
                            $HeaderLine = $SQLQuery.Replace("`n"," ")
                            $HeaderLine = $HeaderLine.Replace("(","").Replace(")","")
                            $HeaderLine = $($HeaderLine -split "select")[1]
                            $HeaderLine = $($HeaderLine -split "from")[0]
                            $HeaderLine = $HeaderLine.ToUpper().Replace("DISTINCT(","").Replace("COUNT(","")
                            $HeaderLine = $HeaderLine.Replace(",","|")
                            Write-Verbose "HeaderLine: $HeaderLine"
                            $DBProps = @{ 'DBName' = [String]$DBName }
                            $ResObj = New-Object -TypeName PSObject -Property $DBProps
                            $ColCounter = 0
                            if ([String]$HeaderLine -notmatch "\|") {
                                Write-Verbose "Single Header found"
                                if ($HeaderLine -like "* AS *") {
                                    $Header = $($HeaderLine -split " AS ")[1].replace('"','')
                                } else  {
                                    $Header = $HeaderLine
                                }
                            } else {
                                foreach ($Value in $HeaderLine -split "\|") {
                                    Write-Verbose "Processing Header: $Value"
                                    $Header = $Value
                                    if ($Value -like "* AS *") {
                                        Write-Verbose "$($Value -split " AS ")"
                                        $Header = $($Value -split " AS ")[1].replace('"','')
                                    }
                                    Write-Verbose "Adding prop! | PropertyName: $Header | Value: $Value"
                                    $ResObj | Add-Member -MemberType NoteProperty -Name $Header.Trim() -Value " "
                                }
                                $ColCounter++
                            }
                            Write-Verbose "Adding prop! | PropertyName: ErrorMsg | Value: $Line"
                            $ResObj | Add-Member -MemberType NoteProperty -Name 'ErrorMsg' -Value $Line
                            Write-Output $ResObj
                            Break
                        }
                    }
                }
                if (-not $ErrorInOutput) {
                    if ($Dump) {
                        if ($DumpFile.Contains("htm")) {
                            $OracleHtmlHeader | Out-File $DumpFile -Append
                        }
                        $Output | Out-File $DumpFile -Append
                        if ($DumpFile.Contains("htm")) {
                            $OracleHtmlTail | Out-File $DumpFile -Append
                        }
                    } elseif ($PlainText) {
                        $Output
                    } else {
                        $Counter = 1
                        foreach ($Row in $Output -split "`n") {
                            $TempList = ""
                            foreach ($Item in $Row -split '\|') {
                                if ($([String]$Item).Trim()) {
                                    $TempList += $([String]$Item).Trim() + '|'
                                }
                            }
                            $Row = $TempList.Trim("|")
                            if ($Row -match "[a-z0-9]") {
                                Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Working on resultset $Row"
                                if ($Counter -eq 1) {
                                    Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Building Column List"
                                    $ColumnList=""
                                    Write-Verbose "Processing $($Row -split '\|')"
                                    foreach ($Column in @($Row -split "\|")) {
                                        $ColumnList += "$Column|"
                                    }
                                    $ColumnList = $ColumnList.TrimEnd("|")
                                    Write-Verbose "Headers: $ColumnList"
                                    $Counter++
                                } else {
                                    Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Building Output object"
                                    $DBProps = @{ 'DBName' = [String]$DBName }
                                    $ResObj = New-Object -TypeName PSObject -Property $DBProps
                                    $ColCounter = 0
                                    Write-Verbose "Row: $Row"
                                    Write-Verbose "Processing $($Row -split '\|')"
                                    foreach ($Value in $Row -split '\|') {
                                        if ([String]$ColumnList -notmatch "\|") {
                                            Write-Verbose "Single Header found"
                                            $Header = $ColumnList
                                        } else {
                                            $Header =  $($($ColumnList -split "\|")[$ColCounter])
                                        }
                                        if ($Value -eq "- Null -") {
                                            $Value = " "
                                        }
                                        Write-Verbose "Counter: $ColCounter | PropertyName: $Header | Value: $Value"
                                        $ResObj | Add-Member -MemberType NoteProperty -Name $Header.Trim() -Value $([String]$Value).Trim()
                                        $ColCounter++
                                    }
                                    $ResObj | Add-Member -MemberType NoteProperty -Name 'ErrorMsg' -Value " "
                                    Write-Output $ResObj
                                    $Counter++
                                }
                            }
                        }
                    } # Output type
                }
            }
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{
        Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Finished the runs, cleaning up..."
        if($PSCmdlet.ParameterSetName -eq 'BySQLFile') {
            Remove-Item -Path $toExecute
        }
        Write-Progress -Activity "Oracle DB Query Run" -CurrentOperation "Thanks for using this script."
    }
}

function Remove-OracleSchema {
    [CmdletBinding(
        SupportsShouldProcess=$true)]
    [Alias("oradrop")]
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
        foreach ($Item in $SchemaObjects | ? { $_.ObjectType -eq 'PACKAGE' }) {
            $Type = $Item | Select -ExpandProperty ObjectType
            $Name = $Item | Select -ExpandProperty ObjectName
            $DropThis = "DROP $Type $Name;"
            $DropperQuery += "$DropThis`n"
        }

        foreach ($Item in $SchemaObjects | ? { $_.ObjectType -eq 'PROCEDURE' }) {
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
        foreach ($Item in $SchemaObjects | ? { $_.ObjectType -eq 'SEQUENCE' }) {
            $Type = $Item | Select -ExpandProperty ObjectType
            $Name = $Item | Select -ExpandProperty ObjectName
            $DropThis = "DROP $Type $Name;"
            $DropperQuery += "$DropThis`n"
        }
        foreach ($Item in $SchemaObjects | ? { $_.ObjectType -eq 'LOB' }) {
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
        $DropperQuery += "PURGE DBA_RECYCLEBIN;"
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
}

function Test-OracleHealth {
    [CmdletBinding()]
    [Alias("orahealth")]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB,
        # Username if required
        [Alias("u")]
        [String]$DBUser,
        # Password if required
        [String]$DBPass,
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
                $SecurePass = Read-Host -AsSecureString -Prompt "Please enter the password for User $DBUser"
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
                $DBPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            Write-Progress -Activity "Checking $DBName Health Status" -CurrentOperation "Pinging $DBName databases" -PercentComplete 0
            foreach ($DBName in $TargetDB) {
                Write-Progress -Activity "Checking $DBName Health Status" -CurrentOperation "Pinging $DBName databases" -PercentComplete 0
                if (Ping-OracleDB -TargetDB $DBName) {
                    Write-Progress -Activity "Checking $DBName Health Status" -CurrentOperation "Querying $DBName..." -PercentComplete 25
                    $GeneralInfoQuery = @'
SELECT 'DATABASE NAME' AS "AttributeName", db_unique_name AS "Value" FROM v$database
UNION ALL
SELECT 'NUMBER OF INSTANCES', TO_CHAR(MAX(inst_id)) FROM gv$instance
UNION ALL
SELECT 'DATABASE HOSTS', listagg(host_name,', ') WITHIN GROUP(ORDER BY inst_id) FROM gv$instance
UNION ALL
SELECT 'DATA DISKGROUP/PATH', value FROM v$spparameter WHERE upper(NAME)='DB_CREATE_FILE_DEST'
UNION ALL
SELECT 'RECOVERY DISKGROUP/PATH', value FROM v$spparameter WHERE upper(NAME)='DB_RECOVERY_FILE_DEST';
'@
                    if ($DBUser) {
                        Use-OracleDB -TargetDB $DBName -SQLQuery $GeneralInfoQuery -DBUser $DBUser -DBPass $DBPass
                    } else {
                        Use-OracleDB -TargetDB $DBName -SQLQuery $GeneralInfoQuery
                    }
                }
            }
            Write-Progress -Activity "Gathering $DBName Services" -CurrentOperation "$DBName done" -PercentComplete 85
        } else { Write-Error "Oracle Environment not set!!!" -Category NotSpecified -RecommendedAction "Set your `$env:ORACLE_HOME variable with the path to your Oracle Client or Software Home" }
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
