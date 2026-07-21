include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-passwall-snell
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKG_MAINTAINER:=autumnsentiment
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-passwall-snell
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=PassWall Snell Bridge
  DEPENDS:=+luci-base +luci-app-passwall +curl +ca-bundle
  PKGARCH:=all
endef

define Package/luci-app-passwall-snell/description
 Runs Mihomo in RAM as a Snell client with optional ShadowTLS and exposes a
 local SOCKS5 endpoint for PassWall.
endef

define Package/luci-app-passwall-snell/conffiles
/etc/config/passwall_snell
endef

define Build/Compile
endef

define Package/luci-app-passwall-snell/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/passwall_snell $(1)/etc/config/passwall_snell
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/passwall-snell $(1)/etc/init.d/passwall-snell
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/luci-app-passwall-snell $(1)/lib/upgrade/keep.d/luci-app-passwall-snell
	$(INSTALL_DIR) $(1)/usr/share/passwall-snell
	$(INSTALL_BIN) ./files/usr/share/passwall-snell/launcher.sh $(1)/usr/share/passwall-snell/launcher.sh
	$(INSTALL_BIN) ./files/usr/share/passwall-snell/migrate-config.sh $(1)/usr/share/passwall-snell/migrate-config.sh
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/controller/passwall_snell.lua $(1)/usr/lib/lua/luci/controller/passwall_snell.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/passwall_snell.lua $(1)/usr/lib/lua/luci/model/cbi/passwall_snell.lua
endef

define Package/luci-app-passwall-snell/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/usr/share/passwall-snell/migrate-config.sh >/dev/null 2>&1 || true
	/etc/init.d/passwall-snell enable >/dev/null 2>&1 || true
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache
fi
exit 0
endef

define Package/luci-app-passwall-snell/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/passwall-snell stop >/dev/null 2>&1 || true
	/etc/init.d/passwall-snell disable >/dev/null 2>&1 || true
fi
exit 0
endef

define Package/luci-app-passwall-snell/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache
fi
exit 0
endef

$(eval $(call BuildPackage,luci-app-passwall-snell))
