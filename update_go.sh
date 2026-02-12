#!/bin/bash

BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"

# 1. 获取官方最新版本
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2)
PATCH=$(echo "$FULL_VER" | cut -d. -f3); PATCH=${PATCH:-0}
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

TARGET_DIR="$BASE_DIR/golang$MAJOR_MINOR"
MAKEFILE="$TARGET_DIR/Makefile"
NEED_REINDEX=false

# 2. 判断是否是大版本跳跃
if [ ! -d "$TARGET_DIR" ]; then
    echo "⚠️ 发现新大版本 $MAJOR_MINOR，正在初始化目录..."
    LATEST_OLD_DIR=$(ls -d $BASE_DIR/golang1.* 2>/dev/null | sort -V | tail -n1)
    cp -r "$LATEST_OLD_DIR" "$TARGET_DIR"
    
    # 修改新 Makefile 内部包名和主版本
    sed -i "s/^PKG_NAME:=.*/PKG_NAME:=golang$MAJOR_MINOR/" "$MAKEFILE"
    sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$MAKEFILE"
    
    NEED_REINDEX=true
fi

# 3. 更新版本号和 Hash
echo "📝 更新 $TARGET_DIR 到 $FULL_VER"
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE"

# 4. 切换默认版本
sed -i "s/^GO_DEFAULT_VERSION:=.*/GO_DEFAULT_VERSION:=$MAJOR_MINOR/" "$VALUES_MK"

# 5. ✨ 只有在需要时才刷新索引并强制链接
if [ "$NEED_REINDEX" = true ]; then
    echo "🔄 正在为新版本注册 feeds 索引..."
    ./scripts/feeds update -i
    ./scripts/feeds install "golang$MAJOR_MINOR"
    ./scripts/feeds install golang
fi

echo "🚀 Golang 更新流程结束"
