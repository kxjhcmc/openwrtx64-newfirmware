#!/bin/bash

MAKEFILE="feeds/packages/lang/golang/golang1.25/Makefile"

# 1. 获取官方最新版本 JSON
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')

# 2. 读取当前 Makefile 里的版本号
# 组合 MAJOR_MINOR 和 PATCH
CUR_MAJOR=$(grep '^GO_VERSION_MAJOR_MINOR:=' "$MAKEFILE" | cut -d= -f2)
CUR_PATCH=$(grep '^GO_VERSION_PATCH:=' "$MAKEFILE" | cut -d= -f2)
CURRENT_VER="${CUR_MAJOR}.${CUR_PATCH}"

echo "最新版本: $FULL_VER"
echo "当前版本: $CURRENT_VER"

# 3. 比较版本
if [ "$FULL_VER" = "$CURRENT_VER" ]; then
    echo "✅ Golang 当前已是最新版本，跳过更新。"
    exit 0
fi

# 4. 如果不一致，获取哈希并更新
echo "🔄 检测到新版本，正在更新 Makefile..."
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2)
PATCH=$(echo "$FULL_VER" | cut -d. -f3)
PATCH=${PATCH:-0}

sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$MAKEFILE"
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE"

echo "🚀 Golang 已成功更新至 $FULL_VER"
