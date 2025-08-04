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

# ==============================================================================
# 智能修正 vlmcsd 哈希值部分 (强烈推荐使用此版本)
# ==============================================================================
echo "Checking and correcting vlmcsd hash value..."
VLMCSD_MAKEFILE_PATH="feeds/packages/net/vlmcsd/Makefile"
OLD_EXPECTED_HASH="0daa66c27aa917db13b26d444f04d73ea16925ef021405f5dd6e11ff9f9d034f"
NEW_ACTUAL_HASH="a5b9854a7cb2055fa2c7890ee196a7fbbec1fd6165bf5115504d160e2e3a7a19" # 已根据日志修正为 165bf

# 检查 Makefile 文件是否存在
if [ ! -f "$VLMCSD_MAKEFILE_PATH" ]; then
    echo "错误：找不到 vlmcsd 的 Makefile 文件在 '$VLMCSD_MAKEFILE_PATH'。"
    echo "请检查路径或确保您在 OpenWrt 源代码的根目录下运行本脚本。"
    exit 1 # 找不到关键文件，直接退出
fi

# 读取 Makefile 中当前的 PKG_MIRROR_HASH 值
# grep -oP 提取匹配到的哈希值
# || true 防止 grep 找不到时因 set -e 导致脚本退出
CURRENT_HASH=$(grep -oP 'PKG_MIRROR_HASH:=\K[0-9a-fA-F]{64}' "$VLMCSD_MAKEFILE_PATH" || true)

if [ "$CURRENT_HASH" == "$OLD_EXPECTED_HASH" ]; then
    echo "检测到当前 PKG_MIRROR_HASH 为旧值：'${OLD_EXPECTED_HASH}'。"
    # 尝试进行替换
    sed -i "s/PKG_MIRROR_HASH:=${OLD_EXPECTED_HASH}/PKG_MIRROR_HASH:=${NEW_ACTUAL_HASH}/g" "$VLMCSD_MAKEFILE_PATH"
    if [ $? -eq 0 ]; then
        echo "PKG_MIRROR_HASH 已从 '${OLD_EXPECTED_HASH}' 成功更新为 '${NEW_ACTUAL_HASH}'。"
    else
        # 理论上，如果 sed 运行时失败，set -e 会在此之前退出。
        # 此分支更多是防御性代码，例如 sed 版本问题。
        echo "错误：更新 PKG_MIRROR_HASH 失败。请检查文件权限或 sed 命令。"
        exit 1
    fi
elif [ "$CURRENT_HASH" == "$NEW_ACTUAL_HASH" ]; then
    echo "PKG_MIRROR_HASH 已是目标新值 '${NEW_ACTUAL_HASH}'，无需修改。"
elif [ -z "$CURRENT_HASH" ]; then
    echo "警告：在 '$VLMCSD_MAKEFILE_PATH' 中未能找到 PKG_MIRROR_HASH 定义，或定义格式不正确。"
    echo "脚本将不会进行修改，请手动检查 Makefile 内容。"
    # 如果关键定义缺失，通常也认为是需要注意的问题
    # exit 1 确保这类异常情况能被发现并阻止后续编译
    exit 1
else
    echo "当前 PKG_MIRROR_HASH 为：'${CURRENT_HASH}'。"
    echo "此值既不是旧值也不是目标新值，脚本将不会进行修改。"
    echo "这可能意味着作者已经更新了不同的哈希值。请手动检查 Makefile 内容。"
    # 如果哈希值是未知的新值，也可能意味着作者已修复，但方式不同，此时不应强制修改。
    # 同样建议退出，以便用户检查。
    exit 1
fi
echo "vlmcsd hash check and fix complete."
# ==============================================================================

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
