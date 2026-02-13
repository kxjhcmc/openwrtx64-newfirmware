#!/bin/bash
set -e
set -u
set -o pipefail

BASE_DIR="feeds/packages/lang/golang"
RAW_URL="https://raw.githubusercontent.com/openwrt/packages/master/lang/golang"
GO_API_URL="https://go.dev/dl/?mode=json"

echo "🛠️ 开始执行 Golang 自动更新脚本 (终极健壮版)..."

# --- 辅助函数：稳健下载官方文件 ---
download_official() {
    local path="$1"
    local output="$2"
    mkdir -p "$(dirname "$output")"
    echo "📥 正在同步: $RAW_URL/$path -> $output ..."
    if curl -fsSL -m 15 "$RAW_URL/$path" -o "$output"; then
        return 0
    else
        echo "❌ 下载失败或文件不存在: $RAW_URL/$path"
        return 1
    fi
}

# --- 1. 获取官网最新稳定版 ---
GO_DATA=$(curl -s "$GO_API_URL" | jq -r '[.[] | select(.stable==true)][0]')
T_VER_OFFICIAL=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
T_MM_OFFICIAL=$(echo "$T_VER_OFFICIAL" | cut -d. -f1,2)
T_P_OFFICIAL=$(echo "$T_VER_OFFICIAL" | cut -d. -f3); T_P_OFFICIAL=${T_P_OFFICIAL:-0}
T_HASH_OFFICIAL=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

echo "🔎 官网最新稳定版本: $T_VER_OFFICIAL"

# --- 2. 获取本地当前版本信息 ---
CURRENT_LOCAL_MM_FULL_PATH=$(ls -d "$BASE_DIR/golang1."* 2>/dev/null | sort -V | tail -n1 || echo "")
CURRENT_LOCAL_MM=$(basename "$CURRENT_LOCAL_MM_FULL_PATH" | sed 's/golang//' || echo "")

FINAL_T_MM="" 
FINAL_T_VER=""
FINAL_T_P=""
FINAL_T_HASH=""

PERFORM_MAJOR_UPDATE=false
NEEDS_REFRESH=false 


# --- 3. 判定最终目标版本 (FINAL_T_MM) ---
if [ -z "$CURRENT_LOCAL_MM" ]; then
    echo "⚠️ 本地未找到任何 golang1.x 目录，假定为首次安装或严重清理。将尝试安装官网最新主版本。"
    FINAL_T_MM="$T_MM_OFFICIAL"
    PERFORM_MAJOR_UPDATE=true
elif [ "$CURRENT_LOCAL_MM" != "$T_MM_OFFICIAL" ]; then
    echo "⚠️ 检测到大版本更新: 本地 $CURRENT_LOCAL_MM -> 官网 $T_MM_OFFICIAL"
    
    if curl -fsSL -m 10 --output /dev/null "$RAW_URL/golang$T_MM_OFFICIAL/Makefile"; then
        echo "✅ 官方 GitHub 已同步 $T_MM_OFFICIAL 目录，将执行大版本更新。"
        FINAL_T_MM="$T_MM_OFFICIAL"
        PERFORM_MAJOR_UPDATE=true
    else
        echo "❌ 官方 GitHub 尚未同步 $T_MM_OFFICIAL 目录。脚本将安全地停留在本地最高版本 $CURRENT_LOCAL_MM。"
        FINAL_T_MM="$CURRENT_LOCAL_MM"
    fi
else
    FINAL_T_MM="$T_MM_OFFICIAL"
fi

# 🚀 关键修复：确保 TARGET_LOCAL_DIR 在 FINAL_T_MM 确定后立即定义
TARGET_LOCAL_DIR="$BASE_DIR/golang$FINAL_T_MM" 

# 获取最终目标版本的详细信息
GO_DATA=$(curl -s "$GO_API_URL" | jq -r --arg mm "go$FINAL_T_MM" '[.[] | select(.version | startswith($mm))][0]')
FINAL_T_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
FINAL_T_MM_FROM_DATA=$(echo "$GO_DATA" | jq -r '.version' | cut -d. -f1,2 | sed 's/go//') # 从 $GO_DATA 获取 FINAL_T_MM
FINAL_T_P=$(echo "$FINAL_T_VER" | cut -d. -f3); FINAL_T_P=${FINAL_T_P:-0}
FINAL_T_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

echo "📈 最终目标 Go 版本系列: $FINAL_T_MM (最新小版: $FINAL_T_VER)"


# 检查当前本地文件中的版本号 (用于判断是否需要更新)
MAKEFILE_T="$BASE_DIR/golang$FINAL_T_MM/Makefile"
if [ -f "$MAKEFILE_T" ]; then
    LOCAL_FINAL_T_P=$(grep -E "^GO_VERSION_PATCH\s*[:?]=" "$MAKEFILE_T" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "-1")
    LOCAL_FINAL_T_VER="$FINAL_T_MM.$LOCAL_FINAL_T_P"
else
    LOCAL_FINAL_T_P="-1"
    LOCAL_FINAL_T_VER="$FINAL_T_MM.-1"
fi
echo "📂 本地 $FINAL_T_MM 系列版本: $LOCAL_FINAL_T_VER"

# --- 4. 核心：版本一致性判断，如果一致则直接退出 ---
if [ "$FINAL_T_VER" = "$LOCAL_FINAL_T_VER" ]; then
    # 额外检查 golang-values.mk 是否也一致，防止因它不同而跳过更新
    L_DEF_MM_CHECK=$(grep -E "^GO_DEFAULT_VERSION\s*[:?]=\s*$(echo "$FINAL_T_MM" | sed 's/\./\\./g')" "$BASE_DIR/golang-values.mk" || true)
    if [ "$L_DEF_MM_CHECK" != "" ]; then
        echo "✅ Go 版本 ($FINAL_T_VER) 和默认配置已是最新，无需更新。脚本退出。"
        exit 0
    fi
fi

echo "🔄 检测到版本不一致或配置需更新，继续执行..."


# --- 5. 执行文件维护与同步 ---
if [ "$PERFORM_MAJOR_UPDATE" = true ]; then
    echo "🔄 正在执行大版本切换操作..."
    
    if [ -d "$CURRENT_LOCAL_MM_FULL_PATH" ] && [ "$CURRENT_LOCAL_MM" != "$FINAL_T_MM" ]; then
        echo "🔄 重命名目录 $CURRENT_LOCAL_MM_FULL_PATH 为 $TARGET_LOCAL_DIR ..."
        mv "$CURRENT_LOCAL_MM_FULL_PATH" "$TARGET_LOCAL_DIR"
    elif [ ! -d "$TARGET_LOCAL_DIR" ]; then
        echo "➕ 创建新目录 $TARGET_LOCAL_DIR ..."
        mkdir -p "$TARGET_LOCAL_DIR"
    fi
    NEEDS_REFRESH=true

    echo "⚙️ 正在同步 $FINAL_T_MM 系列的官方核心配置文件..."
    download_official "golang-values.mk" "$BASE_DIR/golang-values.mk"
    download_official "golang-bootstrap/Makefile" "$BASE_DIR/golang-bootstrap/Makefile"
    download_official "golang$FINAL_T_MM/Makefile" "$TARGET_LOCAL_DIR/Makefile"
else
    echo "⚙️ 正在确保 golang-bootstrap 和 golang-values 是最新版 (小版本追更时同步)..."
    download_official "golang-values.mk" "$BASE_DIR/golang-values.mk"
    download_official "golang-bootstrap/Makefile" "$BASE_DIR/golang-bootstrap/Makefile"
fi


# --- 6. 执行小版本追更 (针对确定的 $FINAL_T_MM) ---
# MAKEFILE_T 路径已在上面定义
if [ ! -f "$MAKEFILE_T" ]; then
    echo "❌ 错误: 目标 Makefile $MAKEFILE_T 不存在，无法进行小版本更新。 (此错误不应发生)"
    exit 1
fi

if [ "$FINAL_T_P" != "$LOCAL_FINAL_T_P" ]; then
    echo "🔄 执行小版本更新: $FINAL_T_MM.$LOCAL_FINAL_T_P -> $FINAL_T_MM.$FINAL_T_P"
    sed -i -E "s/^(GO_VERSION_PATCH\s*[:?]=\s*).*/\1$FINAL_T_P/" "$MAKEFILE_T"
    sed -i -E "s/^(PKG_HASH\s*[:?]=\s*).*/\1$FINAL_T_HASH/" "$MAKEFILE_T"
    sed -i -E "s/^(PKG_RELEASE\s*[:?]=\s*).*/\11/" "$MAKEFILE_T"
    NEEDS_REFRESH=true
else
    echo "✅ $FINAL_T_MM 系列 Makefile 内容已是最新。"
fi

# --- 7. 维护默认版本开关 (golang-values.mk) ---
VALUES_MK="$BASE_DIR/golang-values.mk"
if [ -f "$VALUES_MK" ]; then
    L_DEF_MM=$(grep -E "^GO_DEFAULT_VERSION\s*[:?]=" "$VALUES_MK" | cut -d= -f2 | tr -d '[:space:]' || echo "")
    if [ "$L_DEF_MM" != "$FINAL_T_MM" ]; then
        echo "🔧 切换系统默认 Go 版本: $L_DEF_MM -> $FINAL_T_MM"
        sed -i -E "s/^(GO_DEFAULT_VERSION\s*[:?]=\s*).*/\1$FINAL_T_MM/" "$VALUES_MK"
        NEEDS_REFRESH=true
    fi
fi

# --- 8. 刷新编译系统 ---
if [ "$NEEDS_REFRESH" = true ]; then
    echo "🔄 正在刷新 feeds 索引并强制重新注册包..."
    ./scripts/feeds update -i 
    ./scripts/feeds install "golang$FINAL_T_MM"
    ./scripts/feeds install golang
    ./scripts/feeds install golang-bootstrap
fi

echo "🚀 Golang 自动化流程处理完成！"
