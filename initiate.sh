#!/bin/bash
#prerequirements :
# installed jq utility for work with json
#Creating unique key for passwordless authentification

#variables
bucketName="servicetask-9000"
KeyName="JenkinsKeyPair"
region="us-east-2"
#Creating a key pair and piping private key directly into a file
aws ec2 create-key-pair --key-name $KeyName --query 'KeyMaterial' --output text > $KeyName.pem
#storing key in S3
aws s3 mb s3://$bucketName
aws s3 cp $KeyName.pem s3://$bucketName/${KeyName}.pem --region $region
#seting the permissions of private key file so that only we can read it
chmod 400 $KeyName.pem
#Adding private key to the authentication agent
ssh-add -K $KeyName.pem

#Jenkins instance vpc
echo Creating jenkinsVPC
jenkinsVPC_ID=$(aws ec2 create-vpc --cidr 10.100.80.0/24 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags \
    --resources $jenkinsVPC_ID \
    --tags Key=Name,Value=jenkinsVPC

echo Creating Jenkins Subnet
Jenkins_SubnetId=$(aws ec2 create-subnet --vpc-id $jenkinsVPC_ID --cidr-block 10.100.80.0/25 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags \
    --resources $Jenkins_SubnetId \
    --tags Key=Name,Value=Jenkins_Subnet


echo Creating internet gateway
jenkinsIGwId=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags \
    --resources $jenkinsIGwId \
    --tags Key=Name,Value=JenkinsInternetGateway

echo Attaching gateway to VPC
aws ec2 attach-internet-gateway --internet-gateway-id $jenkinsIGwId --vpc-id $jenkinsVPC_ID >/dev/null

echo Crating jenkins vpc route table
JenkinsRTId=$(aws ec2 create-route-table --vpc-id $jenkinsVPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags \
    --resources $JenkinsRTId \
    --tags Key=Name,Value=jenkinsRouteTable

echo Creating route in main route table
aws ec2 create-route --route-table-id $JenkinsRTId --destination-cidr-block 0.0.0.0/0 --gateway-id $jenkinsIGwId >/dev/null

echo Associating route table with jenkins Subnet
aws ec2 associate-route-table  --subnet-id $Jenkins_SubnetId --route-table-id $JenkinsRTId >/dev/null

echo Creating Jenkins SG
JenkinsSG_ID=$(aws ec2 create-security-group --group-name JenkinsSG_ID --description "NAT security group" --vpc-id $jenkinsVPC_ID --query 'GroupId' --output text)
aws ec2 create-tags \
    --resources $JenkinsSG_ID \
    --tags Key=Name,Value=JenkinsSG_ID

aws ec2 authorize-security-group-ingress \
--group-id $JenkinsSG_ID \
--ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="http Inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $JenkinsSG_ID \
--ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0,Description="ssh Inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $JenkinsSG_ID \
--ip-permissions IpProtocol=tcp,FromPort=8080,ToPort=8080,IpRanges='[{CidrIp=0.0.0.0/0,Description="jenkins Inbound"}]'
aws ec2 authorize-security-group-ingress \
--group-id $JenkinsSG_ID \
--ip-permissions IpProtocol=tcp,FromPort=50000,ToPort=50000,IpRanges='[{CidrIp=0.0.0.0/0,Description="jenkins agent Inbound"}]'

aws ec2 authorize-security-group-egress \
--group-id $JenkinsSG_ID \
--protocol tcp \
--port 0-65535 \
--cidr 0.0.0.0/0




#creating iam user jenkins
JenkinsUserID=$(aws iam create-user --user-name jenkins --query 'User.UserId' --output text)
# attaching policy that allows full access to EC2 services
aws iam attach-user-policy --user-name jenkins --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
# attaching policy that allows full access to S3 services
aws iam attach-user-policy --user-name jenkins --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

JenkinsUserKey=$(aws iam create-access-key --user-name jenkins --output json)
keyID="aws_access_key_id=$(echo $JenkinsUserKey | jq -c '.[].AccessKeyId')"
secrKey="aws_secret_access_key=$(echo $JenkinsUserKey | jq -c '.[].SecretAccessKey')"

function Lambda_Substitution() {
    subs_find=$1
    subs_replace=$2
    awk -v subs_find=$subs_find -v subs_replace=$subs_replace '{gsub(subs_find, subs_replace, $0)}1'
}


cat jenkins_userdata.sh|Lambda_Substitution "aws_access_key_id=DATA" $keyID|Lambda_Substitution "aws_secret_access_key=DATA" $secrKey > tmp.txt

JenkinsInstanceID=$(aws ec2 run-instances \
    --count 1 \
    --image-id ami-07c1207a9d40bc3bd \
    --instance-type t2.micro \
    --security-group-ids $JenkinsSG_ID \
    --subnet-id $Jenkins_SubnetId \
    --key-name $KeyName\
    --associate-public-ip-address \
    --user-data file://tmp.txt \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Jenkins_Instance}]' \
    --query 'Instances[].InstanceId' \
    --output text)

rm -f tmp.txt
