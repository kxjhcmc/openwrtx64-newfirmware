#!/bin/bash

# 基础路径
BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"

# 1. 获取 Go 官网最新版本
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2) # 比如 1.26
PATCH=$(echo "$FULL_VER" | cut -d. -f3)         # 比如 1
PATCH=${PATCH:-0}
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

TARGET_DIR="$BASE_DIR/golang$MAJOR_MINOR"

# 2. 判断是否需要创建新版本文件夹 (例如 1.25 -> 1.26)
if [ ! -d "$TARGET_DIR" ]; then
    echo "发现新大版本 $MAJOR_MINOR，正在创建新目录..."
    # 找一个现有的旧版本目录作为模板
    TEMPLATE_DIR=$(ls -d $BASE_DIR/golang1.* | sort -V | tail -n1)
    cp -r "$TEMPLATE_DIR" "$TARGET_DIR"
    
    # 修正新目录 Makefile 的包名和主版本
    sed -i "s/^PKG_NAME:=.*/PKG_NAME:=golang$MAJOR_MINOR/" "$TARGET_DIR/Makefile"
    sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$TARGET_DIR/Makefile"
fi

# 3. 更新目标目录下的具体版本和 Hash
echo "更新 $TARGET_DIR 的版本至 $FULL_VER"
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$TARGET_DIR/Makefile"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$TARGET_DIR/Makefile"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$TARGET_DIR/Makefile"

# 4. 修改全局默认版本（最核心的一步）
echo "修改 golang-values.mk，设置默认版本为 $MAJOR_MINOR"
sed -i "s/^GO_DEFAULT_VERSION:=.*/GO_DEFAULT_VERSION:=$MAJOR_MINOR/" "$VALUES_MK"

echo "✅ 升级成功！"
