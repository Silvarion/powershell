# Get Formatted Sizing with % Used
Param(
    [Parameter(Mandatory = $true)]
    [String[]]$TargetDB,
    [Parameter(Mandatory = $true)]
    [ValidateSet("Full","Storage","Tablespace","Table")]
    [String]$SizeType,
    [Parameter(Mandatory = $true)]
    [ValidateSet("B","KB","MB","GB","TB","PB","EB","ZB")]
    [String]$Unit
)
foreach ($DBName in $TargetDB) {
    Get-OracleSize -TargetDB $DBName -SizeType $SizeType -Unit $Unit | Format-Table -AutoSize `
@{Name = "Database";Expression = { $_.DBName }; Alignment = "left"},
@{Name = "DiskGroup";Expression = { $_.DiskGroup }; Alignment = "left"},
@{Name = "UsedSpace";Expression = { $_.UsedGB }; Alignment = "Right"},
@{Name = "AllocatedSpace";Expression = { $_.AllocatedGB }; Alignment = "Right"},
@{Name = "MaxSpace";Expression = { "{0:N2}" -f $_.MaxGB }; Alignment = "Right"},
@{Name = "PercentUsed";Expression = { "{0:P2}" -f [float]$( $_.UsedGB / $_.MaxGB ) }; Alignment = "Right"}
}
