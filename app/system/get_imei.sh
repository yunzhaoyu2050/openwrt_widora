#!/bin/bash
#
# gei imei
#

devPath="/dev/ttyUSB1"

AT_CGSN_CMD="AT+CGSN"
atcgsnRespCount=0
ATE1_CMD="ATE1"
AT_CMD="AT"
atRespCount=0

status="INIT"
lastResp=""
cat $devPath | while read line; do
  echo "get line: $line"
  lastResp=$line
  resp=""
  echo $line | grep -i "OK" && resp="OK"
  echo $line | grep -i "ERROR" && resp="ERROR"

  case $status in
  "INIT")
    echo $ATE1_CMD >>$devPath

    if [[ $atRespCount -le 2 ]] && [[ "$resp" == "OK" ]]; then
      status="GIMEI"
    fi
    if [[ $atRespCount -gt 2 ]]; then
      atRespCount=0
    fi
    atRespCount = $(expr $atRespCount + 1)
    ;;
  "GIMEI")
    echo $AT_CGSN_CMD >>$devPath
    # 获取imei
    if [[ $atcgsnRespCount -le 4 ]] && [[ "$resp" == "OK" ]]; then
      status="END"
    fi
    if [[ $atcgsnRespCount -gt 4 ]]; then
      atcgsnRespCount=0
    fi
    atcgsnRespCount = $(expr $atcgsnRespCount + 1)
    ;;
  "END")
    echo "get imei end"
    exit 0
    ;;
  *) ;;
  esac
done
