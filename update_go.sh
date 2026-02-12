#!/bin/bash
set -e
set -u
set -o pipefail

# 定义路径
BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"
BOOTSTRAP_MAKEFILE="$BASE_DIR/golang-bootstrap/Makefile"

GO_API_URL="https://go.dev/dl/?mode=json"
CURL_OPTIONS="" 

echo "🛠️ 开始执行 Golang 自动更新脚本..."

# --- 辅助函数 ---
check_json_data() {
    if [ "$(echo "$1" | jq 'length')" -eq 0 ]; then
        echo "❌ 错误: 无法获取有效的 Go 版本列表。"
        exit 1
    fi
}

get_go_pkg_hash() {
    local hash=$(echo "$1" | jq -r '.files[] | select(.kind=="source") | .sha256')
    [ -z "$hash" ] || [ "$hash" == "null" ] && { echo "❌ 错误: 无法提取源码哈希。"; exit 1; }
    echo "$hash"
}

# --- 1. 获取最新版本信息 ---
echo "🌐 正在检查官方最新稳定版本..."
STABLE_JSON=$(curl -s "$CURL_OPTIONS" "$GO_API_URL" | jq -r '[.[] | select(.stable==true)]')
check_json_data "$STABLE_JSON" "$GO_API_URL"

GO_DATA=$(echo "$STABLE_JSON" | jq -r '.[0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2)
PATCH=$(echo "$FULL_VER" | cut -d. -f3); PATCH=${PATCH:-0}
PKG_HASH=$(get_go_pkg_hash "$GO_DATA")

TARGET_GO_MM_INT=$(echo "$MAJOR_MINOR" | sed 's/\.//')
TARGET_DIR="$BASE_DIR/golang$MAJOR_MINOR"
MAKEFILE="$TARGET_DIR/Makefile"

echo "🔎 目标版本: $FULL_VER"

# --- 2. 检查并更新 golang-bootstrap ---
echo "---------------------------------------------------------"
echo "⚙️ 正在检查 golang-bootstrap..."

REQ_MM_INT=$((TARGET_GO_MM_INT - 2))
REQ_MM="1.$((REQ_MM_INT - 100))"

# 引导器选择：精准匹配 N-2 或取列表最老的一个稳定版
BOOTSTRAP_GO_DATA=$(echo "$STABLE_JSON" | jq -r --arg req "go$REQ_MM" \
  '([.[] | select(.version | startswith($req))] | first) // .[-1]')

B_FULL_VER=$(echo "$BOOTSTRAP_GO_DATA" | jq -r '.version' | sed 's/go//')
B_MM=$(echo "$B_FULL_VER" | cut -d. -f1,2)
B_PATCH=$(echo "$B_FULL_VER" | cut -d. -f3); B_PATCH=${B_PATCH:-0}
B_HASH=$(get_go_pkg_hash "$BOOTSTRAP_GO_DATA")

# 精准读取本地 bootstrap 版本
L_B_MM=$(grep -E "^GO_VERSION_MAJOR_MINOR\s*[:?]=" "$BOOTSTRAP_MAKEFILE" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "0.0")
L_B_P=$(grep -E "^GO_VERSION_PATCH\s*[:?]=" "$BOOTSTRAP_MAKEFILE" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "0")

if [ "$B_FULL_VER" != "$L_B_MM.$L_B_P" ]; then
    echo "🔄 更新 bootstrap: $L_B_MM.$L_B_P -> $B_FULL_VER"
    # 使用精准正则替换，防止误伤。注意 PKG_HASH 必须匹配行首
    sed -i -E "s/^(GO_VERSION_MAJOR_MINOR\s*[:?]=\s*).*/\1$B_MM/" "$BOOTSTRAP_MAKEFILE"
    sed -i -E "s/^(GO_VERSION_PATCH\s*[:?]=\s*).*/\1$B_PATCH/" "$BOOTSTRAP_MAKEFILE"
    sed -i -E "s/^(PKG_HASH\s*[:?]=\s*).*/\1$B_HASH/" "$BOOTSTRAP_MAKEFILE"
    sed -i -E "s/^(PKG_RELEASE\s*[:?]=\s*).*/\11/" "$BOOTSTRAP_MAKEFILE"
    
    rm -f "$(dirname "$BOOTSTRAP_MAKEFILE")/.built"
    ./scripts/feeds install golang-bootstrap
else
    echo "✅ bootstrap 已是最新。"
fi

# --- 3. 更新主 Golang 版本 ---
echo "---------------------------------------------------------"
echo "🌐 正在检查 $MAJOR_MINOR ..."
NEEDS_REFRESH=false

if [ ! -d "$TARGET_DIR" ]; then 
    echo "⚠️ 发现大版本跳跃，创建 $TARGET_DIR..."
    LATEST_OLD=$(ls -d $BASE_DIR/golang1.* 2>/dev/null | sort -V | tail -n1)
    cp -r "$LATEST_OLD" "$TARGET_DIR"
    
    # 基础修改
    sed -i -E "s/^(PKG_NAME\s*[:?]=\s*).*/\1golang$MAJOR_MINOR/" "$MAKEFILE"
    sed -i -E "s/^(GO_VERSION_MAJOR_MINOR\s*[:?]=\s*).*/\1$MAJOR_MINOR/" "$MAKEFILE"
    rm -rf "$TARGET_DIR/patches"

    # ✨ 核心修复：仅针对 HOST_GO_VALID_OS_ARCH 这一块内容执行下划线到斜杠的转换
    # 这样就不会误伤 PKG_HASH 和 INCLUDE_DIR 了
    echo "🔧 正在转换架构列表格式 (仅限特定区块)..."
    sed -i -E '/^HOST_GO_VALID_OS_ARCH:=/,/^[[:space:]]*$/ s/([a-z0-9]+)_([a-z0-9]+)/\1\/\2/g' "$MAKEFILE"
    
    # 修正可能被误改的其他关键变量（保险措施）
    sed -i 's/GO\/VERSION/GO_VERSION/g' "$MAKEFILE"
    sed -i 's/PKG\/HASH/PKG_HASH/g' "$MAKEFILE"
    sed -i 's/PKG\/NAME/PKG_NAME/g' "$MAKEFILE"
    
    NEEDS_REFRESH=true
fi

# 精准读取本地主版本 Patch
L_P=$(grep -E "^GO_VERSION_PATCH\s*[:?]=" "$MAKEFILE" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "0")

if [ "$PATCH" != "$L_P" ]; then
    echo "🔄 更新 $MAJOR_MINOR 到小版本 $PATCH ..."
    sed -i -E "s/^(GO_VERSION_PATCH\s*[:?]=\s*).*/\1$PATCH/" "$MAKEFILE"
    sed -i -E "s/^(PKG_HASH\s*[:?]=\s*).*/\1$PKG_HASH/" "$MAKEFILE"
    sed -i -E "s/^(PKG_RELEASE\s*[:?]=\s*).*/\11/" "$MAKEFILE"
else
    echo "✅ $MAJOR_MINOR 内容已是最新。"
fi

# --- 4. 默认版本开关 ---
if [ -f "$VALUES_MK" ]; then
    echo "🔧 设置默认版本为 $MAJOR_MINOR"
    sed -i -E "s/^(GO_DEFAULT_VERSION\s*[:?]=\s*).*/\1$MAJOR_MINOR/" "$VALUES_MK"
fi

if [ "$NEEDS_REFRESH" = true ]; then
    ./scripts/feeds update -i
    ./scripts/feeds install "golang$MAJOR_MINOR"
    ./scripts/feeds install golang
fi

echo "✅ 脚本执行完毕！"
