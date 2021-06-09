### 开发记录 2021.05.28

#### 生成补丁文件：

  diff -ruN option.c option_new.c > 999-kernel-option-add-new-dev.patch
  diff -ruN mt7620.c.old mt7620.c > 999-kernel-mt7620-add-new-dev.patch
  diff -ruN 8250_core.c.old 8250_core.c > 999-kernel-8250_core-add-new-dev.patch
#### git 相关命令：

  git submodule update --init --recursive

#### openwrt编译相关命令:

  下载后编译前一定要执行以下两句脚本命令！！！

  ./scripts/feeds update -a

  ./scripts/feeds install -a

  make menuconfig

#### 内核打补丁相关：

  补丁获取目录：target/linux/generic/patches-3.18/ 此目录编译的时候会自动将补丁打入

  make target/linux/clean V=99

  make target/linux/prepare V=99

  make target/linux/compile V=s

  编译内核文件路径：build_dir/target-mipsel_24kec+dsp_uClibc-0.9.33.2/linux-ramips_mt7688/linux-3.18.29/
  
  build_dir/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_uClibc-0.9.33.2/linux-3.18.29 而这个路径好像并没有什么作用

#### 内核dts文件目录：

  dts目录：target/linux/ramips/dts/

#### 文件系统相关配置文件

  主机名称文件：package/base-files/files/etc/config/system

#### luvi
  CFLAGS="$(TARGET_CFLAGS) -Wall -ldl" \
	LDFLAGS="$(TARGET_LDFLAGS)"

  make HOST_CC="gcc -m32" CROSS=mipsel-openwrt-linux-uclibc-

  export STAGING_DIR=/home/user/zhaoyu/lorawan/kernel/openwrt_widora/staging_dir/
  
  export PATH=$PATH:$STAGING_DIR/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_uClibc-0.9.33.2/bin
  export PATH=$PATH:$STAGING_DIR/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_glibc-2.21/bin

  make tiny CFLAGS="-ldl" CC=mipsel-openwrt-linux-gcc

  make HOST_CC="gcc -m32" CROSS=/home/user/zhaoyu/lorawan/kernel/openwrt_widora/staging_dir/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_uClibc-0.9.33.2/bin/mipsel-openwrt-linux-uclibc-

  r = uv__dup3(oldfd, newfd, O_CLOEXEC);

  rs485部分代码：
```
          ret = dw8250_probe_rs485(uart, uart->port.dev->of_node); // add by zhaoyu for rs485
          if (ret < 0)
              return -ENOMEM;
          uart->rs485_config = dw8250_config_rs485;
```
  关闭串口控制台
  将$(TOPDIR)/target/linux/ramips/base-files/etc/inittab文件里的下面一句注释掉

  ::askconsole:/bin/ash --login
  $ vi $(TOPDIR)/target/linux/ramips/base-files/etc/inittab
  ::sysinit:/etc/init.d/rcS S boot
  ::shutdown:/etc/init.d/rcS K shutdown
  #::askconsole:/bin/ash --login
  关闭内核打印
  在$(TOPDIR)/package/base-files/files/etc/config/system文件添加以下两句

  option 'conloglevel' '1'
  option 'kconloglevel' '1'
  $ vi $(TOPDIR)/package/base-files/files/etc/config/system
  复制代码
  config system
          option 'conloglevel' '1'
          option 'kconloglevel' '1'
          option hostname OpenWrt
          option timezone UTC

  config timeserver ntp
          list server     0.openwrt.pool.ntp.org
          list server     1.openwrt.pool.ntp.org
          list server     2.openwrt.pool.ntp.org
          list server     3.openwrt.pool.ntp.org
          option enable_server 0
  禁止kernel的输出较简单，重新编译镜像前，在make kernel_menuconfig时，选择Kernel hacking ----> 找到Early printk，将其取消选中，保存设置，make编译镜像即可。 http://docs.blackfin.uclinux.org/doku.php?id=linux-kernel:debug:early_printk
  其他方法（在wr703n中均测试失败，网络上有人测试成功）：
  1）在编译目录下找到./target/linux/<对应的平台>/config-3.3，找到文件中的CONFIG_CMDLINE去掉console=ttyATH0,115200，或者改成console=none，然后重新编译镜像。
  2）因为kernel的message都是printk打印的，可以提高console的message打印级别，将/proc/sys/kernel/printk中第一个值改成0或者1：
  echo 0 > /proc/sys/kernel/printk
  cat /proc/sys/kernel/printk
  0   4   1   7

  或者在/etc/config/system下添加
  option 'conloglevel' '1'
  option 'kconloglevel' '1'

  如果使用了后面的设置，前面的printk中的第一个值会被强制设置为system中的值。

  ffmpeg功能：
  > Multimedia
    <*> ffmpeg.................................................... FFmpeg program

  openssl功能：
  > Utilities
    <*> cryptsetup.................................................... Cryptsetup
    <*> cryptsetup-openssl..................... Cryptsetup (with openssl support)
    <*> openssl-util........................... Open source SSL toolkit (utility)

  spi测试工具：
  > Utilities
    <*> spidev-test.......................................... SPI testing utility 

修改banner.
  临时修改
  /etc/banner

  永久修改
  openwrt_widora/package/base-files/files/etc/banner

1.4g 电源口 boot中启动， kernel-led模拟。gpio
2.glibc getaddrinfo_a -> uclibc 

# t2n 安装至 /usr/sbin/ 之后整理验证
