$rebootCount=6

#
# Variables
#

$Secure_String = ConvertTo-SecureString "ns_g1l0h" -AsPlainText -Force
$DNSName = "rds-9000.local"
$NetbiosName = $DNSName.substring(0,$DNSName.lastindexof("."))
$NetbiosName = $NetbiosName.toupper()
$serverName="$env:computername.$DNSName"


Install-WindowsFeature -Name "AD-Domain-Services" -IncludeAllSubFeature
Install-WindowsFeature -Name "RSAT-AD-Tools" -IncludeAllSubFeature

#
# AD DS Deployment
#



Import-Module ADDSDeployment
Install-ADDSForest `
-CreateDnsDelegation:$false `
-DatabasePath "C:\Windows\NTDS" `
-DomainMode "WinThreshold" `
-DomainName $DNSName `
-DomainNetbiosName $NetbiosName `
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
Install-WindowsFeature -Name "RDS-RD-Server"
Install-WindowsFeature -Name "RDS-Web-Access"
restart-computer
New-RDSessionDeployment -ConnectionBroker $serverName -SessionHost $serverName -WebAccessServer $serverName

Install-WindowsFeature -Name "RDS-Licensing"
Add-RDServer -Server $serverName -Role RDS-LICENSING -ConnectionBroker $serverName

Install-WindowsFeature -Name "RDS-Gateway"
Add-RDServer -Server $serverName -Role RDS-LICENSING -ConnectionBroker $serverName -GatewayExternalFqdn $DNSName


# Creating self-signed certificate

new-selfsignedcertificate -certstorelocation cert:\localmachine\my -dnsname $DNSName -FriendlyName "rds-local"|Export-PfxCertificate -FilePath C:\rds-local.pfx -Password $Secure_String

# Certificate configuration

Set-RDCertificate -Role RDGateway `
                  -ImportPath C:\rds-local.pfx `
                  -Password $Secure_String `
                  -ConnectionBroker $serverName `
                  -Force

Set-RDCertificate -Role RDWebAccess `
                  -ImportPath C:\rds-local.pfx `
                  -Password $Secure_String `
                  -ConnectionBroker $serverName `
                  -Force

Set-RDCertificate -Role RDPublishing `
                  -ImportPath C:\rds-local.pfx `
                  -Password $Secure_String `
                  -ConnectionBroker $serverName `
                  -Force

Set-RDCertificate -Role RDRedirector `
                  -ImportPath C:\rds-local.pfx `
                  -Password $Secure_String `
                  -ConnectionBroker $serverName `
                  -Force

# Creating Collection

New-RDSessionCollection -CollectionName Desktop `
                        -CollectionDescription "Desktop Publication" `
                        -SessionHost $serverName `
                        -ConnectionBroker $serverName
