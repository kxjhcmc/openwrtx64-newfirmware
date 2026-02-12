#!/bin/bash
set -e
set -u
set -o pipefail

BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"
BOOTSTRAP_MAKEFILE="$BASE_DIR/golang-bootstrap/Makefile"

# 1. 获取官方最新稳定版 Golang 信息 (目标版本)
echo "🌐 正在检查 Golang 官方最新稳定版本..."
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//') # 例如 1.27.0
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2) # 例如 1.27
PATCH=$(echo "$FULL_VER" | cut -d. -f3); PATCH=${PATCH:-0}
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

TARGET_GO_MM_INT=$(echo "$MAJOR_MINOR" | sed 's/\.//') # 127 for 1.27

TARGET_DIR="$BASE_DIR/golang$MAJOR_MINOR"
MAKEFILE="$TARGET_DIR/Makefile"

echo "🔎 官网最新 Golang 稳定版: $FULL_VER (目标)"

# 2. 检查当前本地已安装的 Golang 版本 (通过 default 配置)
# 这一步是为了判断是“大版本跳跃”还是“小版本追更”
CURRENT_DEFAULT_MM_FROM_VALUES_MK="unknown"
if [ -f "$VALUES_MK" ]; then
    CURRENT_DEFAULT_MM_FROM_VALUES_MK=$(grep '^GO_DEFAULT_VERSION:=' "$VALUES_MK" | cut -d= -f2)
fi
echo "📂 OpenWrt 配置的默认 Go 主版本: $CURRENT_DEFAULT_MM_FROM_VALUES_MK"

# 3. 检查并更新 golang-bootstrap (优先级最高，因为它是所有 Go 编译的基石)
echo "---------------------------------------------------------"
echo "⚙️ 正在检查并更新 golang-bootstrap 版本..."

# 计算目标版本所需的最低引导版本 (通常是 N-2)。例如 1.27 需要 1.25.x 作为引导。
# 如果 N-2版本过老（例如 OpenWrt 仓库里没有 N-2 的 Makefile），则找 N-1，再找不到就找 N。
REQUIRED_BOOTSTRAP_MM_INT=$((TARGET_GO_MM_INT - 2))
REQUIRED_BOOTSTRAP_MAJOR_MINOR=$(echo "$REQUIRED_BOOTSTRAP_MM_INT" | sed 's/\(..\)/\1./')

# 寻找满足最低要求的最新稳定版作为引导器
# 优先找 N-2，找不到则找 N-1，再找不到就找 N (当前目标版本)
BOOTSTRAP_GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r --arg req_mm "go$REQUIRED_BOOTSTRAP_MAJOR_MINOR" --arg next_req_mm "go$((REQUIRED_BOOTSTRAP_MM_INT + 1))" --arg target_mm "go$MAJOR_MINOR" \
  '[.[] | select(.stable==true and (.version | startswith($req_mm) or .version | startswith($next_req_mm) or .version | startswith($target_mm)))][0]')

BOOTSTRAP_FULL_VER=$(echo "$BOOTSTRAP_GO_DATA" | jq -r '.version' | sed 's/go//')
BOOTSTRAP_PATCH=$(echo "$BOOTSTRAP_FULL_VER" | cut -d. -f3); BOOTSTRAP_PATCH=${BOOTSTRAP_PATCH:-0}
BOOTSTRAP_PKG_HASH=$(echo "$BOOTSTRAP_GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')
BOOTSTRAP_MAJOR_MINOR=$(echo "$BOOTSTRAP_FULL_VER" | cut -d. -f1,2)

echo "Calculated minimum bootstrap: Go $REQUIRED_BOOTSTRAP_MAJOR_MINOR.x"
echo "Selected official bootstrap: $BOOTSTRAP_FULL_VER"

# 读取当前本地 bootstrap 版本
CURRENT_BOOTSTRAP_MM="0.0" # 默认值，防止文件不存在
CURRENT_BOOTSTRAP_P="0"
if [ -f "$BOOTSTRAP_MAKEFILE" ]; then
    CURRENT_BOOTSTRAP_MM=$(grep '^GO_VERSION_MAJOR_MINOR:=' "$BOOTSTRAP_MAKEFILE" | cut -d= -f2)
    CURRENT_BOOTSTRAP_P=$(grep '^GO_VERSION_PATCH:=' "$BOOTSTRAP_MAKEFILE" | cut -d= -f2)
fi
CURRENT_BOOTSTRAP_VER="${CURRENT_BOOTSTRAP_MM}.${CURRENT_BOOTSTRAP_P}"

echo "Current local bootstrap: $CURRENT_BOOTSTRAP_VER"

# 比较并更新 bootstrap
if [ "$BOOTSTRAP_FULL_VER" != "$CURRENT_BOOTSTRAP_VER" ]; then
    echo "🔄 检测到 golang-bootstrap 需要更新..."
    
    # 如果 bootstrap Makefile 不存在，需要创建（通常不会发生，因为它是 feeds 里的核心包）
    if [ ! -f "$BOOTSTRAP_MAKEFILE" ]; then
        echo "❌ 错误: golang-bootstrap/Makefile 不存在，无法更新。请检查 OpenWrt feeds。"
        exit 1
    fi

    sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$BOOTSTRAP_MAJOR_MINOR/" "$BOOTSTRAP_MAKEFILE"
    sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$BOOTSTRAP_PATCH/" "$BOOTSTRAP_MAKEFILE"
    # 如果 bootstrap Makefile 中有 GO_VERSION_RC，确保稳定版时为空
    if grep -q "^GO_VERSION_RC:=" "$BOOTSTRAP_MAKEFILE"; then
        sed -i "s/^GO_VERSION_RC:=.*/GO_VERSION_RC:=/" "$BOOTSTRAP_MAKEFILE"
    fi
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$BOOTSTRAP_PKG_HASH/" "$BOOTSTRAP_MAKEFILE"
    sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$BOOTSTRAP_MAKEFILE"
    echo "🚀 golang-bootstrap 已更新至 $BOOTSTRAP_FULL_VER"
    
    # 清理和强制安装 bootstrap 包
    # 这一步必须在 `openwrt` 目录，否则路径不对
    echo "🧹 清理旧的 golang-bootstrap 编译缓存并刷新索引..."
    rm -rf "$(dirname "$BOOTSTRAP_MAKEFILE")/golang-bootstrap/patches"
    rm -rf "$(dirname "$BOOTSTRAP_MAKEFILE")/golang-bootstrap/.pkgdir"
    rm -rf "$(dirname "$BOOTSTRAP_MAKEFILE")/golang-bootstrap/tmp"
    rm -rf "$(dirname "$BOOTSTRAP_MAKEFILE")/golang-bootstrap/.built"
    ./scripts/feeds install golang-bootstrap
else
    echo "✅ golang-bootstrap 已是最新版本 ($BOOTSTRAP_FULL_VER)，无需更新。"
fi
echo "---------------------------------------------------------"


# 4. 检查并更新目标 Golang 版本 (支持大版本跳跃和小版本追更)
echo "🌐 正在检查并更新主 Golang 版本到 $FULL_VER ..."

# 标志，指示是否需要刷新 feeds 索引
NEEDS_FEEDS_REFRESH=false

# 场景 1: 大版本跳跃 (e.g., local 1.25, official 1.27)
if [ ! -d "$TARGET_DIR" ]; then
    echo "⚠️ 发现大版本跳跃，正在创建新目录 $TARGET_DIR..."
    # 找到版本号最大的旧目录作为模板 (即使是官方已经提供的旧版本，如golang1.26)
    LATEST_OLD_DIR=$(ls -d $BASE_DIR/golang1.* 2>/dev/null | sort -V | tail -n1)
    
    if [ -z "$LATEST_OLD_DIR" ] || [ ! -d "$LATEST_OLD_DIR" ]; then
        echo "❌ 错误: 找不到任何 golang1.x 目录作为模板！无法创建新版本目录。"
        exit 1
    fi
    
    cp -r "$LATEST_OLD_DIR" "$TARGET_DIR"
    
    # 修改新 Makefile 内部基础变量 (PKG_NAME, GO_VERSION_MAJOR_MINOR)
    sed -i "s/^PKG_NAME:=.*/PKG_NAME:=golang$MAJOR_MINOR/" "$MAKEFILE"
    sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$MAKEFILE"
    
    # 删除旧版本补丁，因为大版本更新补丁通常不兼容
    rm -rf "$TARGET_DIR/patches"
    echo "🗑️ 已移除旧版本补丁以防止编译失败。"

    # 检查并修复架构列表格式 (下划线转斜杠)，以防从 1.25 跳到 1.26+
    if grep -q "linux_amd64" "$MAKEFILE" && ! grep -q "linux/amd64" "$MAKEFILE"; then
        echo "🔧 检测到旧版架构列表格式，正在转换为 1.26+ 的斜杠格式..."
        sed -i 's/_/\//g' "$MAKEFILE"
        # 修复因全局替换可能误伤的变量名
        sed -i 's/GO\/VERSION/GO_VERSION/g' "$MAKEFILE"
        sed -i 's/PKG\/NAME/PKG_NAME/g' "$MAKEFILE"
        sed -i 's/PKG\/VERSION/PKG_VERSION/g' "$MAKEFILE"
        sed -i 's/PKG\/RELEASE/PKG_RELEASE/g' "$MAKEFILE"
        sed -i 's/PKG\/SOURCE/PKG_SOURCE/g' "$MAKEFILE"
    fi

    NEEDS_FEEDS_REFRESH=true
    echo "📦 新目录 $TARGET_DIR 初始化完成。"
else
    echo "✅ $TARGET_DIR 目录已存在。"
fi

# 读取当前目标 Go 版本的补丁号，以便比较
CURRENT_TARGET_P="0"
if [ -f "$MAKEFILE" ]; then
    CURRENT_TARGET_P=$(grep '^GO_VERSION_PATCH:=' "$MAKEFILE" | cut -d= -f2)
fi
CURRENT_TARGET_VER="${MAJOR_MINOR}.${CURRENT_TARGET_P}"

# 场景 2: 小版本追更 (或大版本跳跃后的 Makefile 内容更新)
if [ "$FULL_VER" != "$CURRENT_TARGET_VER" ]; then
    echo "🔄 检测到主 Golang 版本内容需要更新 ($CURRENT_TARGET_VER -> $FULL_VER)..."
    sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE"
    if grep -q "^GO_VERSION_RC:=" "$MAKEFILE"; then
        sed -i "s/^GO_VERSION_RC:=.*/GO_VERSION_RC:=/" "$MAKEFILE"
    fi
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE"
    sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE"
    echo "🚀 $MAJOR_MINOR 已更新至 $FULL_VER"
else
    echo "✅ $MAJOR_MINOR 已是最新版本 ($FULL_VER)，无需内容更新。"
fi

# 确保默认版本开关指向最新 (无论更新与否，确保一致性)
sed -i "s/^GO_DEFAULT_VERSION:=.*/GO_DEFAULT_VERSION:=$MAJOR_MINOR/" "$VALUES_MK"

# 强制刷新 feeds 索引和安装新包 (如果发生了大版本跳跃)
if [ "$NEEDS_FEEDS_REFRESH" = true ]; then
    echo "🔄 正在刷新 feeds 索引并安装新创建的 golang$MAJOR_MINOR ..."
    ./scripts/feeds update -i
    ./scripts/feeds install "golang$MAJOR_MINOR"
    ./scripts/feeds install golang # 刷新 dummy 包的依赖
fi

echo "✅ Golang 主版本及其引导器更新流程结束！"
