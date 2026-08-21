# LVM-Based Dynamic Storage Automation on AWS EC2

Hands-on project demonstrating how to build an LVM-backed storage volume on
AWS EC2, extend it **live with zero downtime** when it fills up, and
automatically alert on high disk usage.

## Why this project

Most freshers can explain LVM in theory. This project proves it hands-on:
provisioning real AWS infrastructure, building a PV → VG → LV stack, filling
it to capacity, and growing it live — the exact skill gap between
"knows the commands" and "has done it under pressure."

## Architecture

```
EC2 Instance (Amazon Linux 2 / Ubuntu)
   └── EBS Volume (/dev/xvdf)
         └── Physical Volume (pvcreate)
               └── Volume Group: data_vg (vgcreate)
                     └── Logical Volume: data_lv (lvcreate)
                           └── Filesystem: XFS (mounted at /data)
                                 └── disk_alert.sh (cron, monitors usage)
```

## Prerequisites

- AWS account with an EC2 instance running (Amazon Linux 2 / Ubuntu 22.04)
- IAM permissions to create/modify EBS volumes
- SSH access to the instance

## Steps

### 1. Launch EC2 and attach an EBS volume
Created a small EBS volume (4 GiB) in the same AZ as the instance and
attached it as `/dev/sdf` (appears as `/dev/xvdf` on the instance).

![EBS volume attached](screenshots/01-ebs-attached.png)

### 2. Build the LVM stack
```bash
sudo pvcreate /dev/xvdf
sudo vgcreate data_vg /dev/xvdf
sudo lvcreate -l 100%FREE -n data_lv data_vg
sudo mkfs.xfs /dev/data_vg/data_lv
sudo mkdir -p /data
sudo mount /dev/data_vg/data_lv /data
echo "/dev/data_vg/data_lv /data xfs defaults 0 0" | sudo tee -a /etc/fstab
```
![LVM stack created](screenshots/02-lvm-stack.png)

### 3. Fill /data close to capacity
```bash
sudo fallocate -l 3.5G /data/testfile
df -hT /data
```
**Before state:**
![Before extend](screenshots/03-before-df.png)

### 4. Extend live — zero downtime
Modified the EBS volume size from the AWS Console (4 GiB → 8 GiB), then:
```bash
sudo pvresize /dev/xvdf
sudo lvextend -l +100%FREE /dev/data_vg/data_lv
sudo xfs_growfs /data
df -hT /data
```
**After state — same mount, no unmount, no downtime:**
![After extend](screenshots/04-after-df.png)

### 5. Automated disk monitoring
`disk_alert.sh` checks `/data` usage and fires an alert (log / email / Slack)
when usage crosses 80%. Deployed via cron:
```bash
*/5 * * * * /opt/scripts/disk_alert.sh /data 80 >> /var/log/disk_alert.log 2>&1
```
![Disk alert triggered](screenshots/05-alert-triggered.png)

## Key takeaways

- LVM lets you grow storage **without unmounting or rebooting**.
- EBS volume modification is online — the instance sees the new size
  immediately, but LVM/filesystem must be told to use it (`pvresize`,
  `lvextend`, `xfs_growfs`/`resize2fs`).
- Combining infra automation (AWS) with OS-level tooling (LVM + bash) is
  exactly what real SRE/DevOps work looks like.

## Files in this repo

| File | Purpose |
|---|---|
| `disk_alert.sh` | Monitors a mount point and alerts at a configurable threshold |
| `screenshots/` | Terminal + AWS console screenshots documenting each step |

## Next steps / possible extensions

- Trigger `disk_alert.sh` alerts via SNS instead of/in addition to Slack
- Automate the EBS resize itself via AWS CLI + a Lambda triggered by
  CloudWatch alarm on disk usage
- Add a Terraform version of the EC2 + EBS provisioning
