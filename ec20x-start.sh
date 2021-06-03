#!/bin/sh
 
ec20xPowerPin=37
# main
if [ ! -d /sys/class/gpio/gpio$ec20xPowerPi ];then
  echo $ec20xPowerPin > /sys/class/gpio/export
else
  echo $ec20xPowerPin is already exists.
fi
if if [ $? -ne 0 ];then
  echo export $ec20xPowerPin gpio failed, please check.
  exit 1
fi

echo high > /sys/class/gpio/gpio$ec20xPowerPin/direction
if [ $? -eq 0 ];then
  if [ -f /dev/ttyUSB0 ] && [ -f /dev/ttyUSB1 ];then
    echo ec20x power on ...
  else
    echo ec20x pull high again...
    echo low > /sys/class/gpio/gpio$ec20xPowerPin/direction; sleep 1
    echo high > /sys/class/gpio/gpio$ec20xPowerPin/direction
    if [ $? -ne 0 ];then
      echo ec20x power on failed...
      exit 2
    else
      if [ -f /dev/ttyUSB0 ] && [ -f /dev/ttyUSB1 ];then
        echo ec20x power on ...
      fi
    fi
  fi
else
  echo ec20x power on failed...
  exit 3
fi

