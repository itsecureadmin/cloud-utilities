#!/bin/bash

#
# Delete EBS volumes not associated with EC2 instances.
#
# - note that any EBS volume that *is* being used by a current instance
#   will fail to delete
#

if [[ -f /usr/local/bin/gsed ]]
then
  sed=/usr/local/bin/gsed
else
  sed=sed
fi

IFS='
'
volume_count=0

# FYI - for volume in $(aws ec2 describe-volumes --output text --query 'Volumes[*].[VolumeId,State]' --filters "Name=status,Values=available")
for volume in $(aws ec2 describe-volumes --output text --query 'Volumes[*].[VolumeId]' --filters "Name=status,Values=available")
do

  echo "Deleting orphaned volume ${volume} which is not attached."
  aws ec2 delete-volume --volume-id ${volume}
  volume_count=$((volume_count+1))

done

unset IFS

echo "Deleted volumes:  ${volume_count}"

exit 0;
