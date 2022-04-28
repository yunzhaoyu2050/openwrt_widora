## Openwrt Auxiliary Tools

version:v0.0.1

#### Accessibility script tools

#### 1.rdevimgctl.sh

Content: Engineering test

Function:

1. Back up the remote device partition firmware, and transfer the compressed backup file to the current PC working machine (remote device firmware backup)

2. Transfer the compressed backup file to the remote device and write it to the designated partition (remote device upgrade)

usage:

  e.g: upgade file
```
  ./rdevimgctl.sh -u -i 192.168.11.1 -f mc7628_mtdx_bin_backup.tar.gz -n root
```
  e.g: backup file
```
  ./rdevimgctl.sh -b -i 192.168.11.1 -f mc7628_mtdx_bin_backup.tar.gz -n root
```