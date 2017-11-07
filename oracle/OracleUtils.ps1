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
   Check that the ORACLE_HOME is set. Returns $true if it is or $false otherwise.
.DESCRIPTION
   This functions returns $true if the ORACLE_HOME variable is set
.EXAMPLE
   Import-Module \Path\to\OracleUtils.psm1
.NOTES
   General notes
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

# TNS Ping Oracle Databases
function Ping-OracleDB
{
    [CmdletBinding()]
    [Alias("podb")]
    [OutputType([boolean])]
    Param (
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
        # It can check several databases at once
        [String[]]$TargetDatabase
    )
    Process {
        if (Check-OracleEnv) {
            $pinged=$(tnsping $TargetDatabase)
            $pinged[-1].contains('OK')
        }
    }
}

<#
.Synopsis
    This will run a SQL script on one or more Oracle databases.
#>
# Connect to database and run a script
function Run-OracleScript() {
    [CmdletBinding()]
    [Alias("rsql")]
    Param (
        # It can run the script on several databases at once
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            HelpMessage="One or more Oracle Database names")]
        [String[]]$TargetDatabase,
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
            foreach ($db in $TargetDatabase) {
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
