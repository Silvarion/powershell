﻿function Prompt {
$CurrentLocation=$($(Get-Location).ToString() -split '\\')[-1]
    "[$env:COMPUTERNAME] $CurrentLocation > "

}
