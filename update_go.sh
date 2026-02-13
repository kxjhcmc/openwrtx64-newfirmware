#!/bin/bash
set -e
set -u
set -o pipefail

BASE_DIR="feeds/packages/lang/golang"
RAW_URL="https://raw.githubusercontent.com/openwrt/packages/master/lang/golang"
GO_API_URL="https://go.dev/dl/?mode=json"

echo "🛠️ 开始执行 Golang 自动更新脚本 (高性能逻辑版)..."

# --- 辅助函数：稳健下载官方文件 ---
download_official() {
    local path="$1"
    local output="$2"
    mkdir -p "$(dirname "$output")"
    echo "📥 正在同步: $path ..."
    curl -fsSL -m 15 "$RAW_URL/$path" -o "$output"
    chmod +w "$output" || true
}

# --- 1. 获取官网最新稳定版 ---
GO_DATA=$(curl -s "$GO_API_URL" | jq -r '[.[] | select(.stable==true)][0]')
T_VER_OFFICIAL=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
T_MM_OFFICIAL=$(echo "$T_VER_OFFICIAL" | cut -d. -f1,2)

# --- 2. 获取本地当前版本信息 ---
CURRENT_LOCAL_MM_PATH=$(ls -d "$BASE_DIR/golang1."* 2>/dev/null | sort -V | tail -n1 || echo "")
CURRENT_LOCAL_MM=$(basename "$CURRENT_LOCAL_MM_PATH" | sed 's/golang//' || echo "")

FINAL_T_MM=""
PERFORM_MAJOR_UPDATE=false

# --- 3. 判定最终目标主版本 ---
if [ -z "$CURRENT_LOCAL_MM" ]; then
    echo "⚠️ 本地未找到目录，假定初次安装。"
    FINAL_T_MM="$T_MM_OFFICIAL"
    PERFORM_MAJOR_UPDATE=true
elif [ "$CURRENT_LOCAL_MM" != "$T_MM_OFFICIAL" ]; then
    echo "⚠️ 官网检测到大版本: $T_MM_OFFICIAL (本地: $CURRENT_LOCAL_MM)"
    # 探测官方 GitHub
    if curl -fsSL -m 10 --output /dev/null "$RAW_URL/golang$T_MM_OFFICIAL/Makefile"; then
        echo "✅ 官方已更新 $T_MM_OFFICIAL，准备执行大版本切换。"
        FINAL_T_MM="$T_MM_OFFICIAL"
        PERFORM_MAJOR_UPDATE=true
    else
        echo "❌ 官方尚未同步 $T_MM_OFFICIAL，安全回退至本地版本 $CURRENT_LOCAL_MM。"
        FINAL_T_MM="$CURRENT_LOCAL_MM"
    fi
else
    FINAL_T_MM="$CURRENT_LOCAL_MM"
fi

# --- 4. 获取该主版本线下的最新详细数据 ---
GO_DATA_FINAL=$(curl -s "$GO_API_URL" | jq -r --arg mm "go$FINAL_T_MM" '[.[] | select(.version | startswith($mm))][0]')
FINAL_T_VER=$(echo "$GO_DATA_FINAL" | jq -r '.version' | sed 's/go//')
FINAL_T_P=$(echo "$FINAL_T_VER" | cut -d. -f3); FINAL_T_P=${FINAL_T_P:-0}
FINAL_T_HASH=$(echo "$GO_DATA_FINAL" | jq -r '.files[] | select(.kind=="source") | .sha256')

echo "📈 目标版本线: $FINAL_T_MM | 官网最新小版: $FINAL_T_VER"

# --- 5. 预读本地版本并执行“早退”判断 ---
# 注意：如果是大版本更新，本地目录还没改名，我们需要读 CURRENT_LOCAL_MM_PATH 里的文件
# 如果是小版本更新，读当前 FINAL_T_MM 对应的文件
CHECK_MAKEFILE=""
if [ "$PERFORM_MAJOR_UPDATE" = true ]; then
    CHECK_MAKEFILE="$CURRENT_LOCAL_MM_PATH/Makefile"
else
    CHECK_MAKEFILE="$BASE_DIR/golang$FINAL_T_MM/Makefile"
fi

LOCAL_P="-1"
if [ -f "$CHECK_MAKEFILE" ]; then
    LOCAL_P=$(grep -E "^GO_VERSION_PATCH\s*[:?]=" "$CHECK_MAKEFILE" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "-1")
fi

# 检查默认版本开关
VALUES_MK="$BASE_DIR/golang-values.mk"
CURRENT_VAL_MM=""
if [ -f "$VALUES_MK" ]; then
    CURRENT_VAL_MM=$(grep -E "^GO_DEFAULT_VERSION\s*[:?]=" "$VALUES_MK" | cut -d= -f2 | tr -d '[:space:]' || echo "")
fi

# 🚀 核心判断：如果主版本没变、小版本一致、开关也对 -> 立即退出
if [ "$PERFORM_MAJOR_UPDATE" = false ] && [ "$FINAL_T_P" = "$LOCAL_P" ] && [ "$CURRENT_VAL_MM" = "$FINAL_T_MM" ]; then
    echo "✅ [早退] 本地 Go $FINAL_T_VER 已经是最新且配置正确。无需任何操作。"
    exit 0
fi

# --- 6. 正式开始更新流程 (到这里说明必须有动作了) ---
echo "🔄 检测到不一致，开始更新流程..."
NEEDS_REFRESH=false
TARGET_LOCAL_DIR="$BASE_DIR/golang$FINAL_T_MM"

# A. 大版本目录处理
if [ "$PERFORM_MAJOR_UPDATE" = true ]; then
    if [ -d "$CURRENT_LOCAL_MM_PATH" ] && [ "$CURRENT_LOCAL_MM" != "$FINAL_T_MM" ]; then
        echo "🔄 重命名目录: $CURRENT_LOCAL_MM -> $FINAL_T_MM"
        mv "$CURRENT_LOCAL_MM_PATH" "$TARGET_LOCAL_DIR"
    else
        mkdir -p "$TARGET_LOCAL_DIR"
    fi
    NEEDS_REFRESH=true
fi

# B. 下载官方核心文件
echo "⚙️ 同步官方核心配置文件..."
download_official "golang-values.mk" "$BASE_DIR/golang-values.mk"
download_official "golang-compiler.mk" "$BASE_DIR/golang-compiler.mk"
download_official "golang-package.mk" "$BASE_DIR/golang-package.mk" 
download_official "golang-version.mk" "$BASE_DIR/golang-version.mk" 
download_official "golang-host-build.mk" "$BASE_DIR/golang-host-build.mk" 
download_official "golang-bootstrap/Makefile" "$BASE_DIR/golang-bootstrap/Makefile"
download_official "golang$FINAL_T_MM/Makefile" "$TARGET_LOCAL_DIR/Makefile"


# C. 二次校验并执行小版本 sed 修改 (针对官方 Makefile 还没更新到最新小版本的情况)
# 重新读取刚下载的 Makefile
LOCAL_P_NEW=$(grep -E "^GO_VERSION_PATCH\s*[:?]=" "$TARGET_LOCAL_DIR/Makefile" | head -n1 | cut -d= -f2 | tr -d '[:space:]' || echo "-1")

if [ "$FINAL_T_P" != "$LOCAL_P_NEW" ]; then
    echo "🔄 官方 Makefile 尚在 $FINAL_T_MM.$LOCAL_P_NEW，手动追更至 $FINAL_T_VER ..."
    sed -i -E "s/^(GO_VERSION_PATCH\s*[:?]=\s*).*/\1$FINAL_T_P/" "$TARGET_LOCAL_DIR/Makefile"
    sed -i -E "s/^(PKG_HASH\s*[:?]=\s*).*/\1$FINAL_T_HASH/" "$TARGET_LOCAL_DIR/Makefile"
    sed -i -E "s/^(PKG_RELEASE\s*[:?]=\s*).*/\11/" "$TARGET_LOCAL_DIR/Makefile"
    NEEDS_REFRESH=true
fi

# D. 维护默认版本开关
if [ -f "$VALUES_MK" ]; then
    L_DEF_MM=$(grep -E "^GO_DEFAULT_VERSION\s*[:?]=" "$VALUES_MK" | cut -d= -f2 | tr -d '[:space:]' || echo "")
    if [ "$L_DEF_MM" != "$FINAL_T_MM" ]; then
        echo "🔧 修正默认版本开关: $L_DEF_MM -> $FINAL_T_MM"
        sed -i -E "s/^(GO_DEFAULT_VERSION\s*[:?]=\s*).*/\1$FINAL_T_MM/" "$VALUES_MK"
        NEEDS_REFRESH=true
    fi
fi

# --- 7. 刷新编译系统 ---
if [ "$NEEDS_REFRESH" = true ]; then
    echo "🔄 刷新 feeds 索引..."
    ./scripts/feeds update -i 
    ./scripts/feeds install "golang$FINAL_T_MM"
    ./scripts/feeds install golang
    ./scripts/feeds install golang-bootstrap
fi

echo "🚀 Golang 自动化流程处理完成！"
