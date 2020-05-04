
Install-WindowsFeature -Name "AD-Domain-Services" -IncludeAllSubFeature
Install-WindowsFeature -Name "RSAT-AD-Tools" -IncludeAllSubFeature
Install-WindowsFeature -Name "RDS-Connection-Broker"
Install-WindowsFeature -Name "RDS-Gateway"
Install-WindowsFeature -Name "RDS-Licensing"
Install-WindowsFeature -Name "RDS-RD-Server"
Install-WindowsFeature -Name "RDS-Web-Access"
restart-computer

#
# Windows PowerShell script for AD DS Deployment
#

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
-Force:$true


[string]$host="$env:computername.rds-9000.com"
New-RDSessionDeployment -ConnectionBroker $host -SessionHost $host -WebAccessServer $host
