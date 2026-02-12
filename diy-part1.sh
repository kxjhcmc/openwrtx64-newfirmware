#!/bin/bash
set -e
set -u
set -o pipefail

# 工具函数
download() {
    local url="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if curl -fsSL "$url" -o "$dest"; then
        echo "✓ $(basename "$dest") 下载成功"
    else
        echo "✗ $(basename "$dest") 下载失败"
        exit 1
    fi
}

echo "🧹 正在清理 feeds 中的冗余/旧软件包..."
# 删除 luci-app-cpufreq
rm -rf feeds/luci/applications/luci-app-cpufreq
# 删除旧的 passwall 及其相关界面
rm -rf feeds/luci/applications/luci-app-passwall
# 删除 passwall 相关依赖（这些将由后续 package 目录下的新版本替代）
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,brook,chinadns-ng,dns2socks,dns2tcp,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,simple-obfs,tcping,trojan,trojan-go,trojan-plus,tuic-client,v2ray-plugin,xray-plugin}

echo "🧩 补丁修改：更新 luci-app-cloudflared 界面与翻译"
CLOUDFLARED_JS_URL="https://raw.githubusercontent.com/kxjhcmc/openwrtx64-newfirmware/refs/heads/main/cloudflared/config.js"
CLOUDFLARED_PO_URL="https://raw.githubusercontent.com/kxjhcmc/openwrtx64-newfirmware/refs/heads/main/cloudflared/cloudflared.po"
CLOUDFLARED_APP_DIR="feeds/luci/applications/luci-app-cloudflared"

if [ -d "$CLOUDFLARED_APP_DIR" ]; then
    download "$CLOUDFLARED_JS_URL" "$CLOUDFLARED_APP_DIR/htdocs/luci-static/resources/view/cloudflared/config.js"
    download "$CLOUDFLARED_PO_URL" "$CLOUDFLARED_APP_DIR/po/zh_Hans/cloudflared.po"
fi

echo "🕒 补丁修改：添加编译日期到系统界面"
VER_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
if [ -f "$VER_FILE" ]; then
    BUILD_DATE=$(date +"%Y-%m-%d")
    awk -v build_date="$BUILD_DATE" '{ sub(/\(luciversion \|\| \047\047\)/, "& + \047 ( " build_date " )\047"); print }' "$VER_FILE" > "$VER_FILE.tmp" && mv "$VER_FILE.tmp" "$VER_FILE"
fi

# ====================================================================================
echo "🔄 核心更新：正在检查并更新 cloudflared 源码版本..."
if [ -f "$GITHUB_WORKSPACE/update_cloudflared.sh" ]; then
    chmod +x "$GITHUB_WORKSPACE/update_cloudflared.sh"
    "$GITHUB_WORKSPACE/update_cloudflared.sh"
fi

echo "🔄 核心更新：正在检查并更新 Golang 编译器版本..."
if [ -f "$GITHUB_WORKSPACE/update_go.sh" ]; then
    chmod +x "$GITHUB_WORKSPACE/update_go.sh"
    "$GITHUB_WORKSPACE/update_go.sh"
fi
# ====================================================================================

echo "✅ Pre-Feeds 阶段执行完毕，请紧接着运行 ./scripts/feeds install -a"
