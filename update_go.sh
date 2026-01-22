#!/bin/bash

MAKEFILE="feeds/packages/lang/golang/golang/Makefile"

# 1. 获取最新稳定版信息
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0]')

# 2. 提取并解析版本号与哈希
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

# 自动拆分主次版本 (1.25.6 -> 1.25 和 6)
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2)
PATCH=$(echo "$FULL_VER" | cut -d. -f3)
PATCH=${PATCH:-0} # 如果没有 patch 位则设为 0

# 3. 写入 Makefile
sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$MAKEFILE"
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE"

echo "Success: Updated Golang to $FULL_VER"
