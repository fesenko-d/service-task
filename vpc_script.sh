#!/bin/bash
#Creating unique key for passwordless authentification

#creating unique keyname adding current date
KeyName="serviceTaskKeyPair"
bucketName="servicetask-9000"
#Creating a key pair and piping private key directly into a file
aws ec2 create-key-pair --key-name $KeyName --query 'KeyMaterial' --output text > $KeyName.pem
#storing key in S3
aws s3 cp $KeyName.pem s3://$bucketName/${KeyName}.pem --region $region


echo Creating VPC
FrontVPC_ID=$(aws ec2 create-vpc --cidr 10.11.12.0/24 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags \
    --resources $FrontVPC_ID \
    --tags Key=Name,Value=FrontVPC

echo Creating WordPress Subnet
WordPress_SubnetId=$(aws ec2 create-subnet --vpc-id $FrontVPC_ID --cidr-block 10.11.12.0/28 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $WordPress_SubnetId \
    --tags Key=Name,Value=WordPress_Subnet

echo Creating DataBase Subnet
DataBase_SubnetId=$(aws ec2 create-subnet --vpc-id $FrontVPC_ID --cidr-block 10.11.12.32/27 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $DataBase_SubnetId \
    --tags Key=Name,Value=DataBase_Subnet

echo Creating NAT Subnet
NAT_SubnetId=$(aws ec2 create-subnet --vpc-id $FrontVPC_ID --cidr-block 10.11.12.16/28 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $NAT_SubnetId \
    --tags Key=Name,Value=NAT_Subnet

echo Creating internet gateway
InternetGatewayId=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags \
    --resources $InternetGatewayId \
    --tags Key=Name,Value=InternetGateway

echo Attaching gateway to VPC
aws ec2 attach-internet-gateway --internet-gateway-id $InternetGatewayId --vpc-id $FrontVPC_ID >/dev/null

echo Crating main route table
MainRouteTableId=$(aws ec2 create-route-table --vpc-id $FrontVPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $MainRouteTableId \
    --tags Key=Name,Value=MainRouteTable

echo Creating route in main route table
aws ec2 create-route --route-table-id $MainRouteTableId --destination-cidr-block 0.0.0.0/0 --gateway-id $InternetGatewayId >/dev/null

echo Associating route table with NAT Subnet
aws ec2 associate-route-table  --subnet-id $NAT_SubnetId --route-table-id $MainRouteTableId >/dev/null

echo Creating NAT Security Group
NAT_SecurityGroupID=$(aws ec2 create-security-group --group-name NAT_SecurityGroup --description "NAT security group" --vpc-id $FrontVPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $NAT_SecurityGroupID \
    --tags Key=Name,Value=NAT_SecurityGroup

#Checking existing NAT instanses
#aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance --query 'Reservations[].Instances[].State.Code' --output text
#aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance Name=instance-state-code,Values=16 --query 'Reservations[].Instances[].InstanceId'
echo Creating NAT instance
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

echo Adding NAT Security Group Inbound rules

aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0,Description="SSH Access"}]'
aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTP Inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $NAT_SecurityGroupID \
--ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTPS Inbound"}]'
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

echo Adding NAT Security Group Otbound rules

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

echo Creating WordPress Security Group
WordPress_SecurityGroupID=$(aws ec2 create-security-group --group-name WP_SecurityGroup --description "WP security group" --vpc-id $FrontVPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $WordPress_SecurityGroupID \
    --tags Key=Name,Value=WordPress_SecurityGroup

echo Adding WordPress Security Group Inbound rules
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

echo Adding WordPress Security Group Outbound Rules
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

echo Creating Wordpress Instances
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

echo Creating Private route table
PrivateRouteTableId=$(aws ec2 create-route-table --vpc-id $FrontVPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $PrivateRouteTableId \
    --tags Key=Name,Value=PrivateRouteTable

echo Creating route to internet through NAT Instance as gateway
aws ec2 create-route --route-table-id $PrivateRouteTableId --destination-cidr-block 0.0.0.0/0 --instance-id $NAT_InstanceId >/dev/null

echo Associating Private Route Table with Wordpress Subnet
aws ec2 associate-route-table --subnet-id $WordPress_SubnetId --route-table-id $PrivateRouteTableId >/dev/null

echo Creating DataBase Security Group
DataBase_SecurityGroupID=$(aws ec2 create-security-group --group-name DB_SecurityGroup --description "DB security group" --vpc-id $FrontVPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $DataBase_SecurityGroupID \
    --tags Key=Name,Value=DataBase_SecurityGroup

echo Adding DataBase Security Group Inbound Rules

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

echo Adding DataBase Security Group Outbound rules

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

echo Creating DataBase Subnet Private Route Table
BD_PrivateRouteTableId=$(aws ec2 create-route-table --vpc-id $FrontVPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $BD_PrivateRouteTableId \
    --tags Key=Name,Value=BD_PrivateRouteTable

echo Creating route to internet through NAT Instance as gateway
aws ec2 create-route --route-table-id $BD_PrivateRouteTableId --destination-cidr-block 0.0.0.0/0 --instance-id $NAT_InstanceId >/dev/null

echo Assotiating DataBase Subnet Private Route Table with DataBase Subnet
aws ec2 associate-route-table --subnet-id $DataBase_SubnetId --route-table-id $BD_PrivateRouteTableId >/dev/null

echo Creating Database instance
DataBaseInstanceID=$(aws ec2 run-instances \
    --count 1 \
    --image-id ami-0520e698dd500b1d1 \
    --instance-type t2.micro \
    --security-group-ids $DataBase_SecurityGroupID \
    --subnet-id $DataBase_SubnetId \
    --key-name $KeyName\
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DataBase_Instance}]' \
    --query 'Instances[].InstanceId' \
    --output text)
DataBaseInstancePrivateIP=$(aws ec2 describe-instances --instance-id $DataBaseInstanceID --query 'Reservations[].Instances[].PrivateIpAddress' --output text)

echo Creating VPC for Remote Desktop Service Farm
RDS_VPC_ID=$(aws ec2 create-vpc --cidr 172.200.34.0/24 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags \
    --resources $RDS_VPC_ID \
    --tags Key=Name,Value=RDS_VPC

echo Creating Remote Desktop Service public subnet
RDS_PublicSubNet_ID=$(aws ec2 create-subnet --vpc-id $RDS_VPC_ID --cidr-block 172.200.34.0/25 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $RDS_PublicSubNet_ID \
    --tags Key=Name,Value=RDS_PublicSubNet

echo Creating Internet Gateway for external connections
RDS_InternetGatewayId=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags \
    --resources $RDS_InternetGatewayId \
    --tags Key=Name,Value=RDS_InternetGateway

echo Attaching gateway to Remote Desktop Service VPC
aws ec2 attach-internet-gateway --internet-gateway-id $RDS_InternetGatewayId --vpc-id $RDS_VPC_ID >/dev/null

echo Crating Remote Desktop Service main route table
RDS_MainRouteTableId=$(aws ec2 create-route-table --vpc-id $RDS_VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $RDS_MainRouteTableId \
    --tags Key=Name,Value=RDS_MainRouteTable

echo Adding route to internet in main route table
aws ec2 create-route --route-table-id $RDS_MainRouteTableId --destination-cidr-block 0.0.0.0/0 --gateway-id $RDS_InternetGatewayId >/dev/null

echo Associating route table with Remote Desktop Service public subnet
aws ec2 associate-route-table  --subnet-id $RDS_PublicSubNet_ID --route-table-id $RDS_MainRouteTableId >/dev/null

echo Creating Remote Desktop Service Security Group
RDS_SecurityGroupID=$(aws ec2 create-security-group --group-name RDS_SecurityGroup --description "Remote Desktop Service security group" --vpc-id $RDS_VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $RDS_SecurityGroupID \
    --tags Key=Name,Value=RDS_SecurityGroup

echo Adding Remote Desktop Service Security Group Inbound Rules
aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=icmp,FromPort=0,ToPort=65535,IpRanges='[{CidrIp=0.0.0.0/0,Description="ICMP Access"}]'

aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=3389,ToPort=3389,IpRanges='[{CidrIp=0.0.0.0/0,Description="RDP Access"}]'

aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTP Access"}]'

aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTPS Access"}]'

echo Adding Remote Desktop Service Security Group Outbound Rules
aws ec2 authorize-security-group-egress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTP outbound"}]'

aws ec2 authorize-security-group-egress \
    --group-id $RDS_SecurityGroupID \
    --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTPS outbound"}]'


echo Creating AD domain controller
#Based on Windows_Server-2019-English-Core-ECS_Optimized-2020.05.14
AD_InstanceId=$(aws ec2 run-instances \
    --count 1 \
    --image-id ami-0115c3c361523afa1 \
    --instance-type t2.micro \
    --security-group-ids $RDS_SecurityGroupID \
    --subnet-id $RDS_PublicSubNet_ID \
    --associate-public-ip-address \
    --key-name $KeyName \
    --query 'Instances[].InstanceId' --output text)
aws ec2 create-tags \
    --resources $AD_InstanceId \
    --tags Key=Name,Value=AD_Domain_Controller

echo Creating Remote Desktop Service Farm Instance
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

echo Creating Virtual Privat Gateway to coonect with RDS_VPC
toRDP_VPN_GatewayId=$(aws ec2 create-vpn-gateway --type ipsec.1 --query 'VpnGateway.VpnGatewayId' --output text)
aws ec2 create-tags \
    --resources $toRDP_VPN_GatewayId \
    --tags Key=Name,Value=toRDP_VPN_Gateway

echo Attaching VPN Gateway to Front VPC
aws ec2 attach-vpn-gateway --vpn-gateway-id $toRDP_VPN_GatewayId --vpc-id $FrontVPC_ID >/dev/null


echo Customer Gateway to connect with Front_VPC
CustomerGWID=$(aws ec2 create-customer-gateway --bgp-asn 65000 --type ipsec.1 --public-ip $RDS_InstancePublicIP --query 'CustomerGateway.CustomerGatewayId' --output text)
aws ec2 create-tags \
    --resources $CustomerGWID \
    --tags Key=Name,Value=RDP_CustomerGateway


echo Ceating vpn connection
RDPtoFrontConnectionId=$(aws ec2 create-vpn-connection \
--type ipsec.1 \
--customer-gateway-id $CustomerGWID \
--vpn-gateway-id $toRDP_VPN_GatewayId \
--options "{\"StaticRoutesOnly\":true}" \
--query 'VpnConnection.VpnConnectionId' \
--output text)
aws ec2 create-tags \
    --resources $RDPtoFrontConnectionId \
    --tags Key=Name,Value=RDP_to_FrontVPC_VpnConnection

echo Stopping instances to modifay their attributes
while :
do
  echo checking instances
  NATStateCode=$(aws ec2 describe-instances --instance-id $NAT_InstanceId --query 'Reservations[].Instances[].State.Code' --output text)
  WPStateCode=$(aws ec2 describe-instances --instance-id $WordPressInstanceId --query 'Reservations[].Instances[].State.Code' --output text)
  DBStateCode=$(aws ec2 describe-instances --instance-id $DataBaseInstanceID --query 'Reservations[].Instances[].State.Code' --output text)
  RStateCode=$(aws ec2 describe-instances --instance-id $RDS_InstanceId --query 'Reservations[].Instances[].State.Code' --output text)
  if [[ $NATStateCode -eq 16 && $WPStateCode -eq 16 && $DBStateCode -eq 16 && $RStateCode -eq 16 ]]
  then
    echo success
    break
  fi
done
aws ec2 stop-instances --instance-ids "$NAT_InstanceId" "$WordPressInstanceId" "$DataBaseInstanceID" "$RDS_InstanceId" >/dev/null

echo Adding startup scripts
while :
do
  echo checking instances
  NATStateCode=$(aws ec2 describe-instances --instance-id $NAT_InstanceId --query 'Reservations[].Instances[].State.Code' --output text)
  WPStateCode=$(aws ec2 describe-instances --instance-id $WordPressInstanceId --query 'Reservations[].Instances[].State.Code' --output text)
  DBStateCode=$(aws ec2 describe-instances --instance-id $DataBaseInstanceID --query 'Reservations[].Instances[].State.Code' --output text)
  RStateCode=$(aws ec2 describe-instances --instance-id $RDS_InstanceId --query 'Reservations[].Instances[].State.Code' --output text)
  if [[ $NATStateCode -eq 80 && $WPStateCode -eq 80 && $DBStateCode -eq 80 && $RStateCode -eq 80 ]]
  then
    echo success
    break
  fi
done

if [ -f cloud_init.txt ]
then
  if [ -f NAT_UserData.sh ]
  then
    sed '/DATA/ {
    r NAT_UserData.sh
    d
    }' cloud_init.txt|sed "s/.*WP_IP=.*/WP_IP=$WordPressInstancePrivateIP/"|base64>tmp.txt
    aws ec2 modify-instance-attribute --instance-id $NAT_InstanceId --attribute userData --value file://tmp.txt
  else
    echo NAT_UserData.sh not found
  fi

  if [ -f WP_Userdata_U.sh ]
  then
    sed '/DATA/ {
    r WP_Userdata_U.sh
    d
    }' cloud_init.txt|sed "s/.*DB_IP=.*/DB_IP=$DataBaseInstancePrivateIP/"|base64>tmp.txt
    aws ec2 modify-instance-attribute --instance-id $WordPressInstanceId --attribute userData --value file://tmp.txt
  else
    echo WP_Userdata_U.sh not found
  fi

  if [ -f NAT_UserData.sh ]
  then
    sed '/DATA/ {
    r DB_UserData.sh
    d
    }' cloud_init.txt|sed "s/.*WP_IP=.*/WP_IP=$WordPressInstancePrivateIP/"|base64>tmp.txt
    aws ec2 modify-instance-attribute --instance-id $DataBaseInstanceID --attribute userData --value file://tmp.txt
  else
    echo NAT_UserData.sh not found
  fi

else
  echo cloud_init.txt not found
fi
rm -f tmp.txt

echo Starting instances
aws ec2 start-instances --instance-ids "$NAT_InstanceId" "$WordPressInstanceId" "$DataBaseInstanceID" "$RDS_InstanceId" >/dev/null



echo "to enable ssh agent while connecting to NAT Instanse use next commands:
NAT_PBL_IP=\$(aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance Name=instance-state-code,Values=16 --query 'Reservations[].Instances[].PublicIpAddress' --output text)
ssh -A ec2-user@\$NAT_PBL_IP
to remove key use:
KeyName=\$(aws ec2 describe-instances --filters Name=tag:Name,Values=NAT_Instance Name=instance-state-code,Values=16 --query 'Reservations[].Instances[].KeyName' --output text)
aws ec2 delete-key-pair --key-name \$KeyName
ssh-add -D
rm -f \$KeyName.pem"
