<#
.Synopsis
   MySQL Utilities for using within PowerShell
.DESCRIPTION
   This Module has functions to use MySQL Databases, query them and get performance reports  automatically.
.EXAMPLE
   Import-Module \Path\to\MySQLUtils.psm1
.NOTES
   General notes
.ROLE
   This cmdlet is mean to be used by MySQL DBAs
.FUNCTIONALITY
#>


<#
.Synopsis
   Gets a list of MySQL Schemas
.DESCRIPTION
   Query the MySQL database indicated by port
.EXAMPLE
   Get-MySQLSchemas
.NOTES
   General notes
.ROLE
.FUNCTIONALITY
#>
function Get-MySQLSchemas {
    [CmdletBinding()]
    [Alias("toe")]
    [OutputType([boolean])]
    Param(
	[int]$Port,
    [String]$Hostname,
	[Parameter(Mandatory=$true)]
	[String]$Username
	)
	Process{
		if (-not $Port) {
			$Port = 3306
		}
        if (-not $Hostname) {
            $Hostname = "localhost"
        }
        #$Password = Read-Host -asSecureString "Please enter password for $Username"
        $Password = "3lf0Dr0w#"
        $Output = @"
show databases;
exit
"@ | & "mysql" "-h $Hostname" "-p $Port" "-u $Username" "-p $Password"
        $Output
	}
}

function Get-MySQLConnection {
    $UserName = 'username'
    $Password = 'password'
    $Database = 'MySQL-DB'
    $HostName = 'MySQL-Host'
    $ConnectionString = "server=" + $HostName + ";port=3306;uid=" + $UserName + ";pwd=" + $Password + ";database="+$Database

    Try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
        $Connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $Connection.ConnectionString = $ConnectionString
        $Connection.Open()

        $Command = New-Object MySql.Data.MySqlClient.MySqlCommand($Query, $Connection)
        $DataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($Command)
        $DataSet = New-Object System.Data.DataSet
        $RecordCount = $dataAdapter.Fill($dataSet, "data")
        $DataSet.Tables[0]
    } Catch {
        Write-Host "ERROR : Unable to run query : $query `n$Error[0]"
    } Finally {
        $Connection.Close()
    }
}
