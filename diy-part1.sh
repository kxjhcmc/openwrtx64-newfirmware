#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#

# 🔄 调用 update_go.sh 自动更新 Golang 版本（解决 xray 依赖问题）
echo "🔄 正在检查并更新 Golang 版本..."
if [ -f "$GITHUB_WORKSPACE/update_go.sh" ]; then
    chmod +x "$GITHUB_WORKSPACE/update_go.sh"
    "$GITHUB_WORKSPACE/update_go.sh"
else
    echo "⚠️ 未找到 update_go.sh 脚本，跳过更新。"
fi
# ====================================================================================

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default
#暂时跳过版本号检测
#curl -s https://raw.githubusercontent.com/sbwml/r4s_build_script/4a9fafefd67172e074fa62cbe3570c4e197376b3/openwrt/patch/apk-tools/9999-hack-for-linux-pre-releases.patch > package/system/apk/patches/9999-hack-for-linux-pre-releases.patch

# Add a feed source
#echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
