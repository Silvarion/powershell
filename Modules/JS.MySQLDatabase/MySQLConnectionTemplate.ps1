[System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")

[string]$MySQLUser = 'silvarion'
[string]$MySQLPass = '3lf0Dr0w#'
[string]$MySQLDB = 'mysql'
[string]$MySQLHost = '192.168.1.103'
[int]$MySQLPort = 3306

if (-not $MySQLPass) {
    $MySQLPass = Read-Host -Prompt "Please enter the password for user $MySQLUser" -AsSecureString
}

[string]$ConnectionString = "server="+$MySQLHost+";port=$MySQLPort;uid=" + $MySQLUser + ";pwd=" + $MySQLPass + ";database="+$MySQLDB

$MySQLConn = New-Object MySql.Data.MySqlClient.MySqlConnection($ConnectionString)
$Error.Clear()
try {
    $MySQLConn.Open();
} catch {
    Write-Error "Couldn't connect to the database"
} finally {
    if ($MySQLConn.Ping()) {
        $MySQLConn.Close();
    }
}
