#!/bin/bash
set -e
set -u
set -o pipefail

# ====================================================================================
echo "🔄 核心更新：正在检查并更新 cloudflared 源码版本..."
if [ -f "$GITHUB_WORKSPACE/update_cloudflared.sh" ]; then
    chmod +x "$GITHUB_WORKSPACE/update_cloudflared.sh"
    "$GITHUB_WORKSPACE/update_cloudflared.sh"
fi

echo "🔄 核心更新：正在检查并更新 Golang 编译器版本..."
# 必须在 install -a 之前运行，以便创建新的 golang1.26 目录并被识别
if [ -f "$GITHUB_WORKSPACE/update_go.sh" ]; then
    chmod +x "$GITHUB_WORKSPACE/update_go.sh"
    "$GITHUB_WORKSPACE/update_go.sh"
fi
# ====================================================================================

echo "🧹 清理 feeds 中的旧版插件，防止 install 时产生冲突"
rm -rf feeds/luci/applications/luci-app-cpufreq
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box,brook,chinadns-ng,dns2socks,dns2tcp,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,simple-obfs,tcping,trojan,trojan-go,trojan-plus,tuic-client,v2ray-plugin,xray-plugin}

echo "🧩 复制 FastNet 及 LuCI 插件到 packages 目录"
if [ -f "$GITHUB_WORKSPACE/copy-fastnet.sh" ]; then
 chmod +x "$GITHUB_WORKSPACE/copy-fastnet.sh"
 "$GITHUB_WORKSPACE/copy-fastnet.sh"
fi
# =================================

echo "✅ Pre-Feeds 阶段执行完毕。"
