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
# 添加编译日期标识
VER_FILE=$(find ./feeds/luci/modules/ -type f -name "10_system.js")
awk -v wrt_repo="$WRT_REPO" -v wrt_date="$WRT_DATE" '{ gsub(/(\(luciversion \|\| \047\047\))/, "& + (\047 / "wrt_repo"-"wrt_date"\047)") } 1' $VER_FILE > temp.js && mv -f temp.js $VER_FILE
