#!/bin/bash
set -e
set -u
set -o pipefail

# 工具函数
download() {
    local url="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "$url" -o "$dest"
}

echo "🔧 修改默认登录地址为 192.168.0.1"
sed -i 's/192.168.1.1/192.168.0.1/g' package/base-files/files/bin/config_generate

echo "📦 重新下载最新版 Passwall (克隆到 package 目录以获得最高优先级)"
git clone https://github.com/Openwrt-Passwall/openwrt-passwall package/openwrt-passwall
git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

echo "🧱 替换核心组件：Firewall4, nftables, libnftnl (支持 fullcone NAT)"
REPO_BASE_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master"

# Firewall4, nftables, libnftnl, fullconenat-nft
download "$REPO_BASE_URL/package/network/config/firewall4/Makefile" "package/network/config/firewall4/Makefile"
download "$REPO_BASE_URL/package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch" "package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch"

download "$REPO_BASE_URL/package/network/utils/fullconenat-nft/Makefile" "package/network/utils/fullconenat-nft/Makefile"
download "$REPO_BASE_URL/package/network/utils/fullconenat-nft/patches/010-fix-build-with-kernel-6.12.patch" "package/network/utils/fullconenat-nft/patches/010-fix-build-with-kernel-6.12.patch"

download "$REPO_BASE_URL/package/network/utils/nftables/Makefile" "package/network/utils/nftables/Makefile"
download "$REPO_BASE_URL/package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch" "package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch"

download "$REPO_BASE_URL/package/libs/libnftnl/Makefile" "package/libs/libnftnl/Makefile"
download "$REPO_BASE_URL/package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch" "package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch"

echo "📡 下载 autocore 组件"
AUTOCORE_DIR="package/emortal/autocore"
download "$REPO_BASE_URL/$AUTOCORE_DIR/Makefile" "$AUTOCORE_DIR/Makefile"
for file in 60-autocore-reload-rpcd autocore cpuinfo luci-mod-status-autocore.json tempinfo; do
    download "$REPO_BASE_URL/$AUTOCORE_DIR/files/$file" "$AUTOCORE_DIR/files/$file"
done

echo "🧩 应用 Cloudflared UI 翻译和界面补丁"
CLOUDFLARED_APP_DIR="feeds/luci/applications/luci-app-cloudflared"
LOCAL_PATCH_DIR="$GITHUB_WORKSPACE/cloudflared"

if [ -d "$CLOUDFLARED_APP_DIR" ] && [ -d "$LOCAL_PATCH_DIR" ]; then
    cp -f "$LOCAL_PATCH_DIR/config.js" \
        "$CLOUDFLARED_APP_DIR/htdocs/luci-static/resources/view/cloudflared/config.js"

    cp -f "$LOCAL_PATCH_DIR/cloudflared.po" \
        "$CLOUDFLARED_APP_DIR/po/zh_Hans/cloudflared.po"
fi

echo "🧩 复制 FastNet 及 LuCI 插件到 packages 目录"
if [ -f "$GITHUB_WORKSPACE/copy-fastnet.sh" ]; then
 chmod +x "$GITHUB_WORKSPACE/copy-fastnet.sh"
 "$GITHUB_WORKSPACE/copy-fastnet.sh"
fi

echo "🕒 添加编译日期"
VER_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
if [ -f "$VER_FILE" ]; then
    BUILD_DATE=$(date +"%Y-%m-%d")
    awk -v build_date="$BUILD_DATE" '{ sub(/\(luciversion \|\| \047\047\)/, "& + \047 ( " build_date " )\047"); print }' "$VER_FILE" > "$VER_FILE.tmp" && mv "$VER_FILE.tmp" "$VER_FILE"
fi

echo "✅ Post-Feeds 阶段执行完毕"
