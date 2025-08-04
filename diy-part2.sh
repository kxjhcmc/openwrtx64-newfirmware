#!/bin/bash
set -e  # 脚本遇到错误即退出
set -u  # 使用未定义变量时报错
set -o pipefail  # 管道中任何命令失败都会使整个管道失败

# 工具函数：下载文件并显示状态
download() {
    local url="$1"
    local dest="$2"
    if curl -fsSL "$url" -o "$dest"; then
        echo "✓ $(basename "$dest") 下载成功"
    else
        echo "✗ $(basename "$dest") 下载失败"
    fi
}

echo "🔧 修改默认登录地址为 192.168.0.1"
sed -i 's/192.168.1.1/192.168.0.1/g' package/base-files/files/bin/config_generate

echo "🧹 删除 luci-app-cpufreq"
rm -rf feeds/luci/applications/luci-app-cpufreq

echo "🧹 替换 luci-app-passwall"
rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/xiaorouji/openwrt-passwall package/openwrt-passwall

echo "🧼 替换 passwall 相关依赖"
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,brook,chinadns-ng,dns2socks,dns2tcp,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,simple-obfs,tcping,trojan,trojan-go,trojan-plus,tuic-client,v2ray-plugin,xray-plugin}
git clone https://github.com/xiaorouji/openwrt-passwall-packages package/passwall-packages

# 可选主题注释块，保留设置模板
# echo "🎨 添加 luci-theme-argon 主题"
# git clone https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
# for file in feeds/luci/collections/luci*/Makefile; do
#     sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' "$file"
# done

REPO_BASE_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master"

echo "暂时修正vlmcsd哈希值"
VLMCSD_MAKEFILE_PATH="feeds/packages/net/vlmcsd/Makefile"
OLD_EXPECTED_HASH="0daa66c27aa917db13b26d444f04d73ea16925ef021405f5dd6e11ff9f9d034f"
NEW_ACTUAL_HASH="a5b9854a7cb2055fa2c7890ee196a7fbbec1fd6165bf5115504d160e2e3a7a19"
sed -i "s/PKG_MIRROR_HASH:=${OLD_EXPECTED_HASH}/PKG_MIRROR_HASH:=${NEW_ACTUAL_HASH}/g" "$VLMCSD_MAKEFILE_PATH"
if [ $? -eq 0 ]; then
    echo "PKG_MIRROR_HASH 已从 '${OLD_EXPECTED_HASH}' 更新为 '${NEW_ACTUAL_HASH}'。"
else
    echo "错误：更新 PKG_MIRROR_HASH 失败。请手动检查文件内容或权限。"
    echo "可能的原因是旧的哈希值在文件中未找到，或者文件权限不足。"
    exit 1
fi

echo "🧱 替换 firewall4 以支持 fullcone NAT"
FIREWALL4_DIR="package/network/config/firewall4"
mkdir -p "$FIREWALL4_DIR/patches"
download "$REPO_BASE_URL/$FIREWALL4_DIR/Makefile" "$FIREWALL4_DIR/Makefile"
download "$REPO_BASE_URL/$FIREWALL4_DIR/patches/001-firewall4-add-support-for-fullcone-nat.patch" "$FIREWALL4_DIR/patches/001-firewall4-add-support-for-fullcone-nat.patch"

echo "🌐 添加 fullconenat-nft 支持"
FULLCONE_DIR="package/network/utils/fullconenat-nft"
mkdir -p "$FULLCONE_DIR/patches"
download "$REPO_BASE_URL/$FULLCONE_DIR/Makefile" "$FULLCONE_DIR/Makefile"
download "$REPO_BASE_URL/$FULLCONE_DIR/patches/010-fix-build-with-kernel-6.12.patch" "$FULLCONE_DIR/patches/010-fix-build-with-kernel-6.12.patch"

echo "📦 替换 nftables"
NFTABLES_DIR="package/network/utils/nftables"
mkdir -p "$NFTABLES_DIR/patches"
download "$REPO_BASE_URL/$NFTABLES_DIR/Makefile" "$NFTABLES_DIR/Makefile"
download "$REPO_BASE_URL/$NFTABLES_DIR/patches/002-nftables-add-fullcone-expression-support.patch" "$NFTABLES_DIR/patches/002-nftables-add-fullcone-expression-support.patch"

echo "🔗 替换 libnftnl"
LIBNFTNL_DIR="package/libs/libnftnl"
mkdir -p "$LIBNFTNL_DIR/patches"
download "$REPO_BASE_URL/$LIBNFTNL_DIR/Makefile" "$LIBNFTNL_DIR/Makefile"
download "$REPO_BASE_URL/$LIBNFTNL_DIR/patches/001-libnftnl-add-fullcone-expression-support.patch" "$LIBNFTNL_DIR/patches/001-libnftnl-add-fullcone-expression-support.patch"

echo "📡 下载 autocore 组件"
AUTOCORE_DIR="package/emortal/autocore"
AUTOCORE_FILES_DIR="$AUTOCORE_DIR/files"
mkdir -p "$AUTOCORE_FILES_DIR"

download "$REPO_BASE_URL/$AUTOCORE_DIR/Makefile" "$AUTOCORE_DIR/Makefile"
for file in 60-autocore-reload-rpcd autocore cpuinfo luci-mod-status-autocore.json tempinfo; do
    download "$REPO_BASE_URL/$AUTOCORE_FILES_DIR/$file" "$AUTOCORE_FILES_DIR/$file"
done

echo "🕒 添加编译日期"
VER_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
BUILD_DATE=$(date +"%Y-%m-%d")
awk -v build_date="$BUILD_DATE" '{ sub(/\(luciversion \|\| \047\047\)/, "& + \047 ( " build_date " )\047"); print }' "$VER_FILE" > "$VER_FILE.tmp" && mv "$VER_FILE.tmp" "$VER_FILE"
