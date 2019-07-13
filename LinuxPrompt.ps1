function Prompt {
    $CurrentLocation=$($(Get-Location).ToString() -split '/')[-1]
    "PS [$env:HOSTNAME] $CurrentLocation > "
}   
