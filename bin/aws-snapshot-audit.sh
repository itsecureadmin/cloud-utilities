#!/bin/bash

#
# Delete snapshots associated with AMIs that have been deleted.
#
# - note that any snapshot that *is* being used by a current AMI
#   will fail to delete
#

if [[ -f /usr/local/bin/gsed ]]
then
  sed=/usr/local/bin/gsed
else
  sed=sed
fi

images=$(aws ec2 describe-images --owners self --output text --query 'Images[*].[ImageId]')
invalid_count=0
valid_count=0

IFS='
'

for snapshot in $(aws ec2 describe-snapshots --owner-ids self --output text --query 'Snapshots[*].[SnapshotId,Description]')
do
  snapshotid=$(echo ${snapshot} | awk '{print $1}')
  match=''
  ami_pattern="ami-[a-z0-9]+"

  for word in ${snapshot}
  do
    [[ ${word} =~ ${ami_pattern} ]]
    if [[ ${BASH_REMATCH[0]} ]]
    then
      match="${BASH_REMATCH[0]}"
      continue;
    fi
  done

  amiid=${match}

  if [ -z ${amiid} ]
  then
    # not related to AMI
    continue;
  fi

  valid=$(echo ${images} | egrep -c ${amiid})
  if [ "${valid}" -gt 0 ]
  then
    valid_count=$((valid_count+1))
  else
    echo "Deleting orphaned snapshot ${snapshotid} which belongs to non-existent AMI ${amiid}"
    invalid_count=$((invalid_count+1))
    aws ec2 delete-snapshot --snapshot-id ${snapshotid}
  fi

done

unset IFS

echo "Valid snapshots:  ${valid_count}"
echo "Invalid snapshots:  ${invalid_count}"

exit 0;
