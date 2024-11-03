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
# 替换chinadns-ng
rm -rf feeds/packages/net/chinadns-ng/Makefile
wget -P feeds/packages/net/chinadns-ng https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/chinadns-ng/Makefile
#替换xray
rm -rf feeds/packages/net/xray-core
wget -P feeds/packages/net/xray-core https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/xray-core/Makefile
# 替换miniupnpd
#rm -rf feeds/packages/net/miniupnpd/Makefile
#wget -P feeds/packages/net/miniupnpd https://raw.githubusercontent.com/openwrt/packages/master/net/miniupnpd/Makefile

# 添加编译日期标识
export DATE_VERSION=$(date +'%Y-%m-%d')
sed -i "s/%C/%C (${DATE_VERSION})/g" package/base-files/files/etc/openwrt_release
#VER_FILE=$(find ./feeds/luci/modules/ -type f -name "10_system.js")
#awk -v wrt_repo="$WRT_REPO" -v wrt_date="$WRT_DATE" '{ gsub(/(\(luciversion \|\| \047\047\))/, "& + (\047 / "wrt_repo"-"wrt_date"\047)") } 1' $VER_FILE > temp.js && mv -f temp.js $VER_FILE
