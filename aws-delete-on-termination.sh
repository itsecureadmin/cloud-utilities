#!/bin/bash

#
# Audit instances to set all volumes to deleteOnTermination
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

#
# loop through each instance
#
for instanceid in $(aws ec2 describe-instances --output text | egrep -i instances | ${sed} -n 's/.*\(i-[0-9a-z]\+\).*/\1/gp')
do
  IFS='
'
  result=$(aws ec2 describe-instance-attribute --instance-id ${instanceid} --attribute blockDeviceMapping --output text)
  for line in ${result}
  do

    case "${line}" in
    BLOCKDEVICEMAPPINGS*)
      device=$(echo ${line} | awk '{print $2}')
      ;;
    EBS*)
      volume=$(echo ${line} | awk '{print $5}')
      update=$(echo ${line} | awk '{print $3}')
      ;;
    esac

    if [[ -n "${device}" && -n "${volume}" && "${update}" == "False" ]]
    then
      echo "instance: ${instanceid}"
      echo "device:   ${device}"
      echo "volume:   ${volume}"

      # perform the modification
      aws ec2 modify-instance-attribute --instance-id ${instanceid} --block-device-mappings "[{\"DeviceName\": \"${device}\",\"Ebs\":{\"DeleteOnTermination\":true}}]"

      # cleanup variables to start fresh
      unset volume
      unset update
      unset device
    fi


    if [ $? -gt 0 ]
    then
      echo "command failed for ${instanceid}"
    fi
  done

  unset IFS
done

exit 0;
