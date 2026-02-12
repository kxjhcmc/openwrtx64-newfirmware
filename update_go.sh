#!/bin/bash

# 基础路径定义（注意：确保在 feeds update 之后运行，否则目录可能不存在）
BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"

# 1. 获取官方最新版本 JSON
echo "🌐 正在检查 Golang 官方最新版本..."
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2)
PATCH=$(echo "$FULL_VER" | cut -d. -f3)
PATCH=${PATCH:-0}
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

TARGET_DIR="$BASE_DIR/golang$MAJOR_MINOR"
MAKEFILE="$TARGET_DIR/Makefile"

echo "🔎 官网最新版本: $FULL_VER"

# 2. 检查本地现有版本
if [ -f "$VALUES_MK" ]; then
    CURRENT_DEFAULT_MM=$(grep '^GO_DEFAULT_VERSION:=' "$VALUES_MK" | cut -d= -f2)
    # 找到当前默认版本对应的 Makefile 来获取完整版本号
    CHECK_MAKEFILE="$BASE_DIR/golang$CURRENT_DEFAULT_MM/Makefile"
    if [ -f "$CHECK_MAKEFILE" ]; then
        CUR_MM=$(grep '^GO_VERSION_MAJOR_MINOR:=' "$CHECK_MAKEFILE" | cut -d= -f2)
        CUR_P=$(grep '^GO_VERSION_PATCH:=' "$CHECK_MAKEFILE" | cut -d= -f2)
        CURRENT_VER="${CUR_MM}.${CUR_P}"
        echo "📂 本地当前版本: $CURRENT_VER"
        
        if [ "$FULL_VER" = "$CURRENT_VER" ]; then
            echo "✅ 版本一致，无需更新。"
            exit 0
        fi
    fi
fi

# 3. 执行更新逻辑
echo "🔄 检测到更新，正在准备文件..."

# 3a. 大版本跨越处理 (如 1.25 -> 1.26)
if [ ! -d "$TARGET_DIR" ]; then
    echo "⚠️ 发现大版本 $MAJOR_MINOR 目录不存在，正在从旧版本克隆..."
    # 找到版本号最大的旧目录
    LATEST_OLD_DIR=$(ls -d $BASE_DIR/golang1.* 2>/dev/null | sort -V | tail -n1)
    
    if [ -z "$LATEST_OLD_DIR" ]; then
        echo "❌ 错误：在 $BASE_DIR 下找不到任何 golang1.x 目录！"
        exit 1
    fi
    
    cp -r "$LATEST_OLD_DIR" "$TARGET_DIR"
    # 修改新 Makefile 内部的核心变量
    sed -i "s/^PKG_NAME:=.*/PKG_NAME:=golang$MAJOR_MINOR/" "$MAKEFILE"
    sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$MAKEFILE"
fi

# 3b. 更新版本补丁号和 Hash
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE"

# 4. 修改全局默认版本开关
sed -i "s/^GO_DEFAULT_VERSION:=.*/GO_DEFAULT_VERSION:=$MAJOR_MINOR/" "$VALUES_MK"

echo "🚀 成功将 Golang 源码更新至 $FULL_VER"
echo "👉 请紧接着运行 ./scripts/feeds install -a 以完成注册。"
