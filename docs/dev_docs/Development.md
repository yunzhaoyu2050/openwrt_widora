# Openwrt 开发记录  

- `开发环境系统: ubuntu16.04`
- `开发环境代码编辑器: vscode`
- `目标系统类型: Openwrt`
- `目标芯片类型: Mt7628`
- 虚拟机Mt7628-Gps扩展板工程存储路径：
- 虚拟机Mt7628-Lorawan扩展板工程存储路径：

## 开发过程

### 默认密码： mcxa@.2204

### 编译指导

​	参考widora的编译指导 Link：https://mangopi.cc/compile

### Openwrt工程常用命令

### 编译命令

1. ./scripts/feeds update -a
2. ./scripts/feeds install -a
3. make menuconfig

**针对Gps扩展的主板选择**：

​	*单网口网关* (mc7628_gps board 16MB flash/64MB ram base packages)

```shell
16MB+64MB配置(BIT5,16MB FLASH)：
Target System: Ralink RT288x/RT3xxx 
  Subtarget: MT7628 based boards 
     Target Profile: MC7628_G 
```

4. make V=s

## Openwrt Kernel开发常用命令

### 编译命令

1.  make target/linux/clean V=99
2. make target/linux/prepare V=99
3. make target/linux/compile V=s

### 补丁命令

1. diff -ruN 8250_core.c.old 8250_core.c > 999-kernel-8250_core-add-new-dev.patch

- 将修改过后的补丁文件存在`target/linux/generic/patches-3.18/`文件夹下，之后编译的时候回自动将补丁打入。	

- 编译之后的内核文件路径，E.G：`build_dir/target-mipsel_24kec+dsp_uClibc-0.9.33.2/linux-ramips_mt7688/linux-3.18.29/`

  `build_dir/toolchain-mipsel_24kec+dsp_gcc-4.8-linaro_uClibc-0.9.33.2/linux-3.18.29` 而这个路径好像并没有什么作用

### 内核相关文件

Dts目录：`target/linux/ramips/dts/`

## Openwrt 常用配置

### 主机名称

文件路径：`package/base-files/files/etc/config/system`

### 关闭内核打印

  在$(TOPDIR)/package/base-files/files/etc/config/system文件添加以下两句

```
 option 'conloglevel' '1'
 option 'kconloglevel' '1'
```

  `$ vi $(TOPDIR)/package/base-files/files/etc/config/system`

*复制代码*

```
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
```

 禁止kernel的输出较简单，重新编译镜像前，在make kernel_menuconfig时，选择Kernel hacking ----> 找到Early printk，将其取消选中，保存设置，make编译镜像即可。
  其他方法（在wr703n中均测试失败，网络上有人测试成功）：
  1）在编译目录下找到./target/linux/<对应的平台>/config-3.3，找到文件中的CONFIG_CMDLINE去掉console=ttyATH0,115200，或者改成console=none，然后重新编译镜像。
 2）因为kernel的message都是printk打印的，可以提高console的message打印级别，将/proc/sys/kernel/printk中第一个值改成0或者1：

```shell
  echo 0 > /proc/sys/kernel/printk
  cat /proc/sys/kernel/printk
  0   4   1   7
```

  或者在/etc/config/system下添加

```
  option 'conloglevel' '1'
  option 'kconloglevel' '1'
```

  如果使用了后面的设置，前面的printk中的第一个值会被强制设置为system中的值。

### 关闭串口控制台

  将$(TOPDIR)/target/linux/ramips/base-files/etc/inittab文件里的下面一句注释掉

```
  ::askconsole:/bin/ash --login
```

  $ vi $(TOPDIR)/target/linux/ramips/base-files/etc/inittab

```
  ::sysinit:/etc/init.d/rcS S boot
  ::shutdown:/etc/init.d/rcS K shutdown
  #::askconsole:/bin/ash --login
```

### 修改banner

-   临时修改：/etc/banner
-   永久修改：openwrt_widora/package/base-files/files/etc/banner

### wifi测试

参考链接：https://mangopi.cc/wifi

- 扫描周围AP列表，命令：aps
- 链接其他wifi，命令：wifimode apsta ssid key， 检查链接是否成功：ap_client

- 检查客户端连接，命令：iwpriv ra0 show stainfo, dmesg查看结果

### 自研第三方软件配置

- luvit 二进制文件存储路径：package/self_dev_soft/system/bin/
- getImei 二进制文件存储路径：package/self_dev_soft/system/bin/
- network config文件存储路径：package/self_dev_soft/system/etc/config/
- 平台软件工程文件存放路径：E.G：package/mchj_app
- 单通道网关工程文件存储路径：package/lorawan-signal-gateway



## 参考开发链接:

Sdk：

1. [widora-7688](https://mangopi.cc/7688dev)
2. [widora-openwrt-github](https://github.com/widora/openwrt_widora.git)
3. [widora-uboot-github](https://github.com/widora/u-boot-mt7688.git)

