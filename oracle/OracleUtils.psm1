<#
.Synopsis
   Oracle Utilities for using within PowerShell
.DESCRIPTION
   This Module has functions to ping Oracle Databases, query them and get performance reports  automatically.
.EXAMPLE
   Import-Module \Path\to\OracleUtils.psm1
.NOTES
   General notes
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
.FUNCTIONALITY
#>


$OracleHtmlHeader = @'
<html>
<head>
<style type='text/css'>
body {font:normal 10pt Arial,Helvetica,sans-serif; color:black; background:White;}
p {font:bold 10pt Arial,Helvetica,sans-serif; color:black; background:White;}
    table,tr,td {font:bold 10pt Arial,Helvetica,sans-serif; color:Black; background:#f7f7e7;
    padding:0px 0px 0px 0px; margin:0px 0px 0px 0px;} th {font:bold 10pt Arial,Helvetica,sans-serif;
    color:blue; background:#cccc99; padding:0px 0px 0px 0px;} h1 {font:16pt Arial,Helvetica,Geneva,sans-serif;
    color:#336699; background-color:White; border-bottom:1px solid #cccc99; margin-top:0pt; margin-bottom:0pt;
    padding:0px 0px 0px 0px;} h2 {font:bold 10pt Arial,Helvetica,Geneva,sans-serif; color:#336699;
    background-color:White; margin-top:4pt; margin-bottom:0pt;} a {font:9pt Arial,Helvetica,sans-serif;
    color:#663300; background:#ffffff; margin-top:0pt; margin-bottom:0pt;
    vertical-align:top;}
</style>
</head>
<body>
'@

$OracleHtmlTail = "</body></html>"

$OracleGeneralHealthCheck = @'
SET linesize 32000
SET pagesize 40000
SET trimspool ON
SET trimout ON
SET wrap OFF
SET FEEDBACK OFF
SET MARKUP HTML ON

COLUMN title format a100
COLUMN NAME format a30

SET heading OFF
SELECT '========== DATABASE INFORMATION ==========' title FROM dual;
SELECT 'DATABASE NAME: '||db_unique_name FROM v$database;
SELECT 'NUMBER OF INSTANCES: '||MAX(inst_id) FROM gv$instance;
SELECT 'DATABASE HOSTS: '||listagg(host_name,', ') WITHIN GROUP(ORDER BY inst_id) FROM gv$instance;
SELECT 'DATA DISKGROUP/PATH: '||VALUE FROM v$spparameter WHERE upper(NAME)='DB_CREATE_FILE_DEST';
SELECT 'RECOVERY DISKGROUP/PATH: '||VALUE FROM v$spparameter WHERE upper(NAME)='DB_RECOVERY_FILE_DEST';
PROMPT
SET heading OFF
SELECT '========== SGA INFO ==========' title FROM dual;
SET heading ON
COLUMN gb_per_instance FORMAT a30
SELECT NAME, listagg(round(bytes/1024/1024/1024,2),', ') WITHIN GROUP(ORDER BY inst_id) gb_per_instance 
FROM gv$sgainfo 
WHERE upper(NAME) LIKE '%SIZE' 
AND upper(NAME) NOT LIKE 'GRANULE%' 
GROUP BY NAME 
ORDER BY 2 DESC;
PROMPT
SET heading OFF
SELECT '========== CPU INFO ==========' title FROM dual;
SELECT 'Number of cores/CPUs assigned to instance '||inst_id||': '||VALUE
FROM gv$spparameter
WHERE UPPER(name)='CPU_COUNT'
ORDER BY inst_id;
SET heading ON
COLUMN metric_name FORMAT a40
COLUMN value_per_instance FORMAT a40
COLUMN metric_unit FORMAT a30
SELECT metric_name, listagg(ROUND(VALUE,4),' | ') WITHIN GROUP (ORDER BY inst_id) value_per_instance, metric_unit
FROM gv$sysmetric
WHERE metric_name LIKE '%CPU%' 
GROUP BY metric_name, metric_unit
ORDER BY 2,1;
PROMPT
SET heading OFF
SELECT '========== ASM OPERATIONS ==========' title FROM dual;
SET heading ON
SELECT ag.NAME, ao.operation, ao.state, ao.est_minutes FROM v$asm_operation ao, v$asm_diskgroup ag ORDER BY ao.est_minutes;
PROMPT
SET heading OFF
SELECT '========== ASM DISKGROUP STATUS ==========' title FROM dual;
SET heading ON
COLUMN "TOTAL GB" format 999,999.99
COLUMN "FREE GB" format 999,999.99
COLUMN "USABLE GB" format 999,999.99
COLUMN "FREE %" format 99.99
SELECT NAME
	, offline_disks
	, state
	, round(total_mb/1024,2) "TOTAL GB"
	, round(free_mb/1024,2) "FREE GB"
	, round(usable_file_mb/1024,2) "USABLE GB"
	, round(usable_file_mb*100/total_mb,2) "FREE %" 
FROM v$asm_diskgroup
WHERE NAME IN (
	SELECT substr(VALUE,2,LENGTH(VALUE))
	FROM v$spparameter
	WHERE upper(NAME) LIKE ('DB_%_FILE_DEST')
) ORDER BY 1;
PROMPT
SET heading OFF
SELECT '========== FRA STORAGE ==========' title FROM dual;
SET heading ON
col name format a32
col QUOTA_GB for 999,999,999
col USED_GB for 999,999,999
col PCT_USED for 999
SELECT name
, ceil( space_limit / 1024 / 1024 / 1024) QUOTA_GB
, ceil( space_used  / 1024 / 1024 / 1024) USED_GB
, decode( nvl( space_used, 0), 0, 0
, ceil ( ( space_used / space_limit) * 100) ) PCT_USED
FROM v$recovery_file_dest
ORDER BY NAME;
PROMPT
SET heading OFF
SELECT '========== SERVICES ==========' title FROM dual;
SET heading ON
COLUMN INSTANCES format a30
SELECT NAME, listagg(inst_id,',') WITHIN GROUP (ORDER BY inst_id) INSTANCES
FROM gv$active_services
WHERE NAME NOT LIKE 'SYS%'
GROUP BY NAME
ORDER BY 1;
PROMPT
SET heading OFF
SELECT '========== BLOCKING LOCKS ==========' title FROM dual;
SET heading ON
COLUMN "BLOCKER COUNT" format 999999999
SELECT "BLOCKER COUNT" FROM(
SELECT count(
   blocker.SID
) "BLOCKER COUNT"
FROM (SELECT *
      FROM gv$lock
      WHERE BLOCK != 0
      AND TYPE = 'TX') blocker
,    gv$lock            waiting
WHERE waiting.TYPE='TX' 
AND waiting.BLOCK = 0
AND waiting.id1 = blocker.id1
);
PROMPT
SET heading OFF
SELECT '========== BLOCKING SESSIONS ==========' title FROM dual;
SET heading ON
COLUMN username format a16
SELECT
   sess.username
,  sess.osuser
,  blocker.SID blocker_sid
,  sess.sql_id
,  waiting.request
,  count(waiting.SID) waiting_sid
,  MAX(trunc(waiting.ctime/60)) max_min_waiting
FROM (SELECT *
      FROM gv$lock
      WHERE BLOCK != 0
      AND TYPE = 'TX') blocker
,    gv$lock            waiting
, gv$session sess
WHERE waiting.TYPE='TX' 
AND waiting.BLOCK = 0
AND waiting.id1 = blocker.id1
AND sess.SID=blocker.SID
GROUP BY sess.username, sess.osuser, blocker.SID, sess.sql_id, waiting.request;

SET heading OFF
SELECT '========== BLOCKING SQLS ==========' title FROM dual;
SET heading ON
SELECT DISTINCT sql_id, sql_text
FROM gv$sql
WHERE sql_id IN (
	SELECT
	   DISTINCT sess.sql_id
	FROM (SELECT *
		  FROM gv$lock
		  WHERE BLOCK != 0
		  AND TYPE = 'TX') blocker
	,    gv$lock            waiting
	, gv$session sess
	WHERE waiting.TYPE='TX' 
	AND waiting.BLOCK = 0
	AND waiting.id1 = blocker.id1
	AND sess.SID=blocker.SID
);
PROMPT
SET heading OFF
SELECT '========== LONG DB OPERATIONS ==========' title FROM dual;
SET heading ON
SELECT s.username, l.SID, l.serial#, l.opname, l.totalwork, l.sofar, round(l.sofar*100/l.totalwork) percent_complete
FROM gv$session_longops l, gv$session s
WHERE totalwork > 0
AND sofar*100/totalwork < 100
AND l.SID = s.SID
AND l.serial# = s.serial#;
PROMPT
SET heading OFF
SELECT '========== PENDING DISTRIBUTED TRANSACTIONS ==========' title FROM dual;
SET heading ON
SELECT local_tran_id, state, tran_comment,host,db_user,advice
FROM dba_2pc_pending
WHERE state='PREPARED';
PROMPT
SET heading OFF
SELECT '========== PENDING DISTRIBUTED TRANSACTIONS DEATAILS ==========' title FROM dual;
SET heading ON
with tran_id as (
	select local_tran_id
	from dba_2pc_pending
	where state='prepared'
)
select a.sql_text, s.osuser, s.username
from v$transaction t, v$session s, v$sqlarea a, tran_id i
where s.taddr = t.addr
	and a.address = s.prev_sql_addr
	and t.xidusn = substr(i.local_tran_id,1,instr(i.local_tran_id,'.')-1)
	and t.xidslot = substr(i.local_tran_id,(instr(i.local_tran_id,'.')+1),((instr(i.local_tran_id,'.',(instr(i.local_tran_id,'.')+1)))-(instr(i.local_tran_id,'.')+1)))
	and t.xidsqn = substr(i.local_tran_id,(instr(i.local_tran_id,'.',(instr(i.local_tran_id,'.')+1)))+1,(nvl(nullif(instr(i.local_tran_id,'.',(instr(i.local_tran_id,'.',(instr(i.local_tran_id,'.')+1)))+1),0),length(i.local_tran_id))));
PROMPT
SET heading OFF
SELECT '========== APP/USER SESSIONS ==========' title FROM dual;
COLUMN "COUNT" format 9999999999999
COLUMN machine format a30
SET heading ON
break ON status
WITH list_view AS (
	SELECT status, username, osuser, machine, service_name, inst_id, count(1) session_count
	FROM gv$session
	WHERE status='ACTIVE'
	GROUP BY  inst_id, status, username, osuser, machine, service_name
	UNION ALL
	SELECT status, username, osuser, machine, service_name, inst_id, count(1) session_count
	FROM gv$session
	WHERE status='INACTIVE'
	GROUP BY inst_id, status, username, osuser, machine, service_name
) 
SELECT status, username, osuser, machine, service_name, listagg('INST: '||inst_id||', COUNT: '||session_count,' | ') WITHIN GROUP (ORDER BY inst_id) "COUNT"
FROM list_view
WHERE machine NOT IN (
	SELECT host_name
	FROM gv$instance
)
GROUP BY status, username, osuser, machine , service_name
ORDER BY 1,3,2,4;
PROMPT
SET heading OFF
SELECT '========== INTERNAL SESSIONS COUNT ==========' title FROM dual;
SET heading ON
SELECT 'ACTIVE SESSIONS' "SESSIONS", count(1) "COUNT"
FROM gv$session
WHERE status='ACTIVE'
AND username IN ('SYS','SYSTEM','DBSNMP')
UNION ALL
SELECT 'INACTIVE SESSIONS', count(1) "COUNT"
FROM gv$session
WHERE status='INACTIVE'
AND username IN ('SYS','SYSTEM','DBSNMP');
PROMPT
SET heading OFF
SELECT '========== OUTDATED STATS OBJECTS ==========' title FROM dual;
SET heading ON
COLUMN outdated_stats_objects FORMAT 999
SELECT owner, count(table_name) outdated_stats_objects
FROM dba_tables
WHERE last_analyzed < SYSDATE - 7
GROUP BY owner
ORDER BY 1;
'@

<#
.Synopsis
   Checks that the ORACLE_HOME is set. Returns $true if it is or $false otherwise.
.DESCRIPTION
   This functions returns $true if the ORACLE_HOME variable is set or $false otherwise
.EXAMPLE
if (Test-OracleEnv) {
    <Some commands>
}
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
.FUNCTIONALITY
#>
function Test-OracleEnv {
    [CmdletBinding()]
    [Alias("toe")]
    [OutputType([boolean])]
    Param()
    Process {
        if ($env:ORACLE_HOME.Length -gt 0) {
            if ($(Get-ChildItem -Path "$env:ORACLE_HOME/bin" -Filter "sqlplus.exe").Exists) {
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
    if (Ping-OracleDB -TargetDB <DB NAME>) {
        <Some commands>
    }
.ROLE
   This cmdlet is mean to be used by Oracle 
.FUNCTIONALITY
#>
function Ping-OracleDB
{
    [CmdletBinding()]
    [Alias("podb")]
    [OutputType([boolean])]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB
    )
    Process {
        if (Test-OracleEnv) {
            $pinged=$(tnsping $TargetDB)
            $pinged[-1].contains('OK')
        }
    }
}

<#
.Synopsis
    This will run a SQL script on one or more Oracle databases by leveraging SQL*Plus
.DESCRIPTION
    This function runs a SQL script on a Oracle Database and returns the output from the script
.EXAMPLE
    Run-OracleScript -TargetDB <DB NAME> -SQLScript <Path/to/file.sql> [-ErrorLog]
.ROLE
    This cmdlet is mean to be used by Oracle DBAs
#>
function Query-OracleDB {
    [CmdletBinding(
        DefaultParameterSetName='BySQLQuery',
        SupportsShouldProcess=$true)]
    [Alias("qodb")]
    Param (
        # It can run the script on several databases at once
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,
        # It can run several scripts at once
        [Parameter(
            ValueFromPipeline=$true,
            ParameterSetName='BySQLFile',
            HelpMessage="Path to SQL file to run on the databases")]
        [String[]]$SQLScript,

        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ParameterSetName='BySQLQuery',
            HelpMessage="SQL query to run on the databases")]
        [String[]]$SQLQuery,

        [Parameter(
            HelpMessage="Dump results to an output file")]
        [Switch]$Dump,
        [Parameter(
            HelpMessage="Dump results to an output file")]
        [String]$DumpFile,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (podb($db)) {
                    Write-Verbose "Database $db is reachable"
                    
                    if ($PSCmdlet.ParameterSetName -eq 'BySQLFile') {
                        $Output = &"sqlplus" "-S" "/@$db" "@$SQLScript"
                    } elseif ($PSCmdlet.ParameterSetName -eq 'BySQLQuery') {
                        $Output = $SQLQuery | &"sqlplus" "-S" "/@$db"
                    } else {
                        Write-Warning "Please use either -SQLFile or -SQLQuery to provide what you need to run on the database"
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
                    Write-Error "Database $db not reachable"
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
    Query an Oracle database to get the global name
.DESCRIPTION
    This function returns the global name of the database
.EXAMPLE
    Get-OracleGlobalName -TargetDB <DB NAME> [-ErrorLog]
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OracleGlobalName {
    [CmdletBinding()]
    [Alias("gogn")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (podb($db)) {
					Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    @'
SET HEADING OFF
SET PAGESIZE 0
SELECT global_name from global_name;
exit
'@ | &"sqlplus" "-S" "/@$db"
                } else {
                    Write-Error "Database $db not reachable" >> $ErrorLogFile
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
    [Alias("goin")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
			Write-Debug "Database pinged successfully"
            # Using here-string to pipe the SQL query to SQL*Plus
            @'
SET HEADING OFF
SET PAGESIZE 0
SELECT instance_name from gv$instance ORDER BY 1;
exit
'@ | &"sqlplus" "-S" "/@$TargetDB"
        } else {
            Write-Error "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{}
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
    [Alias("oragdbid")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (podb($db)) {
					Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    @'
SET HEADING OFF
SET PAGESIZE 0
SELECT dbid FROM v$database;
exit
'@ | &"sqlplus" "-S" "/@$db"
                } else {
                    Write-Error "Database $db not reachable" | Out-File $ErrorLogFile
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
    [Alias("gos")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String]$TargetDB,

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
    [Alias("gost")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,

        # This can be a list of databases
        [Parameter(Mandatory=$true,
            HelpMessage="Oracle Database ID")]
        [bigint]$DBID,

        # This is the snapshot to use to query the time
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [bigint]$Snapshot,

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
    [Alias("goaddmi")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,

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
    
.ROLE
    
#>
function Get-OracleAWRReport {
    [CmdletBinding()]
    [Alias("goawrg")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,

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
			Write-Verbose "Launching AWR Global Report"
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
    
.ROLE
    
#>
function Get-OracleAWRInstanceReport {
    [CmdletBinding()]
    [Alias("goawri")]
    Param (
        # Target Database
        [Parameter(Mandatory=$true,
            HelpMessage="Target Oracle Database name")]
        [String]$TargetDB,

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
    .ROLE
       This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OraclePerfReports {
    [CmdletBinding(
    SupportsShouldProcess=$true)]
    [Alias("gopr")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="Target Oracle Database names")]
        [String]$TargetDB,
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
        Write-Output "PS Oracle Performance Reports Generator"
        if (Test-OracleEnv) {
            if (Ping-OracleDB -TargetDB $TargetDB) {
				Write-Verbose "Database pinged successfully"
                Write-Output "Gathering DBID"
                [String]$TempStr = Get-OracleDBID -TargetDB $TargetDB
                [bigint]$DBID = $TempStr.Trim(' ')
                Write-Verbose "DBID for $TargetDB : $DBID"
                Write-Output "Getting Snapshot numbers"
                [String]$StrSnapshot = Get-OracleSnapshot -TargetDB $TargetDB -TimeStamp $StartTime.AddSeconds(59).ToString("yyyy-MM-dd HH:mm:ss") -Mark start
                [bigint]$StartSnapshot = [bigint]$StrSnapshot.trim(' ')
                [String]$StrSnapshot = Get-OracleSnapshot -TargetDB $TargetDB -TimeStamp $EndTime.ToString("yyyy-MM-dd HH:mm:ss") -Mark end
                [bigint]$EndSnapshot = [bigint]$StrSnapshot.trim(' ')
				Write-Verbose "Starting Snapshot: $StartSnapshot | Ending Snapshot: $EndSnapshot"
                Write-Output "Getting Snapshot times"
                [String]$StartSnapTime = Get-OracleSnapshotTime -TargetDB $TargetDB -DBID $DBID -Snapshot $StartSnapshot -Mark start
                [String]$EndSnapTime = Get-OracleSnapshotTime -TargetDB $TargetDB -DBID $DBID -Snapshot $EndSnapshot -Mark end
                Write-Verbose "Starting Snapshot Time: $StartSnapTime | Ending Snapshot Time: $EndSnapTime"
                Write-Output "Getting Oracle database instances"
                $Instances = Get-OracleInstances -TargetDB $TargetDB
                if ($AWR) {
                    Write-Output "Generating AWR Report Set"
                    $ORAOutput = Get-OracleAWRReport -TargetDB $TargetDB -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                    foreach ($Instance in $Instances) {
                        if ($Instance.Length -gt 0) {
                            Write-Verbose "Launching AWR Instance #$InstNumber Report for $Instance"
                            $ORAOutput = Get-OracleAWRInstanceReport -TargetDB $TargetDB -Instance $Instance -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                        }
                    }
                    if ($Compress) {
                        Write-Output "Compressing AWR reports set"
                        zip -9m AWR_${TargetDB}_${StartSnapshot}_${EndSnapshot}_reports.zip awr*.htm*
                    }
                }
                if ($ADDM) {
                    Write-Output "Generating ADDM Report Set"
                    foreach ($Instance in $Instances) {
                        if ($Instance.Length -gt 0) {
                            Write-Verbose "Launching ADDM Instance #$InstNumber Report for $Instance"
                            $ORAOutput = Get-OracleADDMInstanceReport -TargetDB $TargetDB -Instance $Instance -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                        }
                    }
                    if ($Compress) {
                        Write-Output "Compressing ADDM reports set"
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
