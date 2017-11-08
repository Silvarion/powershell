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
                    Write-Output "Database $db is reachable"
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
                    Write-Output "Database $db is reachable"
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
    
.DESCRIPTION
    
.EXAMPLE
    
.ROLE
    
#>
function Get-OracleSnapshots {
    [CmdletBinding()]
    [Alias("gos")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,

        # This is the starting time for the permoance snapshot
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [datetime]$StartTime,
        # This is the ending time for the permoance snapshot
        [Parameter(Mandatory=$true,
            HelpMessage="Ending snapshot approximate time")]
        [datetime]$EndTime,

        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin{}
    Process{
        if (Check-OracleEnv) {
            foreach ($db in $TargetDB) {
                if (podb($db)) {
                    $StrStartStamp = $StartTime.AddSeconds(59).ToString("yyyy-MM-dd HH:mm:ss")
                    Write-Debug $StrStartStamp
                    $StrEndStamp = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
                    Write-Debug $StrEndStamp
                    # Using here-string to pipe the SQL query to SQL*Plus
                    @"
SET HEADING OFF
SET PAGESIZE 0
SELECT max(snap_id)
FROM dba_hist_snapshot
WHERE begin_interval_time <= TO_TIMESTAMP('$StrStartStamp','YYYY-MM-DD HH24:MI:SS')
AND end_interval_time > TO_TIMESTAMP('$StrStartStamp','YYYY-MM-DD HH24:MI:SS');
SELECT min(snap_id)
FROM dba_hist_snapshot
WHERE end_interval_time >= TO_TIMESTAMP('$StrEndStamp','YYYY-MM-DD HH24:MI:SS')
AND begin_interval_time < TO_TIMESTAMP('$StrEndStamp','YYYY-MM-DD HH24:MI:SS');"
EXIT
"@ | &"sqlplus" "-S" "/@$db"
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
    Generate AWR and/or ADDM report sets from an oracle database
.DESCRIPTION
    This function defines the required variables to generate automatically AWR and ADDM report sets.
.EXAMPLE
    Get-OraclePerfReports  [-AWR] [-ADDM] -TargetDB <DB NAME> [-ErrorLog]
    .ROLE
       This cmdlet is mean to be used by Oracle DBAs
#>
function Get-OraclePerfReport {
    [CmdletBinding()]
    [Alias("gopr")]
    Param (
        # This can be a list of databases
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDB,
        # This is the starting time for the permoance snapshot
        [Parameter(Mandatory=$true,
            HelpMessage="Starting snapshot approximate time")]
        [datetime]$StartTime,
        # This is the ending time for the permoance snapshot
        [Parameter(Mandatory=$true,
            HelpMessage="Ending snapshot approximate time")]
        [datetime]$EndTime,
        # Switch to turn on the error logging
        [Switch]$ErrorLog,
        [String]$ErrorLogFile = "$env:TEMP\OracleUtils_Errors_$PID.log"
    )
    Begin {}
    Process {
        Write-Warning "NOT IMPLEMENTED YET!"
        if (Check-OracleEnv) {
            if (Ping-OracleDB -TargetDB $TargetDB) {

                $StartTime.AddSeconds(59).ToString("yyyy-MM-dd HH:mm:ss")
                $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
    End{}
}
