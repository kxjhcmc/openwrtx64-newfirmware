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
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall package/openwrt-passwall
git clone --depth 1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

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

echo "🧩 下载 speedtest 插件到 package 目录"
if [ ! -d package/speedtest ]; then
    TMP_SPEEDTEST="$(mktemp -d)"
    git clone --depth 1 https://github.com/kxjhcmc/openwrt-speedtest "$TMP_SPEEDTEST"
    cp -r "$TMP_SPEEDTEST/speedtest" package/
    cp -r "$TMP_SPEEDTEST/luci-app-speedtest" package/
    rm -rf "$TMP_SPEEDTEST"
fi

echo "🩹 修复 luci-app-upnp 不显示端口映射 (兼容 miniupnpd 2.3.10+)"
# miniupnpd 2.3.10 起 nft DNAT 规则多了 "counter packets X bytes Y"，
# luci-app-upnp 的 rpcd 正则未适配导致 LuCI 页面一直显示"当前没有生效的端口映射"。
# 特征匹配打补丁：上游若自行修复（特征消失）则自动跳过，不做任何修改。
UPNP_UCODE=$(find feeds -type f -path '*luci-app-upnp*' -name 'luci.upnp' 2>/dev/null || true)
if [ -n "$UPNP_UCODE" ]; then
    for f in $UPNP_UCODE; do
        if grep -qF 'th dport ([0-9]+).*dnat ip to' "$f"; then
            echo "   -> $f 已兼容，跳过"
        elif grep -qF 'th dport ([0-9]+) dnat ip to' "$f"; then
            sed -i 's/) dnat ip to/).*dnat ip to/' "$f"
            if grep -qF 'th dport ([0-9]+).*dnat ip to' "$f"; then
                echo "   -> 已打补丁: $f"
            else
                echo "   -> 补丁后校验失败！" >&2
                exit 1
            fi
        else
            echo "   -> $f 正则已被上游修改，视为已修复，不做任何改动"
        fi
    done
else
    echo "   -> 在 feeds 中未找到 luci-app-upnp，跳过（不影响编译）"
fi

echo "🧩 修改网络参数"
CONF_FILE="package/kernel/linux/files/sysctl-nf-conntrack.conf"

# 直接使用 > 进行覆盖写入
cat > "$CONF_FILE" <<'EOF'
# Do not edit, changes to this file will be lost on upgrades
# /etc/sysctl.conf can be used to customize sysctl settings

net.ipv4.tcp_ecn=0
net.ipv4.tcp_keepalive_probes=6
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.ip_local_port_range=2048 63487
net.ipv4.tcp_fastopen=3
net.core.netdev_budget=600
net.core.gro_normal_batch=16
net.core.netdev_max_backlog=4096
net.core.rmem_max=4194304

net.netfilter.nf_conntrack_acct=1
net.netfilter.nf_conntrack_checksum=0
net.netfilter.nf_conntrack_generic_timeout=600
net.netfilter.nf_conntrack_log_invalid=0
net.netfilter.nf_conntrack_tcp_timeout_syn_sent=5
net.netfilter.nf_conntrack_tcp_timeout_syn_recv=5
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=10
net.netfilter.nf_conntrack_tcp_timeout_close_wait=10
net.netfilter.nf_conntrack_tcp_timeout_last_ack=10
net.netfilter.nf_conntrack_tcp_timeout_time_wait=10
net.netfilter.nf_conntrack_tcp_timeout_close=5
net.netfilter.nf_conntrack_tcp_loose=1
net.netfilter.nf_conntrack_tcp_be_liberal=0
net.netfilter.nf_conntrack_tcp_max_retrans=3
net.netfilter.nf_conntrack_tcp_timeout_established=1800
net.netfilter.nf_conntrack_icmp_timeout=10
net.netfilter.nf_conntrack_udp_timeout=10
net.netfilter.nf_conntrack_udp_timeout_stream=60

net.ipv4.neigh.default.gc_thresh1=16384
net.ipv4.neigh.default.gc_thresh2=16384
net.ipv4.neigh.default.gc_thresh3=32768
net.unix.max_dgram_qlen=2048
EOF

echo "已成功修改配置文件。"

echo "🕒 添加编译日期"
VER_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
if [ -f "$VER_FILE" ]; then
    BUILD_DATE=$(date +"%Y-%m-%d")
    awk -v build_date="$BUILD_DATE" '{ sub(/\(luciversion \|\| \047\047\)/, "& + \047 ( " build_date " )\047"); print }' "$VER_FILE" > "$VER_FILE.tmp" && mv "$VER_FILE.tmp" "$VER_FILE"
fi

echo "✅ Post-Feeds 阶段执行完毕"
