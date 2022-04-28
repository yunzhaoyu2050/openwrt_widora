# MIT License
#
# Copyright (c) 2021 yunzhaoyu2050
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#!/bin/bash

#
# Content: Engineering test
# Function:
# 1. Back up the remote device partition firmware, and transfer the compressed backup file to the current PC working machine (remote device firmware backup)
# 2. Transfer the compressed backup file to the remote device and write it to the designated partition (remote device upgrade)
#

# 1 from: https://openwrt.org/docs/guide-user/installation/generic.backup
set -e

die() {
  echo "${@}"
  exit 2
}

OUTPUT_FILE="mc7628_mtdx_bin_backup.tar.gz"
OPENWRT_HOSTNAME="root"
OPENWRT="192.168.1.1"
TMPDIR=$(mktemp -d)
# echo "TMPDIR:$TMPDIR"
BACKUP_DIR="${TMPDIR}/mc7628_mtdx_bin_backup"
SSH_CONTROL="${TMPDIR}/ssh_control"
SSH_CMD=

OPENWRT_DEV_PASSWD=

cleanup() {
  set +e
  echo "Closing master SSH connection"
  "${SSH_CMD[@]}" -O stop
  echo "Removing temporary backup files"
  rm -r "${TMPDIR}"
}

partition_backup() {
  mkdir -p "${BACKUP_DIR}"
  trap cleanup EXIT

  # Open master ssh connection, to avoid the need to authenticate multiple times
  echo "Opening master SSH connection"
  ssh -o "ControlMaster=yes" -o "ControlPath=${SSH_CONTROL}" -o "ControlPersist=10" -n -N "${OPENWRT_HOSTNAME}@${OPENWRT}"

  # This is the command we'll use to reuse the master connection
  SSH_CMD=(ssh -o "ControlMaster=no" -o "ControlPath=${SSH_CONTROL}" -n "${OPENWRT_HOSTNAME}@${OPENWRT}")

  # List remote mtd devices from /proc/mtd. The first line is just a table
  # header, so skip it (using tail)
  "${SSH_CMD[@]}" 'cat /proc/mtd' | tail -n+2 | while read; do
    MTD_DEV=$(echo ${REPLY} | cut -f1 -d:)
    MTD_NAME=$(echo ${REPLY} | cut -f2 -d\")
    echo "Backing up ${MTD_DEV} (${MTD_NAME})"
    # It's important that the remote command only prints the actual file
    # contents to stdout, otherwise our backup files will be corrupted. Other
    # info must be printed to stderr instead. Luckily, this is how the dd
    # command already behaves by default, so no additional flags are needed.
    "${SSH_CMD[@]}" "dd if='/dev/${MTD_DEV}ro'" >"${BACKUP_DIR}/${MTD_DEV}_${MTD_NAME}.bin" || die "dd failed, aborting..."
  done

  # Use gzip and tar to compress the backup files
  echo "Compressing backup files to \"${OUTPUT_FILE}\""
  (cd "${TMPDIR}" && tar czf - "$(basename "${BACKUP_DIR}")") >"${OUTPUT_FILE}" || die 'tar failed, aborting...'

  # Clean up a little earlier, so the completion message is the last thing the user sees
  cleanup
  # Reset signal handler
  trap EXIT

  echo -e "\nMTD backup complete. Extract the files using:\ntar xzf \"${OUTPUT_FILE}\""
}

# 2
UPGRADE_FILE=${OUTPUT_FILE}
partition_upgrade() {
  trap cleanup EXIT
  [ -d .upg_tmp/ ] && rm -rf .upg_tmp/
  mkdir .upg_tmp/
  tar -xzf $UPGRADE_FILE -C .upg_tmp/

  local upFileNmNoSuffix=$(echo ${UPGRADE_FILE} | awk -F "/" '{print $NF}' | sed 's/.tar.gz//')
  local partNmArrTmp=$(ls .upg_tmp/${upFileNmNoSuffix}/ | sed 's/.bin//')

  echo $"Opening master SSH connection"
  # ssh -o "ControlMaster=yes" -o "ControlPath=${SSH_CONTROL}" -o "ControlPersist=10m" -n -N "${OPENWRT_HOSTNAME}@${OPENWRT}"
  /usr/bin/expect <<EOF
  set time 30
  spawn ssh -o "ControlMaster=yes" -o "ControlPath=${SSH_CONTROL}" -o "ControlPersist=10m" -n -N "${OPENWRT_HOSTNAME}@${OPENWRT}"
  expect {
    "*yes/no" { send "yes\r"; exp_continue }
    "*password:" { send "${OPENWRT_DEV_PASSWD}\r" }
  }
  expect eof
EOF
  SSH_CMD=(ssh -o "ControlMaster=no" -o "ControlPath=${SSH_CONTROL}" -n "${OPENWRT_HOSTNAME}@${OPENWRT}")
  "${SSH_CMD[@]}" 'rm -rf /root/.upgrade_tmp/'
  "${SSH_CMD[@]}" 'mkdir -p /root/.upgrade_tmp/'

  echo "Transfer upgrade files(${UPGRADE_FILE})"
  # scp -r ".upg_tmp/${upFileNmNoSuffix}/" "${OPENWRT_HOSTNAME}@${OPENWRT}:/root/.upgrade_tmp/"
  /usr/bin/expect <<EOF
  set time 30
  spawn scp -r ".upg_tmp/${upFileNmNoSuffix}/" "${OPENWRT_HOSTNAME}@${OPENWRT}:/root/.upgrade_tmp/"
  expect {
    "*yes/no" { send "yes\r"; exp_continue }
    "*password:" { send "${OPENWRT_DEV_PASSWD}\r" }
  }
  expect eof
EOF

  echo "Upgrade remote device partition"
  echo $partNmArrTmp | while read line; do
    local tmpNm=$(echo $line | sed 's/mtd[0-9]_//')
    # "${SSH_CMD[@]}" "mtd -r write /root/.upgrade_tmp/${upFileNmNoSuffix}/$partNmArrTmp.bin $tmpNm" || die 'mtd write failed, aborting...'
    local MTD_DEV=$(echo $partNmArrTmp | awk -F '_' '{print $1}')
    echo "MTD_DEV:${MTD_DEV}"
    "${SSH_CMD[@]}" "dd of=/dev/mtd4 if=/root/.upgrade_tmp/${upFileNmNoSuffix}/$partNmArrTmp.bin" || die 'dd write failed, aborting...' # bug at if or of
  done
  "${SSH_CMD[@]}" 'rm -rf /root/.upgrade_tmp/'

  echo "Upgrade remote device partition done, then reboot .after 7s"
  rm -rf .upg_tmp/
  "${SSH_CMD[@]}" 'reboot -d 7'

  cleanup
  trap EXIT
}

help() {
  echo "usage:"
  echo "-h             help."
  echo "-b             backup remote device partition info to a compressed file."
  echo "-u             upgrade remote device partition."
  echo "-i x.x.x.x     remote device ip addr,(e.g:-i 192.168.11.1)."
  echo "-n x           remote device hostname,(e.g:-n admin)."
  echo "-f xxx.tar.gz  -b -f is backup file, -u -f is upgrade file."
  echo ""
  echo "  e.g:upgade file, ./rdevimgctl.sh -u -i 192.168.11.1 -f mc7628_mtdx_bin_backup.tar.gz -n root"
  echo "  e.g:backup file, ./rdevimgctl.sh -b -i 192.168.11.1 -f mc7628_mtdx_bin_backup.tar.gz -n root"
}

# main
CMD=
TMP_FILE=
while getopts "hbui:f:n:" opt; do
  case $opt in
  h)
    help
    exit 1
    ;;
  b)
    CMD="BK"
    ;;
  u)
    CMD="UG"
    ;;
  i)
    OPENWRT=$OPTARG
    ;;
  n)
    OPENWRT_HOSTNAME=$OPTARG
    ;;
  f)
    TMP_FILE=$OPTARG
    ;;
  \?)
    echo "Invalid option: -$OPTARG"
    help
    exit -1
    ;;
  esac
done

read -s -p "${OPENWRT_HOSTNAME}@${OPENWRT}'s password:" OPENWRT_DEV_PASSWD
echo -e "\r\n"

case $CMD in
"BK")
  OUTPUT_FILE=$TMP_FILE
  partition_backup
  ;;
"UG")
  UPGRADE_FILE=$TMP_FILE
  partition_upgrade
  ;;
*) ;;
esac
