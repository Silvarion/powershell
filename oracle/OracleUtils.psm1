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

Class OracleDatabase {
    [String]$UniqueName
    [String]$GlobalName
    [boolean]$Cluster
    [String[]]$Instances
    [String[]]$Hosts
    [String[]]$ActiveServices

    OracleDatabase([String]$TargetDB) {
        $this.GlobalName = Get-OracleName -NameType global -TargetDB $TargetDB
        $this.UniqueName = Get-OracleName -NameType unique -TargetDB $TargetDB
        $this.Instances = Get-OracleInstances -TargetDB $TargetDB
        $this.Hosts = Get-OracleHosts -TargetDB $TargetDB
        $this.ActiveServices = Get-OracleServices -TargetDB $TargetDB
        if ($this.Hosts.Count -gt 1) {$this.Cluster=$true}
    }
}

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
    if (Ping-OracleDB -TargetDB orcl {
        Write-Logger -Notice -Message "Database pinged successfully"
        <Some commands>
    }
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBS to verify the reachability of a DB
#>
function Ping-OracleDB
{
    [CmdletBinding()]
    [Alias("oraping")]
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
   Returns the Active Services in an Oracle DB
.DESCRIPTION
   This functions the Active Services in an Oracle DB
.EXAMPLE
    Get-OracleServices -TargetDB myorcl
.FUNCTIONALITY
   This cmdlet is mean to be used by Oracle DBAs to retrieve a full list of active services in a DB
#>
function Get-OracleServices
{
    [CmdletBinding()]
    [Alias("orasrvc")]
    [OutputType([String[]])]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB
    )
    Process {
        if ((Test-OracleEnv) -and (Ping-OracleDB -TargetDB $TargetDB)) {
            foreach ($db in $TargetDB) {
                @'
SET PAGESIZE 0
SET HEADING OFF
COLUMN unique_name FORMAT a11
COLUMN global_name FORMAT a11
SELECT name 
FROM v$active_services 
WHERE name NOT LIKE ('SYS%') 
ORDER BY 1;
'@ | &"sqlplus" "-S" "/@$db"
            }
        }
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
    [Alias("orasrvc")]
    [OutputType([String[]])]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDB
    )
    Process {
        if ((Test-OracleEnv) -and (Ping-OracleDB -TargetDB $TargetDB)) {
            foreach ($db in $TargetDB) {
                @'
COLUMN name FORMAT a21
COLUMN status FORMAT a5

SELECT comp_name as name, status, modified
FROM dba_registry
WHERE comp_name LIKE '%Label%'
OR comp_name LIKE '%Vault%';
'@ | &"sqlplus" "-S" "/@$db"
            }
        }
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
        [String[]]$TargetDB,
        # Name Type
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [ValidateSet("global","unique","instance")]
        [String[]]$NameType,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Test-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (($db)) {
                    Switch ($NameType) {
                        "global" {$Query="SELECT global_name FROM global_name;"}
                        "unique" {$Query="SELECT db_unique_name FROM v`$database;"}
                        "instance" {$Query="SELECT instance_name FROM v`$instance;"}
                    }
					Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET LINESIZE 999
SET TRIM ON
SET WRAP OFF
SET HEADING OFF
$Query
exit
"@ | &"sqlplus" "-S" "/@$db"
                } else {
                    Write-Logger -Error -Message "Database $db not reachable" >> $ErrorLogFile
                }
            }
        } else {
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
SELECT host_name from gv$instance ORDER BY 1;
exit
'@ | &"sqlplus" "-S" "/@$TargetDB"
        } else {
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
    [Alias("oradbid")]
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
                if (Ping-OracleDB($db)) {
					Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    @'
SET HEADING OFF
SET PAGESIZE 0
SELECT dbid FROM v$database;
exit
'@ | &"sqlplus" "-S" "/@$db"
                } else {
                    Write-Logger -Error -Message "Database $db not reachable" | Out-File $ErrorLogFile
                }
            }
        } else {
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
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
            if (Ping-OracleDB -TargetDB $TargetDB) {
				Write-Logger -Notice -Message "Database pinged successfully"
                Write-Logger -Info -Message "Gathering DBID"
                [String]$TempStr = Get-OracleDBID -TargetDB $TargetDB
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
        [Switch]$ToPipeline,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{
        if (-not $ToPipeline) {Write-Logger -Underlined -Message "Welcome to the Use-OracleDB Function"}

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
        if ($ToPipeline) {
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
        if (-not $ToPipeline) {Write-Logger -Info -Message "Checking Oracle variables..."}
        if (Test-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (-not $ToPipeline) {Write-Logger -Info -Message "Trying to reach database $db..."}
                if (Ping-OracleDB -TargetDB $db) {
                    if (-not $ToPipeline) {Write-Logger -Notice -Message "Database $db is reachable"}
                    if (-not $ToPipeline) {Write-Logger -Info -Message "Checking Run-Mode..."}
                    if ($PSCmdlet.ParameterSetName -eq 'BySQLFile') {
                        if (-not $ToPipeline) {Write-Logger -Info -Message "Running on Script Mode"}
                        if (-not $ToPipeline) {Write-Logger -Info -Message "Checking script for settings and exit string"}
                        $tmpScript = Get-Content -Path $SQLScript
                        $toExecute = "$env:TEMP/runthis_$PID.sql"
                        "-- AUTOGENERATED TEMPORARY FILE" | Out-File -Encoding ASCII $toExecute
                        if ($HTML) {
                        Write-Logger -Notice -Message "Adding HTML output setting"
                        if (-not $ToPipeline) {"SET MARKUP HTML ON" | Out-File -Encoding ASCII $toExecute -Append}
                        }
                        foreach ($line in $tmpScript) {
                            "$line" | Out-File -Encoding ASCII $toExecute -Append
                        }
                        if(-not $tmpScript[-1].ToLower().Contains("exit")) {
                        if (-not $ToPipeline) {Write-Logger -Notice -Message "Adding EXIT command"}
                        "exit;" | Out-File -Encoding ASCII $toExecute -Append
                        }
                        if (-not $ToPipeline) {Write-Logger -Info -Message "Running script. Please wait..."}
                        $Output = &"sqlplus" "-S" "/@$db" "@$toExecute"
                    } elseif ($PSCmdlet.ParameterSetName -eq 'BySQLQuery') {
                        if (-not $ToPipeline) {Write-Logger -Info -Message "Running on Command Mode"}
                        if ($HTML) {
                            if (-not $ToPipeline) {Write-Logger -Notice -Message "Adding HTML setting to the command line"}
                            $SQLQuery = @"
SET MARKUP HTML ON
$SQLQuery
"@
                        }
                        if (-not $ToPipeline) {Write-Logger -Info -Message "Running query on the database..."}
                        $Output = @"
$PipelineSettings
$SQLQuery
exit;
"@ | &"sqlplus" "-S" "/@$db"

                    } else {
                        if (-not $ToPipeline) {Write-Logger -Error -Message "Please use either -SQLFile or -SQLQuery to provide what you need to run on the database"}
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
                    Write-Logger -Error -Message "Database $db not reachable"
                }
            }
        } else {
            Write-Logger -Error -Message "No Oracle Home detected, please install at least the Oracle Client and try again"
        }
    }
    End{
        if (-not $ToPipeline) {Write-Logger -Info -Message "Finished the runs, cleaning up..."}
        if($PSCmdlet.ParameterSetName -eq 'BySQLFile') {
            Remove-Item -Path $toExecute
        }
        if (-not $ToPipeline) {Write-Logger -Info -Message "Thanks for using this script."}
    }
}
