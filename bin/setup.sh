#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..
source $DIR/conf/config

function create_vpc() {

  VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR_BLOCK | grep VpcId | head -1 \
          | awk '{gsub(/\"/, "");gsub(/,/,""); print $2}')
  
  aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
  aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

  IGW_ID=$(aws ec2 create-internet-gateway | grep InternetGatewayId | head -1 | \
          awk '{gsub(/\"/, "");gsub(/,/,""); print $2}')
  aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

  PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --availability-zone $AZ --cidr-block $PUBLIC_SUBNET \
                    | grep SubnetId | head -1 | awk '{gsub(/\"/, "");gsub(/,/,""); print $2}')
  # PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID  --availability-zone $AZ  --cidr-block $PRIBATE_SUBNET \
  #           | grep SubnetId | head -1 | awk '{gsub(/\"/, "");gsub(/,/,""); print $2}')

  MAIN_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
                      | grep RouteTableId | head -1 | awk '{gsub(/\"/, "");gsub(/,/,""); print $2}')

  aws ec2 create-route --route-table-id $MAIN_ROUTE_TABLE_ID \
    --destination-cidr-block '0.0.0.0/0' --gateway-id $IGW_ID

  aws ec2 associate-route-table --route-table-id $MAIN_ROUTE_TABLE_ID --subnet-id $PUBLIC_SUBNET_ID

  # CUSTOM_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  #               | grep RouteTableId | head -1 | awk '{gsub(/\"/, "");gsub(/,/,""); print $2}')

  # aws ec2 associate-route-table --route-table-id $CUSTOM_ROUTE_TABLE_ID --subnet-id $PRIVATE_SUBNET_ID

  aws ec2 create-vpc-endpoint --vpc-id $VPC_ID \
    --service-name com.amazonaws.ap-southeast-1.s3 --route-table-ids $MAIN_ROUTE_TABLE_ID

  CUSTOM_SECURITY_GROUP_ID=$(aws ec2 create-security-group --vpc-id $VPC_ID --group-name custom --description custom \
                             | grep GroupId | head -1  | awk '{gsub(/\"/, "");gsub(/,/,""); print $2}')

  aws ec2 authorize-security-group-ingress --group-id $CUSTOM_SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id $CUSTOM_SECURITY_GROUP_ID --protocol tcp --port 8888 --cidr 0.0.0.0/0
}

create_emr() {

  OS_TYPE=$(uname -s)

  if [ "$OS_TYPE" = "Darwin" ]; then
    START_TIME=$(date -v -1H -u +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  else
    echo 
  fi

  echo "Getting On Demand pricing from AWS..."

  CURRENT_ON_DEMAND_PRICE=$(curl -s https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/index.csv \
                            | grep $INSTANCE_TYPE \
                            | grep Linux | grep OnDemand | grep Singapore \
                            | grep -v Dedicated | cut -d, -f10 | sort -dr | head -n1 | bc)

  AVG_SPOT_PRICE=$(aws ec2 describe-spot-price-history --instance-types $INSTANCE_TYPE \
                    --availability-zone $AZ \
                    --product-description "Linux/UNIX (Amazon VPC)" \
                    --start-time $START_TIME \
                    --end-time $END_TIME | grep SpotPrice \
                    | awk '{gsub(/\"/, "");gsub(/,/,""); print $2}' \
                    | awk '{s+=$1}END{print s/NR}')

  BID_PRICE=$(echo  "$AVG_SPOT_PRICE $ADD_TO_BID_PRICE" | awk '{printf "%.3f", $1 + $2}')

  echo "INSTANCE TYPE: $INSTANCE_TYPE"
  echo "CURRENT ON DEMAND PRICE: $CURRENT_ON_DEMAND_PRICE"
  echo "AVERAGE SPOT PRICE: $AVG_SPOT_PRICE"
  echo "YOUR BID PRICE: $BID_PRICE"
    
  if [ $(echo "$BID_PRICE > $CURRENT_ON_DEMAND_PRICE" | bc) -eq 1 ]; then
    echo "!!! Your Bid price > On Demand price. Will cap spot price to On Demand Price"
    BID_PRICE=$CURRENT_ON_DEMAND_PRICE
  fi

  echo "Checking for EMR roles"
  if [ $(aws iam list-roles | grep RoleName | grep EMR | grep DefaultRole | wc -l) -ne 2 ]; then
    echo "Creating default EMR roles" 
    aws emr create-default-roles 
  fi

  aws emr create-cluster --name SparkJupyter \
    --release-label emr-4.3.0 \
    --applications Name=Spark \
    --ec2-attributes KeyName=$AWS_KEY_PAIR_NAME,SubnetId=$PUBLIC_SUBNET_ID,AdditionalMasterSecurityGroups=[$CUSTOM_SECURITY_GROUP_ID] \
    --instance-groups InstanceGroupType=MASTER,InstanceType=$INSTANCE_TYPE,InstanceCount=1,BidPrice=$BID_PRICE \
    InstanceGroupType=CORE,BidPrice=$BID_PRICE,InstanceType=$INSTANCE_TYPE,InstanceCount=$SLAVES_INSTANCE_COUNT \
    --use-default-roles \
    --termination-protected \
    --bootstrap-action Path=s3://ltsai/smu-talk-8mar2016/install-jupyter.sh
}

create_vpc
create_emr
