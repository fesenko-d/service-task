
Install-WindowsFeature -Name "AD-Domain-Services" -IncludeAllSubFeature
Install-WindowsFeature -Name "RSAT-AD-Tools" -IncludeAllSubFeature

#
# AD DS Deployment
#

$Secure_String = ConvertTo-SecureString "ns_g1l0h" -AsPlainText -Force

Import-Module ADDSDeployment
Install-ADDSForest `
-CreateDnsDelegation:$false `
-DatabasePath "C:\Windows\NTDS" `
-DomainMode "WinThreshold" `
-DomainName "rds-9000.com" `
-DomainNetbiosName "RDS-9000" `
-ForestMode "WinThreshold" `
-InstallDns:$true `
-LogPath "C:\Windows\NTDS" `
-NoRebootOnCompletion:$false `
-SysvolPath "C:\Windows\SYSVOL" `
-SafeModeAdministratorPassword $Secure_String `
-Force:$true


#
# RDS Deployment
#

Install-WindowsFeature -Name "RDS-Connection-Broker"
Install-WindowsFeature -Name "RDS-Gateway"
Install-WindowsFeature -Name "RDS-Licensing"
Install-WindowsFeature -Name "RDS-RD-Server"
Install-WindowsFeature -Name "RDS-Web-Access"
restart-computer

[string]$serverName="$env:computername.rds-9000.com"

New-RDSessionDeployment -ConnectionBroker $serverName -SessionHost $serverName -WebAccessServer $serverName
Add-RDServer -Server $serverName -Role RDS-LICENSING -ConnectionBroker $serverName
Add-RDServer -Server $serverName -Role RDS-LICENSING -ConnectionBroker $serverName -GatewayExternalFqdn $serverName
restart-computer
