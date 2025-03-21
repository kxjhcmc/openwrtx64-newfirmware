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

# 总是拉取官方golang版本，避免xray&v2ray编译错误
#rm -rf feeds/packages/lang/golang
#git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

# 添加编译日期标识
# 获取当前时间
BUILD_DATE=$(date +"%Y-%m-%d")

# 目标文件路径
TARGET_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
# 修改文件，在第 87 行后面添加编译时间
sed -i '87s/\(luciversion || .\)/\1 + '\'' ('"$BUILD_TIME"')'\''/' "$TARGET_FILE"

