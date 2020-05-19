#!/bin/bash
#Creating unique key for passwordless authentification

#creating unique keyname adding current date
KeyName="MyKeyPair$(date "+%Y-%m-%d(%H:%M:%S)")"
#Creating a key pair and piping private key directly into a file
aws ec2 create-key-pair --key-name $KeyName --query 'KeyMaterial' --output text > $KeyName.pem

#creating iam user jenkins
JenkinsUserID=$(aws iam create-user --user-name jenkins --query 'User.UserId' --output text)
JenkinsUserKey=$(aws iam create-access-key --user-name jenkins --output text)
keyID=$(echo $JenkinsUserKey | awk '{print $2}')
secrKey=$(echo $JenkinsUserKey | awk '{print $4}')
aws iam attach-user-policy --user-name jenkins --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-user-policy --user-name jenkins --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess


#sed "s/.*aws_access_key_id=.*/aws_access_key_id=$keyID/" jenkins_userdata.sh|sed "s/.*aws_secret_access_key=.*/aws_secret_access_key=$secrKey/"|base64>tmp.txt
