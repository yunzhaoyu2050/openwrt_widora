#!/bin/bash
# openwrt build
export STAGING_DIR=/home/user/zhaoyu/lorawan/kernel/openwrt_widora/staging_dir/
export PATH=$PATH:$STAGING_DIR/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_uClibc-0.9.33.2/bin

../../staging_dir/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_glibc-2.21/bin/mipsel-openwrt-linux-gcc -O0 -Wall -g ttySx_rs485_test.c -o ttySx_rs485_test
../../staging_dir/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_glibc-2.21/bin/mipsel-openwrt-linux-gcc -O0 -Wall -g change_touart2.c -o change_touart2