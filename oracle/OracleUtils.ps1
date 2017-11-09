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


<#
.Synopsis
   Checks that the ORACLE_HOME is set. Returns $true if it is or $false otherwise.
.DESCRIPTION
   This functions returns $true if the ORACLE_HOME variable is set or $false otherwise
.EXAMPLE
if (Check-OracleEnv) {
    <Some commands>
}
.ROLE
   This cmdlet is mean to be used by Oracle DBAs
.FUNCTIONALITY
#>
function Check-OracleEnv {
    [CmdletBinding()]
    [Alias("coe")]
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
   This cmdlet is mean to be used by Oracle DBAs
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
        if (Check-OracleEnv) {
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
function Run-OracleScript {
    [CmdletBinding(
        SupportsShouldProcess=$true)]
    [Alias("rsql")]
    Param (
        # It can run the script on several databases at once
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,
        # It can run several scripts at once
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            HelpMessage="Path to SQL file to run on the databases")]
        [String[]]$SQLScript,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Check-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (podb($db)) {
                    Write-Output "Database $db is reachable"
                    &"sqlplus" "-S" "/@$db" "@$SQLScript"
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
        if (Check-OracleEnv) {
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
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Check-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (podb($db)) {
					Write-Debug "Database pinged successfully"
                    # Using here-string to pipe the SQL query to SQL*Plus
                    @'
SET HEADING OFF
SET PAGESIZE 0
SELECT instance_name from gv$instance ORDER BY 1;
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
        if (Check-OracleEnv) {
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
        if (Check-OracleEnv) {
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
        if (Check-OracleEnv) {
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
        if (Check-OracleEnv) {
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
define  report_name  = 'addm_${Instance}_${StartSnapshot}_${EndSnapshot}_report.html'
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
        if (Check-OracleEnv) {
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
        if (Check-OracleEnv) {
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
function Get-OraclePerfReport {
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
        Write-Warning "CURRENTLY UNDER DEVELOPMENT!"
        if (Check-OracleEnv) {
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
                if ($AWR) {
                    Write-Output "Generating AWR Report Set"
                    $ORAOutput = Get-OracleAWRReport -TargetDB $TargetDB -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                    Write-Output "Getting Oracle database instances"
                    $Instances = Get-OracleInstances -TargetDB $TargetDB
                    foreach ($Instance in $Instances) {
                        if ($Instance.Length -gt 0) {
                            Write-Verbose "Launching AWR Instance #$InstNumber Report for $Instance"
                            $ORAOutput = Get-OracleAWRInstanceReport -TargetDB $TargetDB -Instance $Instance -DBID $DBID -StartSnapshot $StartSnapshot -EndSnapshot $EndSnapshot
                        }
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
                }
                if ($Compress) {
                    Write-Output "Compressing AWR reports set"
                    zip -9m AWR_${TargetDB}_${StartSnapshot}_${EndSnapshot}_reports.zip awr*.htm*
                    Write-Output "Compressing ADDM reports set"
                    zip -9m ADDM_${TargetDB}_${StartSnapshot}_${EndSnapshot}_reports.zip addm*.htm*
                }
                if ($SendMail) {
                $EmailAddress = "some_email@some_domain.com"
                    if ($Compress) {
                        $ReportFiles = Get-ChildItem -Path . -Name *reports.zip
                    } else {
                        $ReportFiles = Get-ChildItem -Path . -Name *report.*
                    }
                Send-MailMessage -Attachments $ReportFiles -From $env:USERNAME -To $EmailAddress -Subject "Reports Test" -Body "Some message"
                }
            }
        }
    }
    End{}
}
