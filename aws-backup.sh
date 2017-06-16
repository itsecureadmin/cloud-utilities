#!/bin/bash

#
# This script will create an AMI from each active Ec2 instance without reboot.
#
# The script will then prune AMIs older than 14 days if the name in the EC2 tag matches the
# following format - this script creates AMIs in this format:
#
# ${ec2_Name_tag}-${date +%s}
#
# ie:  web-app-server-1497647267
#

if [[ -f /usr/local/bin/gsed ]]
then
  sed=/usr/local/bin/gsed
else
  sed=sed
fi

#
# get my account ID
#
owner_ids=$(aws iam get-user --output text | ${sed} 's/.*iam::\(.*\):user.*/\1/g')

instanceID=''
instanceTAG=''

timeepoch=$(date +%s)
prunedays=14

#
# expects input like 
# ${account_id}/${instance_name}-${epoch created date}
#
# and should output age in days
#
get_object_age() {

  imageID=$1

  #
  # parse the epoch timestamp from the end of the AMI name
  # - should be last 11 characters
  #
  imageepoch=${imageID: -10}

  if [[ "${imageepoch}" =~ ^[0-9]+$ ]]
  then
    timediff=$(( ${timeepoch}-${imageepoch} ))
    timediff=$(( ${timediff} / 60 ))
    timediff=$(( ${timediff} / 60 ))
    timediff=$(( ${timediff} / 24 ))
  else
    # be sure that imageepoch is a number or default to no difference
    # so we do not delete the AMI
    timediff=0
  fi

  echo ${timediff}
  
}

#
# take images of each EC2 instance
#
for line in $(aws ec2 describe-tags --output text | egrep Name | egrep instance | awk '$4 ~ "instance" {print $3, $5}')
do

  if [ $(echo ${line} | egrep -c '^i-') -gt 0 ] 
  then
    instanceID=${line}
  else
    instanceTAG=${line}
  fi

  if [[ ${instanceID} && ${instanceTAG} ]]
  then
    echo "creating image of ${instanceTAG} (${instanceID})"

    # create the image w/ ephemeral storage
    aws ec2 create-image                                                                             \
           --instance-id ${instanceID}                                                               \
           --name ${instanceTAG}-${timeepoch}                                                        \
           --description ${instanceTAG}-${timeepoch}                                                 \
           --block-device-mappings "[{\"DeviceName\": \"/dev/sdb\",\"VirtualName\":\"ephemeral0\"}]" \
           --no-reboot

    instancdID=''
    instanceTAG=''
  fi

done

#
# prune old EC2 images
#
for image in $(aws ec2 describe-images --owners ${owner_ids} --output text | awk '/IMAGE/ {print $4, $7}')
do

  if [ $(echo ${image} | egrep -c '^ami-') -gt 0 ]
  then
    imageID=${image}
  else
    imageName=${image}
  fi

  if [[ ${imageID} && ${imageName} ]]
  then

    imageAge=$(get_object_age "${imageName}")

    # if image age is greater than prunedays, un-register
    if [[ ${imageAge} -gt ${prunedays} ]]
    then
      echo "deregistering:  ${imageID}"
      aws ec2 deregister-image --image-id ${imageID}
    fi

    imageID=''
    imageName=''
  fi

done

exit 0 ;
