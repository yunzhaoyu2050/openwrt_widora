#!/bin/sh

usage() {
  echo "usage:"
}

cmd=

CheckInputArgc() {
  if [ "$1" == "up" ];then
    cmd="high"
  elif [ "$1" == "down" ];then
    cmd="low"
  else
    echo cmd is other, please check.
    return 1
  fi
  return 0
}
 
ec20xPowerPin=37
CreateEc20xPowerGpio() {
  if [ ! -f /sys/class/gpio/gpio$ec20xPowerPin/direction ];then
    echo $ec20xPowerPin > /sys/class/gpio/export
  else
    echo "gpio $ec20xPowerPin is already exists."
  fi
}
DelEc20xPowerGpio() {
  # if [ ! -f /sys/class/gpio/gpio$ec20xPowerPin/direction ];then
    echo $ec20xPowerPin > /sys/class/gpio/unexport
  # else
  #   echo "gpio $ec20xPowerPin is already exists."
  # fi
}
PowerHighEc20x() {
  echo high > /sys/class/gpio/gpio$ec20xPowerPin/direction
  return $?
}
PowerLowEc20x() {
  echo low > /sys/class/gpio/gpio$ec20xPowerPin/direction
  return $?
}

# main

CreateEc20xPowerGpio
if [ $? -ne 0 ];then
  echo "export $ec20xPowerPin gpio failed, please check."
  exit 1
fi

CheckInputArgc $1
if [ $? -ne 0 ];then
  exit 4
fi

if [ $cmd == "high" ];then
  PowerHighEc20x
  if [ $? -eq 0 ];then
    echo wait 3s...
    sleep 2
    if [ -f /dev/ttyUSB0 ] && [ -f /dev/ttyUSB1 ];then
      echo ec20x power on ...
    else
      echo ec20x pull high again...
      PowerLowEc20x; sleep 1
      PowerHighEc20x
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
elif [ $cmd == "low" ];then
  PowerLowEc20x; sleep 1
  if [ $? -ne 0 ];then
    echo ec20x power down failed...
    exit 2
  fi
  DelEc20xPowerGpio
  echo ec20x power down...
fi
