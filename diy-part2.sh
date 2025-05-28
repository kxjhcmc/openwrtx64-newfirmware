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

# 添加agron主题
#git clone https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-light/Makefile
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-nginx/Makefile


# 替换防火墙实现NAT1
# ---------- firewall4 ----------
FIREWALL4_DIR="package/network/config/firewall4"
FIREWALL4_PATCHES="$FIREWALL4_DIR/patches"
mkdir -p "$FIREWALL4_PATCHES"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$FIREWALL4_DIR/Makefile" -o "$FIREWALL4_DIR/Makefile" && echo "✓ firewall4 Makefile 下载成功"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$FIREWALL4_PATCHES/001-firewall4-add-support-for-fullcone-nat.patch" -o "$FIREWALL4_PATCHES/001-firewall4-add-support-for-fullcone-nat.patch" && echo "✓ firewall4 patch 下载成功"

# ---------- fullconenat-nft ----------
FULLCONE_DIR="package/network/utils/fullconenat-nft"
mkdir -p "$FULLCONE_DIR"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$FULLCONE_DIR/Makefile" -o "$FULLCONE_DIR/Makefile" && echo "✓ fullconenat-nft Makefile 下载成功"
FULLCONE_PATCHES="$FULLCONE_DIR/patches"
mkdir -p "$FULLCONE_PATCHES"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/refs/heads/master/package/network/utils/fullconenat-nft/patches/010-fix-build-with-kernel-6.12.patch" -o "$FULLCONE_PATCHES/010-fix-build-with-kernel-6.12.patch" && echo "✓ fullconenat-nft patch 下载成功"

# ---------- nftables ----------
NFTABLES_DIR="package/network/utils/nftables"
NFTABLES_PATCHES="$NFTABLES_DIR/patches"
mkdir -p "$NFTABLES_PATCHES"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$NFTABLES_DIR/Makefile" -o "$NFTABLES_DIR/Makefile" && echo "✓ nftables Makefile 下载成功"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$NFTABLES_PATCHES/001-drop-useless-file.patch" -o "$NFTABLES_PATCHES/001-drop-useless-file.patch" && echo "✓ nftables patch 001 下载成功"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$NFTABLES_PATCHES/002-nftables-add-fullcone-expression-support.patch" -o "$NFTABLES_PATCHES/002-nftables-add-fullcone-expression-support.patch" && echo "✓ nftables patch 002 下载成功"

# ---------- libnftnl ----------
LIBNFTNL_DIR="package/libs/libnftnl"
LIBNFTNL_PATCHES="$LIBNFTNL_DIR/patches"
mkdir -p "$LIBNFTNL_PATCHES"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$LIBNFTNL_DIR/Makefile" -o "$LIBNFTNL_DIR/Makefile" && echo "✓ libnftnl Makefile 下载成功"
curl -fsSL "https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/$LIBNFTNL_PATCHES/001-libnftnl-add-fullcone-expression-support.patch" -o "$LIBNFTNL_PATCHES/001-libnftnl-add-fullcone-expression-support.patch" && echo "✓ libnftnl patch 下载成功"



# 添加编译日期标识
# 目标文件路径
VER_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
# 获取当前编译日期（YYYY-MM-DD）
BUILD_DATE=$(date +"%Y-%m-%d")
# 修改文件，添加编译日期
awk -v build_date="$BUILD_DATE" '{ sub(/\(luciversion \|\| \047\047\)/, "& + \047 ( " build_date " )\047"); print }' "$VER_FILE" > "$VER_FILE.tmp" && mv "$VER_FILE.tmp" "$VER_FILE"
