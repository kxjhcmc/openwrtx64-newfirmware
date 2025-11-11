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
        # 如果下载失败，在 set -e 的情况下，脚本会自动退出。
        # 如果需要更精细的错误处理，可以在这里添加 exit 1
        exit 1 # 确保下载失败时终止整个脚本
    fi
}

echo "🔧 修改默认登录地址为 192.168.0.1"
sed -i 's/192.168.1.1/192.168.0.1/g' package/base-files/files/bin/config_generate

# ====================================================================================

echo "🧹 删除 luci-app-cpufreq"
rm -rf feeds/luci/applications/luci-app-cpufreq

echo "🧹 替换 luci-app-passwall"
rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/xiaorouji/openwrt-passwall package/openwrt-passwall

echo "🧼 替换 passwall 相关依赖"
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,brook,chinadns-ng,dns2socks,dns2tcp,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,simple-obfs,tcping,trojan,trojan-go,trojan-plus,tuic-client,v2ray-plugin,xray-plugin}
git clone https://github.com/xiaorouji/openwrt-passwall-packages package/passwall-packages

# ====================================================================================


# 可选主题注释块，保留设置模板
# echo "🎨 添加 luci-theme-argon 主题"
# git clone https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
# for file in feeds/luci/collections/luci*/Makefile; do
#     sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' "$file"
# done

REPO_BASE_URL="https://raw.githubusercontent.com/immortalwrt/immortalwrt/master"

echo "🧱 替换 firewall4 以支持 fullcone NAT"
mkdir -p package/network/config/firewall4/patches # 确保 patches 目录存在
download "$REPO_BASE_URL/package/network/config/firewall4/Makefile" "package/network/config/firewall4/Makefile"
download "$REPO_BASE_URL/package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch" "package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch"

echo "🌐 添加 fullconenat-nft 支持"
mkdir -p package/network/utils/fullconenat-nft/patches # 确保 patches 目录存在
download "$REPO_BASE_URL/package/network/utils/fullconenat-nft/Makefile" "package/network/utils/fullconenat-nft/Makefile"
download "$REPO_BASE_URL/package/network/utils/fullconenat-nft/patches/010-fix-build-with-kernel-6.12.patch" "package/network/utils/fullconenat-nft/patches/010-fix-build-with-kernel-6.12.patch"

echo "📦 替换 nftables"
mkdir -p package/network/utils/nftables/patches # 确保 patches 目录存在
download "$REPO_BASE_URL/package/network/utils/nftables/Makefile" "package/network/utils/nftables/Makefile"
download "$REPO_BASE_URL/package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch" "package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch"

echo "🔗 替换 libnftnl"
mkdir -p package/libs/libnftnl/patches # 确保 patches 目录存在
download "$REPO_BASE_URL/package/libs/libnftnl/Makefile" "package/libs/libnftnl/Makefile"
download "$REPO_BASE_URL/package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch" "package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch"

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
# 使用 awk 进行替换，确保替换成功后才进行文件移动
awk -v build_date="$BUILD_DATE" '{ sub(/\(luciversion \|\| \047\047\)/, "& + \047 ( " build_date " )\047"); print }' "$VER_FILE" > "$VER_FILE.tmp" && mv "$VER_FILE.tmp" "$VER_FILE"
if [ $? -ne 0 ]; then
    echo "错误：修改编译日期失败。请检查文件权限或路径。"
    exit 1
fi

echo "✅ 脚本执行完毕"
