#!/bin/bash
#variables
KeyName="serviceTaskKeyPair"
bucketName="servicetask-9000"
region="us-east-2"
declare -A VpcList=( [FrontVPC]=10.11.12.0/24 [RDS_VPC]=172.200.34.0/24 )

#REMOVING VPC AND ALL IN IT
for VpcName in ${!VpcList[@]}
do
  vpcidList=($(aws ec2 describe-vpcs --filters Name=tag:Name,Values=$K Name=cidr,Values=${VpcList[$K]} --query 'Vpcs[].VpcId' --output json|jq -r '.[]'))
  if [[ $vpcidList ]]
    then
      for vpcid in $vpcidList
      do
#Removing vpn connection
        aws ec2 describe-
        aws ec2 delete-vpn-connection --vpn-connection-id $vpnConnectionId

#Removing CustomerGW
        aws ec2 describe-customer-gateways --filters Name=tag:Name,Values=$cgTagName
        aws ec2 delete-customer-gateway --customer-gateway-id $cgwid


#Removing VPNGV
#Dettaching VPNGV from VPC
        aws ec2 detach-vpn-gateway --vpn-gateway-id $vpnGvId --vpc-id $vpcid

        aws ec2 delete-vpn-gateway --vpn-gateway-id $vpnGvId

#removing instances
        instids=($(aws ec2 describe-instances --filters Name=vpc-id,Values=$vpcid --query 'Reservations[].Instances[].InstanceId' --output json|jq -r '.[]'))
        if [[ $instids ]]
        then
          for i in $instids
          do
            while :
            do
              statecode=$(aws ec2 describe-instances --instance-ids $i --query 'Reservations[].Instances[].Code' --output text)
              case $statecode in
                16|80)
                  echo terminate
                  aws ec2 aws ec2 terminate-instances --instance-ids $i
                  break
                  ;;
                48)
                  break
                  ;;
                *)
                  echo wait
                  ;;
              esac
            done
          done
        else
          echo nothing to do
        fi

#removing security groups
        SgIDs=($(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$vpcid --query 'SecurityGroups[].GroupId' --output json|jq -r '.[]'))
        if [[ $SgIDs ]]
        then
          for i in $SgIDs
          do
            aws ec2 delete-security-group --group-id $i
          done
        else
          echo nothing to do
        fi


#Remove route table
        rtid=($(aws ec2 describe-route-tables --filters Name=vpc-id ,Values=$vpcid --query 'RouteTables[].RouteTableId' --output json|jq -r '.[]'))
        if [[ $rtid ]]
        then
          for i in $rtid
          do
#disassociating routetable from subnet
            rtbassocIds=($(aws ec2 describe-route-tables --route-table-ids $i --query 'RouteTables[].Associations[].RouteTableAssociationId' --output json|jq -r '.[]'))
            if [[ $rtbassocIds ]]
            then
              for e in $rtbassocIds
              do
                aws ec2 disassociate-route-table --association-id $e
              done
            else
              echo nothing to do
            fi
            aws ec2 delete-route-table --route-table-id $i
          done
        else
          echo nothing to do
        fi

#removing igateway
        igvlist=($(aws ec2 describe-internet-gateways --filters Name=tag:Name,Values=$igvTagNamelist  --query 'InternetGateways[].InternetGatewayId' --output json|jq -r '.[]'))
        if [[ $igvlist ]]
        then
          for i in $igwid
          do
#dettaching gateway from VPC
            aws ec2 detach-internet-gateway --internet-gateway-id $i --vpc-id $vpcid
            aws ec2 delete-internet-gateway --internet-gateway-id $i
          done
        else
          echo nothing to do
        fi

#removing subnets
        subids=($(aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid --query 'Subnets[].SubnetId' --output json|jq -r '.[]'))
        if [[ $subids ]]
        then
          for i in $subids
          do
            aws ec2 delete-subnet --subnet-id $i
          done
        else
          echo nothing to do
        fi

#removing VPCs

        aws ec2 delete-vpc --vpc-id $i
      done
    else
    echo nothing to do
  fi
done

#removing keys from bucket
aws s3 rm s3://$bucketName/${KeyName}.pem --region $region

#removing keys
KeyID=$(aws ec2 describe-key-pairs --key-name $KeyName)
if [[ $KeyID ]]
  then
    aws ec2 delete-key-pair --key-pair-id $KeyID
  else
    echo nothing to do
fi
