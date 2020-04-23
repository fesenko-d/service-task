#!/bin/bash
#Creating unique key for passwordless authentification

#creating unique keyname adding current date
KeyName="MyKeyPair$(date "+%Y-%m-%d(%H:%M:%S)")"
#Creating a key pair and piping private key directly into a file
aws ec2 create-key-pair --key-name $KeyName --query 'KeyMaterial' --output text > $KeyName.pem
#seting the permissions of private key file so that only we can read it
chmod 400 $KeyName.pem
#Adding private key to the authentication agent
ssh-add -K $KeyName.pem

#Creating VPC
FrontVPC_ID=$(aws ec2 create-vpc --cidr 10.11.12.0/24 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags \
    --resources $FrontVPC_ID \
    --tags Key=Name,Value=FrontVPC
WordPress_SubnetId=$(aws ec2 create-subnet --vpc-id $FrontVPC_ID --cidr-block 10.11.12.0/28 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $WordPress_SubnetId \
    --tags Key=Name,Value=WordPress_Subnet
DataBase_SubnetId=$(aws ec2 create-subnet --vpc-id $FrontVPC_ID --cidr-block 10.11.12.32/27 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $DataBase_SubnetId \
    --tags Key=Name,Value=DataBase_Subnet
NAT_SubnetId=$(aws ec2 create-subnet --vpc-id $FrontVPC_ID --cidr-block 10.11.12.16/28 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $NAT_SubnetId \
    --tags Key=Name,Value=NAT_Subnet
#Creating internet gateway
InternetGatewayId=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags \
    --resources $InternetGatewayId \
    --tags Key=Name,Value=InternetGateway
#Attaching gateway to VPC
aws ec2 attach-internet-gateway --internet-gateway-id $InternetGatewayId --vpc-id $FrontVPC_ID
#Crating route table
MainRouteTableId=$(aws ec2 create-route-table --vpc-id $FrontVPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $MainRouteTableId \
    --tags Key=Name,Value=MainRouteTable
aws ec2 create-route --route-table-id $MainRouteTableId --destination-cidr-block 0.0.0.0/0 --gateway-id $InternetGatewayId
aws ec2 associate-route-table  --subnet-id $NAT_SubnetId --route-table-id $MainRouteTableId
NAT_SecurityGroupID=$(aws ec2 create-security-group --group-name NAT_SecurityGroup --description "NAT security group" --vpc-id $FrontVPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $NAT_SecurityGroupID \
    --tags Key=Name,Value=NAT_SecurityGroup

#Checking existing NAT instanses
#aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance --query 'Reservations[].Instances[].State.Code' --output text
#aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance Name=instance-state-code,Values=16 --query 'Reservations[].Instances[].InstanceId'
#Creating NAT instance
NAT_InstanceId=$(aws ec2 run-instances \
    --count 1 \
    --image-id ami-00d1f8201864cc10c \
    --instance-type t2.micro \
    --security-group-ids $NAT_SecurityGroupID \
    --subnet-id $NAT_SubnetId \
    --associate-public-ip-address \
    --key-name $KeyName \
    --query 'Instances[].InstanceId' --output text)
aws ec2 modify-instance-attribute \
    --instance-id $NAT_InstanceId\
    --no-source-dest-check
aws ec2 create-tags \
    --resources $NAT_InstanceId \
    --tags Key=Name,Value=NAT_Instance
NAT_PrivateIP=$(aws ec2 describe-instances --instance-id $NAT_InstanceId --query 'Reservations[].Instances[].PrivateIpAddress' --output text)
NAT_PrivateCIDR="${NAT_PrivateIP}/32"
#Inbound rules
aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0,Description="SSH Access"}]'
aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=10.11.12.0/28,Description="HTTP WP Inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=10.11.12.0/28,Description="HTTPs WP Inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=10.11.12.32/27,Description="HTTP DB inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=10.11.12.32/27,Description="HTTPs to DB inbound"}]'
#Otbound rules
aws ec2 authorize-security-group-egress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTP outbound"}]'
aws ec2 authorize-security-group-egress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTPs outbound"}]'
aws ec2 authorize-security-group-egress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=10.11.12.0/28,Description="SSH to WP outbound"}]'
aws ec2 authorize-security-group-egress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=10.11.12.32/27,Description="SSH to DB outbound"}]'

WordPress_SecurityGroupID=$(aws ec2 create-security-group --group-name WP_SecurityGroup --description "WP security group" --vpc-id $FrontVPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $WordPress_SecurityGroupID \
    --tags Key=Name,Value=WordPress_SecurityGroup
#Inbound rules
aws ec2 authorize-security-group-ingress \
--group-id $WordPress_SecurityGroupID \
--protocol tcp \
--port 22 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-ingress \
--group-id $WordPress_SecurityGroupID \
--protocol tcp \
--port 80 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-ingress \
--group-id $WordPress_SecurityGroupID \
--protocol tcp \
--port 443 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-ingress \
--group-id $WordPress_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp=10.11.12.32/27,Description="DB Inbound"}]'
#Outbound Rules
aws ec2 authorize-security-group-egress \
--group-id $WordPress_SecurityGroupID \
--protocol tcp \
--port 80 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-egress \
--group-id $WordPress_SecurityGroupID \
--protocol tcp \
--port 443 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-egress \
--group-id $WordPress_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp=10.11.12.32/27,Description="DB Outbound"}]'
WordPressInstanceId=$(aws ec2 run-instances \
    --count 1 \
    --image-id ami-0fc20dd1da406780b \
    --instance-type t2.micro \
    --security-group-ids $WordPress_SecurityGroupID \
    --subnet-id $WordPress_SubnetId \
    --key-name $KeyName \
    --query 'Instances[].InstanceId' --output text)
aws ec2 create-tags \
    --resources $WordPressInstanceId \
    --tags Key=Name,Value=WordPress_Instance
WordPressInstancePrivateIP=$(aws ec2 describe-instances --instance-id $WordPressInstanceId --query 'Reservations[].Instances[].PrivateIpAddress' --output text)

PrivateRouteTableId=$(aws ec2 create-route-table --vpc-id $FrontVPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $PrivateRouteTableId \
    --tags Key=Name,Value=PrivateRouteTable
aws ec2 create-route --route-table-id $PrivateRouteTableId --destination-cidr-block 0.0.0.0/0 --instance-id $NAT_InstanceId
aws ec2 associate-route-table --subnet-id $WordPress_SubnetId --route-table-id $PrivateRouteTableId

DataBase_SecurityGroupID=$(aws ec2 create-security-group --group-name DB_SecurityGroup --description "DB security group" --vpc-id $FrontVPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $DataBase_SecurityGroupID \
    --tags Key=Name,Value=DataBase_SecurityGroup

#Inbound Rules

aws ec2 authorize-security-group-ingress \
--group-id $DataBase_SecurityGroupID \
--protocol tcp \
--port 22 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-ingress \
--group-id $DataBase_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp=10.11.12.0/28,Description="WP Inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $DataBase_SecurityGroupID \
--protocol tcp \
--port 80 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-ingress \
--group-id $DataBase_SecurityGroupID \
--protocol tcp \
--port 443 \
--cidr $NAT_PrivateCIDR

#Outbound rules
aws ec2 authorize-security-group-egress \
--group-id $DataBase_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges='[{CidrIp=10.11.12.0/28,Description="WP Outbound"}]'
aws ec2 authorize-security-group-egress \
--group-id $DataBase_SecurityGroupID \
--protocol tcp \
--port 80 \
--cidr $NAT_PrivateCIDR
aws ec2 authorize-security-group-egress \
--group-id $DataBase_SecurityGroupID \
--protocol tcp \
--port 443 \
--cidr $NAT_PrivateCIDR

BD_PrivateRouteTableId=$(aws ec2 create-route-table --vpc-id $FrontVPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $BD_PrivateRouteTableId \
    --tags Key=Name,Value=BD_PrivateRouteTable
aws ec2 create-route --route-table-id $BD_PrivateRouteTableId --destination-cidr-block 0.0.0.0/0 --instance-id $NAT_InstanceId
aws ec2 associate-route-table --subnet-id $DataBase_SubnetId --route-table-id $BD_PrivateRouteTableId

DataBaseInstanceID=$(aws ec2 run-instances \
    --count 1 \
    --image-id ami-0520e698dd500b1d1 \
    --instance-type t2.micro \
    --security-group-ids $DataBase_SecurityGroupID \
    --subnet-id $DataBase_SubnetId \
    --key-name $KeyName\
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DataBase_Instance}]')
DataBaseInstancePrivateIP=$(aws ec2 describe-instances --instance-id $DataBaseInstanceID --query 'Reservations[].Instances[].PrivateIpAddress' --output text)

#New VPC for Remote Desktop Service Farm
RDS_VPC_ID=$(aws ec2 create-vpc --cidr 172.200.34.0/24 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags \
    --resources $RDS_VPC_ID \
    --tags Key=Name,Value=RDS_VPC
RDS_PublicSubNet_ID=$(aws ec2 create-subnet --vpc-id $RDS_VPC_ID --cidr-block 172.200.34.0/25 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $RDS_PublicSubNet_ID \
    --tags Key=Name,Value=RDS_PublicSubNet

#Internet Gateway for external connections
RDS_InternetGatewayId=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags \
    --resources $RDS_InternetGatewayId \
    --tags Key=Name,Value=RDS_InternetGateway

#Attaching gateway to VPC
aws ec2 attach-internet-gateway --internet-gateway-id $RDS_InternetGatewayId --vpc-id $RDS_VPC_ID

#Crating route table
RDS_MainRouteTableId=$(aws ec2 create-route-table --vpc-id $RDS_VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $RDS_MainRouteTableId \
    --tags Key=Name,Value=RDS_MainRouteTable
aws ec2 create-route --route-table-id $RDS_MainRouteTableId --destination-cidr-block 0.0.0.0/0 --gateway-id $RDS_InternetGatewayId
aws ec2 associate-route-table  --subnet-id $RDS_PublicSubNet_ID --route-table-id $RDS_MainRouteTableId

#Creating Security Group
RDS_SecurityGroupID=$(aws ec2 create-security-group --group-name RDS_SecurityGroup --description "Remote Desktop Service security group" --vpc-id $RDS_VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $RDS_SecurityGroupID \
    --tags Key=Name,Value=RDS_SecurityGroup

#Inbound Rules
aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0,Description="SSH Access"}]'
aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=3389,ToPort=3389,IpRanges='[{CidrIp=0.0.0.0/0,Description="RDP Access"}]'
#Outbound Rules
aws ec2 authorize-security-group-egress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTP outbound"}]'

#Remote Desktop Service Farm Instance
RDS_InstanceId=$(aws ec2 run-instances \
    --count 1 \
    --image-id ami-07f3715a1f6dbb6d9 \
    --instance-type t2.micro \
    --security-group-ids $RDS_SecurityGroupID \
    --subnet-id $RDS_PublicSubNet_ID \
    --associate-public-ip-address \
    --key-name $KeyName \
    --query 'Instances[].InstanceId' --output text)
aws ec2 create-tags \
    --resources $RDS_InstanceId \
    --tags Key=Name,Value=Remote_Desktop_Farm
RDS_InstancePublicIP=$(aws ec2 describe-instances --instance-id $RDS_InstanceId --query 'Reservations[].Instances[].PublicIpAddress' --output text)

#Virtual Privat Gateway to coonect with RDS_VPC
toRDP_VPN_GatewayId=$(aws ec2 create-vpn-gateway --type ipsec.1 --query 'VpnGateway.VpnGatewayId' --output text)
aws ec2 create-tags \
    --resources $toRDP_VPN_GatewayId \
    --tags Key=Name,Value=toRDP_VPN_Gateway
aws ec2 attach-vpn-gateway --vpn-gateway-id $toRDP_VPN_GatewayId --vpc-id $FrontVPC_ID

#Stopping instances to modifay their attributes
aws ec2 stop-instances --instance-ids "$NAT_InstanceId" "$WordPressInstanceId" "$DataBaseInstanceID" "$RDS_InstanceId"

sed "s/.*WP_IP=.*/WP_IP=$WordPressInstancePrivateIP/" NAT_UserData.sh > text
cat text > NAT_UserData.sh
sed "s/.*WP_IP=.*/WP_IP=$WordPressInstancePrivateIP/" DB_UserData.sh > text
cat text > DB_UserData.sh
sed "s/.*DB_IP=.*/DB_IP=$DataBaseInstancePrivateIP/" WP_Userdata_U.sh > text
cat text > WP_Userdata_U.s

#Adding startup scripts
base64 NAT_UserData.sh >NAT_UserData_base64.sh
aws ec2 modify-instance-attribute --instance-id $NAT_InstanceId --attribute userData --value file://NAT_UserData_base64.sh
rm -f NAT_UserData_base64.sh
base64 WP_Userdata_U.sh >WP_Userdata_U_base64.sh
aws ec2 modify-instance-attribute --instance-id $WordPressInstanceId --attribute userData --value file://WP_Userdata_U_base64.sh
rm -f WP_Userdata_U_base64.sh
base64 DB_UserData.sh >DB_UserData_base64.sh
aws ec2 modify-instance-attribute --instance-id $DataBaseInstanceID --attribute userData --value file://DB_UserData_base64.sh
rm -f DB_UserData_base64.sh

aws ec2 start-instances --instance-ids "$NAT_InstanceId" "$WordPressInstanceId" "$DataBaseInstanceID"

#Customer Gateway to connect with Front_VPC
CustomerGWID=$(aws ec2 create-customer-gateway --type ipsec.1 --public-ip $RDS_InstancePublicIP --query 'CustomerGateway.CustomerGatewayId' --output text)
aws ec2 create-tags \
    --resources $CustomerGWID \
    --tags Key=Name,Value=RDP_CustomerGateway

#Virtual private gateway
VirtualPrivateGWID=$(aws ec2 create-vpn-gateway --type ipsec.1 --query 'VpnGateway.VpnGatewayId' --output text)
aws ec2 create-tags \
    --resources $VirtualPrivateGWID \
    --tags Key=Name,Value=Front_VpnGateway

#Ceating vpn connection
RDPtoFrontConnectionId=$(aws ec2 create-vpn-connection \
--type ipsec.1 \
--customer-gateway-id $CustomerGWID \
--vpn-gateway-id $VirtualPrivateGWID \
--options "{\"StaticRoutesOnly\":true}" \
--query 'VpnConnection.VpnConnectionId' \
--output text)
aws ec2 create-tags \
    --resources $RDPtoFrontConnectionId \
    --tags Key=Name,Value=RDP_to_FrontVPC_VpnConnection

echo "to enable ssh agent while connecting to NAT Instanse use next commands:
NAT_PBL_IP=\$(aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance Name=instance-state-code,Values=16 --query 'Reservations[].Instances[].PublicIpAddress' --output text)
ssh -A ec2-user@\$NAT_PBL_IP
to remove key use:
KeyName=\$(aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance Name=instance-state-code,Values=16 --query 'Reservations[].Instances[].KeyName' --output text)
aws ec2 delete-key-pair --key-name \$KeyName
ssh-add -D
rm -f \$KeyName.pem"
