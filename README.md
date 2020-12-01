# cloud-utilities
Various utilities to make cloud life easier.

Backup all EC2 instances by creating an AMI, without reboot:
- aws-backup.sh

For all EC2 instances, iterate through all attached devices and ensure delete on termination is set:
- aws-delete-on-termination.sh

For all EBS snapshots, ensure that any snapshots that were created as part of an AMI that no longer exists, delete them:
- aws-snapshot-audit.sh


