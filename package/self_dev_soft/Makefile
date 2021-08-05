##############################################
# OpenWrt Makefile for helloworld program
#
#
# Most of the variables used here are defined in
# the include directives below. We just need to
# specify a basic description of the package,
# where to build our program, where to find
# the source files, and where to install the
# compiled program on the router.
#
# Be very careful of spacing in this file.
# Indents should be tabs, not spaces, and
# there should be no trailing whitespace in
# lines that are not commented.
#
##############################################
include $(TOPDIR)/rules.mk
 
# Name and release number of this package
PKG_NAME:=self_dev_soft
PKG_RELEASE:=1
RSTRIP:=:

# This specifies the directory where we're going to build the program. 
# The root build directory, $(BUILD_DIR), is by default the build_mipsel
# directory in your OpenWrt SDK directory
 
PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)
 
include $(INCLUDE_DIR)/package.mk
 
# Specify package information for this program.
# The variables defined here should be self explanatory.
# If you are running Kamikaze, delete the DESCRIPTION
# variable below and uncomment the Kamikaze define
# directive for the description below
define Package/self_dev_soft
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=self_dev_software
	DEPENDS:=+libpthread +librt
endef

# Uncomment portion below for Kamikaze and delete DESCRIPTION variable above
define Package/self_dev_soft/description
	self_dev_software for openwrt
endef

# Specify what needs to be done to prepare for building the package.
# In our case, we need to copy the source files to the build directory.
# This is NOT the default.  The default uses the PKG_SOURCE_URL and the
# PKG_SOURCE which is not defined here to download the source from the web.
# In order to just build a simple program that we have just written, it is
# much easier to do it this way.
define Build/Prepare
	@echo prepare...
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./system/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
	@echo build none...
endef

# We do not need to define Build/Configure or Build/Compile directives
# The defaults are appropriate for compiling a simple program such as this one
# Specify where and how to install the program. Since we only have one file,
# the helloworld executable, install it by copying it to the /bin directory on
# the router. The $(1) variable represents the root directory on the router running
# OpenWrt. The $(INSTALL_DIR) variable contains a command to prepare the install
# directory if it does not already exist.  Likewise $(INSTALL_BIN) contains the
# command to copy the binary file from its current location (in our case the build
# directory) to the install directory.
define Package/self_dev_soft/install
	@echo install...
	$(INSTALL_DIR) $(1)/usr/bin
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/t2n $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/luvit $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/getImei $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/reconnect.sh $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/etc/config/

	# 测试rndis
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/config/network_ppp $(1)/etc/config/network
	cp $(PKG_BUILD_DIR)/etc/config/network_rndis $(PKG_BUILD_DIR)/etc/config/network
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/config/network $(1)/etc/config/

	# 界面配置成中文默认
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/config/luci_en $(1)/etc/config/luci
	cp $(PKG_BUILD_DIR)/etc/config/luci_zh $(PKG_BUILD_DIR)/etc/config/luci
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/config/luci $(1)/etc/config/

	# $(INSTALL_DIR) $(1)/etc/init.d
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/init.d/t2napp $(1)/etc/init.d/
	# $(INSTALL_DIR) $(1)/etc/rc.d
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/etc/rc.d/S99t2napp $(1)/etc/rc.d/

	# $(INSTALL_DIR) $(1)/lib/netifd/proto
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/lib/netifd/proto/t2n.sh $(1)/lib/netifd/proto/

	# $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/admin_network/
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/usr/lib/lua/luci/model/cbi/admin_network/proto_t2n.lua $(1)/usr/lib/lua/luci/model/cbi/admin_network/

	# $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/network/
	# $(INSTALL_BIN) $(PKG_BUILD_DIR)/usr/lib/lua/luci/model/network/proto_t2n.lua $(1)/usr/lib/lua/luci/model/network/
endef

# This line executes the necessary commands to compile our program.
# The above define directives specify all the information needed, but this
# line calls BuildPackage which in turn actually uses this information to
# build a package.
$(eval $(call BuildPackage,self_dev_soft))
