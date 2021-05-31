#
# Copyright (C) 2008 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.


include $(TOPDIR)/rules.mk


PKG_NAME:=t2n
PKG_VERSION:=1
PKG_RELEASE:=0

PKG_BUILD_DEPENDS:=

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_INSTALL_DIR:=$(PKG_BUILD_DIR)

include $(INCLUDE_DIR)/package.mk
# include $(INCLUDE_DIR)/cmake.mk

CMAKE_OPTIONS += -DUBUS=1

define Package/t2n
  SECTION:=net
  CATEGORY:=Network
  TITLE:=EC20 dis_t2n
  DEPENDS:=+libpthread
endef 

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./t2n_linux/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	@echo build...
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)"
endef

define Package/t2n/install
	# $(INSTALL_DIR) $(1)/usr/sbin
	# $(INSTALL_DIR) $(1)/usr/lib
	# $(INSTALL_BIN) $(PKG_INSTALL_DIR)/t2n $(1)/usr/sbin/
	#	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/supernode $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,t2n))
