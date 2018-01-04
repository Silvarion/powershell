Param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Type1","Type2","Type3","Type4","Type5")]
    [String[]]$Type
)
cls
foreach ($t in $Type) {
    
    Start-Job -Name "${t}_JOB" -ArgumentList $g -ScriptBlock { 
    Set-Location '<YOUR CUSTOM LOCATION>'
    #Import required modules
    Import-Module 'path\to\some\module'
    <PATH_TO_YOUR_SCRIPT>.ps1 -Type $args[0] 
    }
}
$JobTimer = @{}
$JobTimeOut = [timespan]::FromSeconds(180)
while ($(Get-Job -Name "*OID").ChildJobs.Count -gt 0) {
    foreach ($JobInProgress in Get-Job "*OID" | ? { $_.State -eq 'Running' } ) {
        $JobOutput = Receive-Job $JobInProgress
        if ($([String]$JobOutput).Length -eq 0) {
            if ($JobTimer[$JobInProgress]) {
                if (($(Get-Date) - $JobTimer[$JobInProgress]) -gt $JobTimeOut) {
                    Write-Output "[$(Get-Date)] Job $($JobInProgress.Name) hung... Restarting!"
                    Stop-Job -Name "$($JobInProgress.Name)"
                    Remove-Job -Name "$($JobInProgress.Name)"
                    Start-Job -Name "$($JobInProgress.Name)" -ScriptBlock {
                        Set-Location '<YOUR CUSTOM LOCATION>'
                        #Import required modules
                        Import-Module 'path\to\some\module'
                        <PATH_TO_YOUR_SCRIPT>.ps1 -Type $args[0] 
                    } -ArgumentList $($JobInProgress.Name -split "_")[0]
                } else {
                    if (($(Get-Date) - $JobTimer[$JobInProgress]) -in @(60,120) ) {
                        Write-Warning "[$(Get-Date)] Job $($JobInProgress.Name) can be hung..."
                    }
                }
            } else {
                $JobTimer[$JobInProgress] = ($(Get-Date))
            }
        } else {
            $JobTimer[$JobInProgress] = ($(Get-Date))
            Write-Output $JobOutput
        }
    }
    foreach ($JobDone in Get-Job "*OID" | ? { $_.State -in @('Completed','Failed') } ) {
        Write-Output $(Receive-Job $JobDone)
        Remove-Job $JobDone
    }
    Start-Sleep 3
}
