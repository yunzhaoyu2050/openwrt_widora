#!/bin/sh

case $1 in
add)
  mkdir -p $2
  mount -t vfat -o iocharset=utf8,rw,sync,umask=0000,dmask=0000,fmask=0000 /dev/$3 $2
  # mount -t vfat /dev/$2 /media
  ;;

remove)
  umount $2
  rm -rf $2
  ;;
esac
