#!/bin/bash
# Pre requirements:
# Ubuntu
# configured security groups for 8080 and 50000 ports
# configured IAM jenkins user/role

#AWS jenkins user credentials
aws_access_key_id=""
aws_secret_access_key=""

#Adding jenkins repository
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | apt-key add -
sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ > \
    /etc/apt/sources.list.d/jenkins.list'
apt-get update -y

#insatlling openjdk 8 & jenkins itself
apt-get install -y openjdk-8-jdk
apt-get install -y jenkins

systemctl start jenkins

#installing AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install unzip -y
unzip awscliv2.zip
./aws/install

#configuring AWS CLI for jenkins user
su - jenkins -c "mkdir /var/lib/jenkins/.aws"
su - jenkins -c "echo '[default]
region = us-east-2
output = json'>/var/lib/jenkins/.aws/config"
su - jenkins -c "echo '[default]
aws_access_key_id = $aws_access_key_id
aws_secret_access_key = $aws_secret_access_key'>/var/lib/jenkins/.aws/credentials"
