#!/bin/bash

#
# Author: Josh Miller, ITSA Consulting, LLC
#

EKS_VERSION=1.21
EKS_REGION='us-west-2'

#
# before running this script, update your launch template with the latest EKS AMI
#

#
# retrieve the latest EKS optimized AMI ID from the SSM Parameter Store
# - https://docs.aws.amazon.com/eks/latest/userguide/retrieve-ami-id.html
#
UPDATED_AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/eks/optimized-ami/${EKS_VERSION}/amazon-linux-2/recommended/image_id \
  --region ${EKS_REGION} \
  --query "Parameter.Value" \
  --output text)

echo "latest eks ${EKS_VERSION} ami id:  ${UPDATED_AMI_ID}"

if [[ -z "${UPDATED_AMI_ID}" ]]
then
  echo "No AMI found - exiting."
  exit 1;
fi

# get all eks nodes
nodes=$(kubectl get nodes -o jsonpath="{.items[*].metadata.name}")

#
# iterate through node list and recycle each node that is not using the latest AMI
#
for node in ${nodes[@]}
do
  echo "node: ${node}"
  ec2_instance_id=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].{Instance:InstanceId}' --filters Name=private-dns-name,Values=${node} --output text)
  echo "ec2 instance ID: ${ec2_instance_id}"

  INSTANCE_AMI_ID=$(aws ec2 describe-instances \
    --instance-ids ${ec2_instance_id} \
    --query 'Reservations[*].Instances[*].ImageId' \
    --output text)
  echo "ec2 AMI ID: ${INSTANCE_AMI_ID}"

  if [[ -z "${INSTANCE_AMI_ID}" ]]
  then
    echo "No EC2 instance found - exiting."
    exit 1;
  fi

  # check to see if the node has already been updated, otherwise, update
  if [[ "${INSTANCE_AMI_ID}" != "${UPDATED_AMI_ID}" ]]
  then

    echo "draining node:  ${node}"
    kubectl drain --ignore-daemonsets --delete-emptydir-data --force ${node}
    sleep 120
    echo "deleting node:  ${node}"
    kubectl delete node ${node}
    sleep 120
    echo "terminating ec2 instance:  ${ec2_instance_id}"
    aws ec2 terminate-instances --instance-id ${ec2_instance_id}

    sleep 600
  fi

done
