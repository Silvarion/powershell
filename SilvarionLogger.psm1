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
    --Notice use the Verbose stream
    -Error and -Critical options use the Error stream.
    -All other flags use the standard output.
.FUNCTIONALITY
    This Module is mean to be used as a simple logger for the console.
#>

function Write-Logger {
[CmdletBinding()]
Param(
    # Switch for debug info
    [Switch]$Debugging,
    # Switch for normal information
    [Switch]$Info,
    # Switch for added logging
    [Switch]$Notice,
    # Switch for Warnings
    [Switch]$Warning,
    # Switch for Errors
    [Switch]$Error,
    #Switch for Critical Errors, exits after showing the error
    [Switch]$Critical,
    # Switch for plain output
    [Switch]$Plain,
    # Switch for underlined output
    [Switch]$Underlined,
    # Switch for blank line
    [Switch]$Blank,
    # Message to be printed
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
        Write-Output "  [INFO][$StrTS] $Message"
    } elseif ($Notice) {
        Write-Verbose "[NOTICE][$StrTS] $Message"
    } elseif ($Warning) {
        Write-Warning "        [$StrTS] $Message"
    } elseif ($Error) {
        Write-Error "  [$StrTS] $Message" -TargetObject $Caller
    } elseif ($Critical) {
        Write-Error "  [CRITICAL][$StrTS] $Message" -TargetObject $Caller -RecommendedAction "Review $CallerLoc"
    } elseif ($Underlined) {
        $Line=""
        for ($i=0; $i -lt $Message.Length; $i++) {
            $Line +="-"
        }
        Write-Output "$Message"
        Write-Output "$Line"
    } elseif ($Blank) {
        Write-Output ""
    } else {
        Write-Output "$Message"
    }
}
