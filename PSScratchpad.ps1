# Scratchpad


$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "silvarion@msn.com",$passwd

$MySession = Enter-PSSession -computername jasd-pavilion -credential $(Get-Credential -UserName "claudy.de.sousa@hotmail.com" -Message "Password to connect") -UseSSL

$MySession = Enter-PSSession -computername Hekka-Desktop -credential $(Get-Credential -UserName "claudy.de.sousa@hotmail.com" -Message "Password to connect") -UseSSL

Publish-Module -Name JS.OracleDatabase -NuGetApiKey 8464bc7a-4ea3-4964-a7ae-6c7ef5a46acb

Remove-Module -Name JS.OracleDatabase

Import-Module  -Name JS.OracleDatabase -Verbose

Get-Command -Module JS.OracleDatabase
