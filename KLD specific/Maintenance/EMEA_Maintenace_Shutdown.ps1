#Script to stop the service for EMEA maintenance. 

#Define values

#Define servers to run the commands
#$KOiServer = "UK1P1IINFMAD001.koi.local"
#$CCPServer = "UK1P1PINFMAD001.ccp.edp.local"

#Define maintenance servers
$WSMServers = "UK1P1IEDRWSM001.koi.local", "UK1P1IEDRWSM002.koi.local"
$SVCServers = "UK1P1PCC1SVZ001.ccp.edp.local"
$SMACServers = "B1P1VCC1SMZ0001.ccp.edp.local"
$CacheServer = "B1P1VLB1CHE0001.ccp.edp.local"
$HPC_HeadNode = "UK1P1IEDRHPH001.koi.local"

#load credential
$Cred_Koi = Import-Clixml -Path "C:\Users\rui.ferreira\Creds\KOI.xml"
$Cred_CCP = Import-Clixml -Path "C:\Users\rui.ferreira\Creds\CCP.xml"

#Create PSsession to target domain
#New-PSSession -ComputerName $KOiServer -Credential $Cred_Koi -Name "KOIServer"
#New-PSSession -ComputerName $CCPServer -Credential $Cred_CCP -Name "CCPServer"


#Creating PSsession for KOI servers
New-PSSession -ComputerName $WSMServers[0] -Credential $Cred_Koi -Name $WSMServers[0]
New-PSSession -ComputerName $WSMServers[1] -Credential $Cred_Koi -Name $WSMServers[1]

#Creating PSsession for CCP servers
New-PSSession -ComputerName $SVCServers -Credential $Cred_CCP -Name $SVCServers
New-PSSession -ComputerName $SMACServers -Credential $Cred_CCP -Name $SMACServers
New-PSSession -ComputerName $CacheServer -Credential $Cred_CCP -Name $CacheServer


#Stop Semetric Import Service and Request service on server 1##
enter-PSSession -Name $WSMServers[0]

Get-Service -Name "SemetricImport" | set-service -StartupType Disabled -Verbose
Get-Service -Name "Request Service" | set-service -StartupType Disabled -verbose

Stop-Service -Name "SemetricImport" -Verbose
Stop-Service -Name "Request Service" -Verbose

Exit-PSSession

#Stop Semetric Import Service and Request service on server 2##
Enter-PSSession -Name $WSMServers[1]

Get-Service -Name "Request Service" | set-service -StartupType Disabled -verbose
Stop-Service -Name "Request Service" -Verbose

Exit-PSSession


#Stop DdDuction, Dictionary & Release Services
Enter-PSSession -Name $SVCServers

Get-Service -Name "OIRelease" | set-service -StartupType Disabled -verbose
Get-Service -Name "OIDictionary" | set-service -StartupType Disabled -verbose
Get-Service -Name "OIDdDeduction" | set-service -StartupType Disabled -verbose
Get-Service -Name "Task Service" | set-service -StartupType Disabled -verbose

Stop-Service -Name "OIRelease" -Verbose
Stop-Service -Name "OIDictionary" -Verbose
Stop-Service -Name "OIDdDeduction" -Verbose
Stop-Service -Name "Task Service" -Verbose

Exit-PSSession


#Stop 3x SMAC v4 Services
Enter-PSSession -Name $SMACServers

Get-Service -Name "Storage Manager Remote Object Service v4.5.2.4" | set-service -StartupType Disabled -verbose
Get-Service -Name "Storage Manager Task Host Service v4.5.2.4" | set-service -StartupType Disabled -verbose
Get-Service -Name "Storage Manager Write Point Monitor Service v4.5.0.24" | set-service -StartupType Disabled -verbose

Stop-Service -Name "Storage Manager Remote Object Service v4.5.2.4" -Verbose
Stop-Service -Name "Storage Manager Task Host Service v4.5.2.4" -Verbose
Stop-Service -Name "Storage Manager Write Point Monitor Service v4.5.0.24" -Verbose

Exit-PSSession

#Stop Report Generation Service and DiskSpaceUpdate 
enter-PSSession -Name $WSMServers[0]

Get-Service -Name "Report Generation Service" | set-service -StartupType Disabled -Verbose
Get-Service -Name "DiskSpaceUpdateService" | set-service -StartupType Disabled -verbose

Stop-Service -Name "Report Generation Service" -Verbose
Stop-Service -Name "DiskSpaceUpdateService" -Verbose

Exit-PSSession

#second server
Enter-PSSession -Name $WSMServers[1]
Get-Service -Name "Report Generation Service" | set-service -StartupType Disabled -Verbose
Stop-Service -Name "Report Generation Service" -Verbose

Exit-PSSession

#Remove all PSSessions
Get-PSsession | Remove-PSSession 


#End message
Write-Host "Script Complete"
