#!/bin/bash -x

#
# Delete snapshots associated with AMIs that have been deleted.
#

if [[ -f /usr/local/bin/gsed ]]
then
  sed=/usr/local/bin/gsed
else
  sed=sed
fi

#
# get the owner id
#
owner_ids=$(aws iam get-user --output text | ${sed} 's/.*iam::\(.*\):user.*/\1/g')

images=$(aws ec2 describe-images --owners ${owner_ids} --output text | ${sed} -n 's/.*\(ami-[a-zA-Z0-9]\+\).*/\1/p')
invalid_count=0
valid_count=0

IFS='
'

for snapshot in $(aws ec2 describe-snapshots --owner-ids ${owner_ids} --output text)
do
  snapshotid=$(echo ${snapshot} | ${sed} -n 's/.*\(snap-[a-z0-9]\+\).*/\1/p')
  amiid=$(echo ${snapshot} | ${sed} -n 's/.*\(ami-[a-z0-9]\+\).*/\1/p')

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
