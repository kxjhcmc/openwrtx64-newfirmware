#!/bin/bash
set -e
set -u
set -o pipefail

download() {
    local url="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "$url" -o "$dest"
}

echo "🔧 修改默认登录地址为 192.168.0.1"
sed -i 's/192.168.1.1/192.168.0.1/g' package/base-files/files/bin/config_generate

echo "📦 拉取最新版 Passwall 仓库到 package 目录"
# 因为 Part 1 已经删除了 feeds 里的旧版，这里克隆的新版将生效
git clone https://github.com/Openwrt-Passwall/openwrt-passwall package/openwrt-passwall
git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

echo "🧱 替换系统核心组件 (Firewall4, nftables, libnftnl) 以支持 Fullcone NAT"
REPO_BASE_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master"

# Firewall4
download "$REPO_BASE_URL/package/network/config/firewall4/Makefile" "package/network/config/firewall4/Makefile"
download "$REPO_BASE_URL/package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch" "package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch"

# fullconenat-nft
download "$REPO_BASE_URL/package/network/utils/fullconenat-nft/Makefile" "package/network/utils/fullconenat-nft/Makefile"
download "$REPO_BASE_URL/package/network/utils/fullconenat-nft/patches/010-fix-build-with-kernel-6.12.patch" "package/network/utils/fullconenat-nft/patches/010-fix-build-with-kernel-6.12.patch"

# nftables
download "$REPO_BASE_URL/package/network/utils/nftables/Makefile" "package/network/utils/nftables/Makefile"
download "$REPO_BASE_URL/package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch" "package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch"

# libnftnl
download "$REPO_BASE_URL/package/libs/libnftnl/Makefile" "package/libs/libnftnl/Makefile"
download "$REPO_BASE_URL/package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch" "package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch"

echo "📡 下载 autocore 组件"
AUTOCORE_DIR="package/emortal/autocore"
download "$REPO_BASE_URL/$AUTOCORE_DIR/Makefile" "$AUTOCORE_DIR/Makefile"
for file in 60-autocore-reload-rpcd autocore cpuinfo luci-mod-status-autocore.json tempinfo; do
    download "$REPO_BASE_URL/$AUTOCORE_DIR/files/$file" "$AUTOCORE_DIR/files/$file"
done

echo "✅ Post-Feeds 阶段执行完毕"
