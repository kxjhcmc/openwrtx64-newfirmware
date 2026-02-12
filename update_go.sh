#!/bin/bash
set -e
set -u
set -o pipefail

BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"
BOOTSTRAP_MAKEFILE="$BASE_DIR/golang-bootstrap/Makefile"

GO_API_URL="https://go.dev/dl/?mode=json"
CURL_OPTIONS="" 

echo "🛠️ 开始执行 Golang 自动更新脚本..."

# --- 辅助函数 ---
get_go_pkg_hash() {
    local hash=$(echo "$1" | jq -r '.files[] | select(.kind=="source") | .sha256')
    echo "$hash"
}

# --- 1. 获取最新版本信息 ---
echo "🌐 正在检查官方最新稳定版本..."
STABLE_JSON=$(curl -s "$CURL_OPTIONS" "$GO_API_URL" | jq -r '[.[] | select(.stable==true)]')
GO_DATA=$(echo "$STABLE_JSON" | jq -r '.[0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2)
PATCH=$(echo "$FULL_VER" | cut -d. -f3); PATCH=${PATCH:-0}
PKG_HASH=$(get_go_pkg_hash "$GO_DATA")

# 转换为整数方便比较 (如 1.26 -> 126)
TARGET_MM_INT=$(echo "$MAJOR_MINOR" | sed 's/\.//')
TARGET_DIR="$BASE_DIR/golang$MAJOR_MINOR"
MAKEFILE="$TARGET_DIR/Makefile"

echo "🔎 官网最新版本: $FULL_VER"

# --- 2. 判定并处理 golang-bootstrap (按需更新) ---
echo "---------------------------------------------------------"
echo "⚙️ 检查 golang-bootstrap 兼容性..."

# 计算最低引导要求 (N-2)
REQ_MM_INT=$((TARGET_MM_INT - 2))
REQ_MM_STR="1.$((REQ_MM_INT - 100))"

# 读取本地当前 bootstrap 版本
L_B_MM=$(grep -E "^GO_VERSION_MAJOR_MINOR\s*[:?]=" "$BOOTSTRAP_MAKEFILE" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "1.0")
L_B_MM_INT=$(echo "$L_B_MM" | sed 's/\.//')

echo "当前引导器: Go $L_B_MM, 目标编译器要求: >= Go $REQ_MM_STR"

if [ "$L_B_MM_INT" -lt "$REQ_MM_INT" ]; then
    echo "🔄 当前引导器版本过低，正在升级 bootstrap..."
    # 选一个合适的稳定版作为新的引导器 (N-2 或列表最老的一个)
    B_GO_DATA=$(echo "$STABLE_JSON" | jq -r --arg req "go$REQ_MM_STR" \
      '([.[] | select(.version | startswith($req))] | first) // .[-1]')
    
    B_FULL_VER=$(echo "$B_GO_DATA" | jq -r '.version' | sed 's/go//')
    B_MM=$(echo "$B_FULL_VER" | cut -d. -f1,2)
    B_PATCH=$(echo "$B_FULL_VER" | cut -d. -f3); B_PATCH=${B_PATCH:-0}
    B_HASH=$(get_go_pkg_hash "$B_GO_DATA")

    sed -i -E "s/^(GO_VERSION_MAJOR_MINOR\s*[:?]=\s*).*/\1$B_MM/" "$BOOTSTRAP_MAKEFILE"
    sed -i -E "s/^(GO_VERSION_PATCH\s*[:?]=\s*).*/\1$B_PATCH/" "$BOOTSTRAP_MAKEFILE"
    sed -i -E "s/^(PKG_HASH\s*[:?]=\s*).*/\1$B_HASH/" "$BOOTSTRAP_MAKEFILE"
    sed -i -E "s/^(PKG_RELEASE\s*[:?]=\s*).*/\11/" "$BOOTSTRAP_MAKEFILE"
    
    rm -f "$(dirname "$BOOTSTRAP_MAKEFILE")/.built"
    ./scripts/feeds install golang-bootstrap
    echo "🚀 bootstrap 已成功升级至 $B_FULL_VER"
else
    echo "✅ 现有引导器符合要求，跳过更新。"
fi

# --- 3. 检查并更新主 Golang 版本 ---
echo "---------------------------------------------------------"
echo "🌐 检查主程序 $MAJOR_MINOR 状态..."
NEEDS_REFRESH=false

if [ ! -d "$TARGET_DIR" ]; then 
    echo "⚠️ 发现大版本跳跃，正在初始化 $TARGET_DIR ..."
    LATEST_OLD=$(ls -d $BASE_DIR/golang1.* 2>/dev/null | sort -V | tail -n1)
    cp -r "$LATEST_OLD" "$TARGET_DIR"
    sed -i -E "s/^(PKG_NAME\s*[:?]=\s*).*/\1golang$MAJOR_MINOR/" "$MAKEFILE"
    sed -i -E "s/^(GO_VERSION_MAJOR_MINOR\s*[:?]=\s*).*/\1$MAJOR_MINOR/" "$MAKEFILE"
    rm -rf "$TARGET_DIR/patches"
    
    # 架构格式转换 (仅限架构区块，防止误伤)
    sed -i -E '/^HOST_GO_VALID_OS_ARCH:=/,/^[[:space:]]*$/ s/([a-z0-9]+)_([a-z0-9]+)/\1\/\2/g' "$MAKEFILE"
    NEEDS_REFRESH=true
fi

# 读取本地主版本补丁号
L_P=$(grep -E "^GO_VERSION_PATCH\s*[:?]=" "$MAKEFILE" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "-1")

if [ "$PATCH" != "$L_P" ]; then
    echo "🔄 发现新补丁/版本，更新 Makefile: $MAJOR_MINOR.$L_P -> $FULL_VER"
    sed -i -E "s/^(GO_VERSION_PATCH\s*[:?]=\s*).*/\1$PATCH/" "$MAKEFILE"
    sed -i -E "s/^(PKG_HASH\s*[:?]=\s*).*/\1$PKG_HASH/" "$MAKEFILE"
    sed -i -E "s/^(PKG_RELEASE\s*[:?]=\s*).*/\11/" "$MAKEFILE"
else
    echo "✅ $MAJOR_MINOR 已经是最新版 ($FULL_VER)。"
fi

# --- 4. 默认版本开关维护 ---
if [ -f "$VALUES_MK" ]; then
    # 检查当前默认版本是否需要切换
    L_DEF_MM=$(grep -E "^GO_DEFAULT_VERSION\s*[:?]=" "$VALUES_MK" | cut -d= -f2 | tr -d '[:space:]' || echo "")
    if [ "$L_DEF_MM" != "$MAJOR_MINOR" ]; then
        echo "🔧 切换系统默认 Go 版本: $L_DEF_MM -> $MAJOR_MINOR"
        sed -i -E "s/^(GO_DEFAULT_VERSION\s*[:?]=\s*).*/\1$MAJOR_MINOR/" "$VALUES_MK"
        NEEDS_REFRESH=true
    fi
fi

if [ "$NEEDS_REFRESH" = true ]; then
    echo "🔄 正在刷新 feeds 索引..."
    ./scripts/feeds update -i
    ./scripts/feeds install "golang$MAJOR_MINOR"
    ./scripts/feeds install golang
fi

echo "✅ 脚本执行完毕！"
