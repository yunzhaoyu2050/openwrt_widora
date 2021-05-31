### 开发记录 2021.05.28

#### 生成补丁文件：

  diff -ruN option.c option_new.c > 999-kernel-option-add-new-dev.patch

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

make HOST_CC="gcc -m32" CROSS=/home/user/zhaoyu/lorawan/kernel/openwrt_widora/staging_dir/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_uClibc-0.9.33.2/bin/mipsel-openwrt-linux-uclibc-

r = uv__dup3(oldfd, newfd, O_CLOEXEC);