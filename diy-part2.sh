#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 修改openwrt登陆地址
sed -i 's/192.168.1.1/192.168.0.1/g' package/base-files/files/bin/config_generate
#替换自带的passwall
rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/xiaorouji/openwrt-passwall package/openwrt-passwall
# 替换passwall组件
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,brook,chinadns-ng,dns2socks,dns2tcp,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,simple-obfs,tcping,trojan,trojan-go,trojan-plus,tuic-client,v2ray-plugin,xray-plugin}
git clone https://github.com/xiaorouji/openwrt-passwall-packages package/passwall-packages

# 替换miniupnpd
#rm -rf feeds/packages/net/miniupnpd
#git clone https://github.com/kxjhcmc/miniupnpd feeds/packages/net/miniupnpd

# 添加agron主题
#git clone https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-light/Makefile
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile


# 替换防火墙实现NAT1
FIREWALL4_DIR="package/network/config/firewall4"
PATCHES_DIR="$FIREWALL4_DIR/patches"
FULLCONE_DIR="package/network/utils/fullconenat-nft"

FIREWALL4_MAKEFILE_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$FIREWALL4_DIR/Makefile"
PATCH_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$PATCHES_DIR/001-firewall4-add-support-for-fullcone-nat.patch"
FULLCONE_MAKEFILE_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$FULLCONE_DIR/Makefile"

# 下载 firewall4 的 Makefile
mkdir -p "$FIREWALL4_DIR"
curl -fsSL "$FIREWALL4_MAKEFILE_URL" -o "$FIREWALL4_DIR/Makefile" && echo "✓ firewall4 Makefile 下载成功"

# 下载 fullcone 补丁
mkdir -p "$PATCHES_DIR"
curl -fsSL "$PATCH_URL" -o "$PATCHES_DIR/001-firewall4-add-support-for-fullcone-nat.patch" && echo "✓ 补丁文件下载成功"

# 下载 fullconenat-nft 的 Makefile
mkdir -p "$FULLCONE_DIR"
curl -fsSL "$FULLCONE_MAKEFILE_URL" -o "$FULLCONE_DIR/Makefile" && echo "✓ fullconenat-nft Makefile 下载成功"

# 添加编译日期标识
# 目标文件路径
VER_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
# 获取当前编译日期（YYYY-MM-DD）
BUILD_DATE=$(date +"%Y-%m-%d")
# 修改文件，添加编译日期
awk -v build_date="$BUILD_DATE" '{ sub(/\(luciversion \|\| \047\047\)/, "& + \047 ( " build_date " )\047"); print }' "$VER_FILE" > "$VER_FILE.tmp" && mv "$VER_FILE.tmp" "$VER_FILE"
