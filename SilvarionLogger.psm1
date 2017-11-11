<#
.Synopsis
   simple formatted logger for PowerShell
.DESCRIPTION
   This module has a single function to Log information to the console in a formatted fashion
.EXAMPLE
   Import-Module \Path\to\SilvarionLogger.psm1
.NOTES
    This is one of my first modules for PowerShell, so any comments and suggestions are more than welcome. 
.FUNCTIONALITY
    This Module is mean to be used as a simple logger for the console.
#>

<#
.Synopsis
   Simple formatted logger for PowerShell
.DESCRIPTION
   This function is a centralized point for logging onto the console (or files)
.EXAMPLE
   Write-Logger -Info "Some Information message"
.EXAMPLE
   Write-Debug -Info "Some Debugging  message"
.NOTES
    -Debug turns on the debugging where the message is placed.
    -Info and -Notice use the Verbose stream and activate it on demmand
    -Error and -Critical options use the Error stream.
    -All other flags use the standard output.
.FUNCTIONALITY
    This Module is mean to be used as a simple logger for the console.
#>

function Write-Logger {
[CmdletBinding()]
Param(
    [Switch]$Debugging,
    [Switch]$Info,
    [Switch]$Notice,
    [Switch]$Warning,
    [Switch]$Error,
    [Switch]$Critical,
    [Switch]$Plain,
    [Switch]$Underlined,
    [Switch]$Blank,
    [Alias("msg")]
    [parameter(Mandatory=$true)]
    [String]$Message
)
    if (($Debugging) -or ($Error) -or ($Critical)) {
        $CallStack = Get-PSCallStack  | Where -NotIn -Property FunctionName  -Value '<ScriptBlock>','Write-Logger' | Select -Property FunctionName,Location -First 1
        [String]$Caller = $CallStack | Select -ExpandProperty FunctionName
        [String]$CallerLoc = $CallStack | Select -ExpandProperty Location
    }
    [datetime]$Timestamp = Get-Date
    [String]$StrTS = $Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
    if ($Debugging) {
        Write-Debug "          [$StrTS] [Caller: $Caller][Code: $CallerLoc] $Message" -debug -InformationAction SilentlyContinue -ErrorAction SilentlyContinue
    } elseif ($Info) {
        Write-Verbose "  [INFO][$StrTS] $Message" -Verbose
    } elseif ($Notice) {
        Write-Verbose "[NOTICE][$StrTS] $Message" -Verbose
    } elseif ($Warning) {
        Write-Warning "        [$StrTS] $Message"
    } elseif ($Error) {
        Write-Error "  [$StrTS] $Message" -TargetObject $Caller
    } elseif ($Critical) {
        Write-Error "  [$StrTS] $Message" -TargetObject $Caller -RecommendedAction "Review $CallerLoc"
    } elseif ($Plain) {
        Write-Output "$Message"
    } elseif ($Underlined) {
        $Line=""
        for ($i=0; $i -lt $Message.Length; $i++) {
            $Line +="-"
        }
        Write-Output "$Message"
        Write-Output "$Line"
    } elseif ($Blank) {
        Write-Output ""
    }
}
