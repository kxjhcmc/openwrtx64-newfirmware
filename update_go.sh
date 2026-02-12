#!/bin/bash

BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"

# 1. 获取当前系统默认的 Golang 主版本号 (例如 1.26)
if [ ! -f "$VALUES_MK" ]; then
    echo "❌ 错误: 找不到 $VALUES_MK，请确保在 feeds update 之后运行。"
    exit 1
fi
CURRENT_DEFAULT_MM=$(grep '^GO_DEFAULT_VERSION:=' "$VALUES_MK" | cut -d= -f2)
echo "📂 当前系统默认 Golang 主版本: $CURRENT_DEFAULT_MM"

# 2. 获取官网针对该主版本号的最新小版本信息
# 这里利用 jq 过滤出匹配当前主版本的最新稳定版
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r --arg mm "go$CURRENT_DEFAULT_MM" '[.[] | select(.version | startswith($mm))][0]')

if [ "$GO_DATA" == "null" ]; then
    echo "⚠️ 官网未找到针对 $CURRENT_DEFAULT_MM 的版本信息，跳过更新。"
    exit 0
fi

FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
PATCH=$(echo "$FULL_VER" | cut -d. -f3); PATCH=${PATCH:-0}
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

TARGET_DIR="$BASE_DIR/golang$CURRENT_DEFAULT_MM"
MAKEFILE="$TARGET_DIR/Makefile"

# 3. 检查本地 Makefile 里的当前小版本号
if [ ! -f "$MAKEFILE" ]; then
    echo "❌ 错误: 找不到目录 $TARGET_DIR"
    exit 1
fi

CUR_PATCH=$(grep '^GO_VERSION_PATCH:=' "$MAKEFILE" | cut -d= -f2)

echo "🔎 官网最新补丁版: $FULL_VER"
echo "📂 本地当前补丁版: $CURRENT_DEFAULT_MM.$CUR_PATCH"

# 4. 比较版本号：如果一致则退出
if [ "$PATCH" == "$CUR_PATCH" ]; then
    echo "✅ Golang $CURRENT_DEFAULT_MM 系列已是最新版本，无需操作。"
    exit 0
fi

# 5. 执行小版本更新 (仅修改 Patch, Hash, Release)
echo "🔄 检测到小版本更新，正在更新 Makefile..."
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE"

echo "🚀 Golang 已成功追更至 $FULL_VER"
