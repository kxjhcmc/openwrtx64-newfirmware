#!/bin/bash

# 基础路径定义
BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"

# 1. 获取官方最新版本 JSON
GO_DATA=$(curl -s https://go.dev/dl/?mode=json | jq -r '[.[] | select(.stable==true)][0]')
FULL_VER=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
MAJOR_MINOR=$(echo "$FULL_VER" | cut -d. -f1,2)
PATCH=$(echo "$FULL_VER" | cut -d. -f3)
PATCH=${PATCH:-0}
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

TARGET_DIR="$BASE_DIR/golang$MAJOR_MINOR"
MAKEFILE="$TARGET_DIR/Makefile"

echo "🔎 官网最新版本: $FULL_VER"

# 2. 检查当前本地版本（通过读取总开关对应的 Makefile）
if [ -f "$VALUES_MK" ]; then
    CURRENT_DEFAULT_MM=$(grep '^GO_DEFAULT_VERSION:=' "$VALUES_MK" | cut -d= -f2)
    CURRENT_MAKEFILE="$BASE_DIR/golang$CURRENT_DEFAULT_MM/Makefile"
    
    if [ -f "$CURRENT_MAKEFILE" ]; then
        CUR_MM=$(grep '^GO_VERSION_MAJOR_MINOR:=' "$CURRENT_MAKEFILE" | cut -d= -f2)
        CUR_P=$(grep '^GO_VERSION_PATCH:=' "$CURRENT_MAKEFILE" | cut -d= -f2)
        CURRENT_VER="${CUR_MM}.${CUR_P}"
        
        echo "📂 本地当前版本: $CURRENT_VER"
        
        # 核心对比：版本一致则退出
        if [ "$FULL_VER" = "$CURRENT_VER" ]; then
            echo "✅ 版本一致，无需更新。"
            exit 0
        fi
    fi
fi

# 3. 如果版本不一致，开始更新流程
echo "🔄 检测到更新，正在处理..."

# 3a. 处理大版本目录不存在的情况 (例如从 1.25 升级到 1.26)
if [ ! -d "$TARGET_DIR" ]; then
    echo "⚠️ 发现大版本跳跃，正在创建新目录 $TARGET_DIR..."
    LATEST_OLD_DIR=$(ls -d $BASE_DIR/golang1.* 2>/dev/null | sort -V | tail -n1)
    
    if [ -z "$LATEST_OLD_DIR" ]; then
        echo "❌ 错误：找不到任何旧的 golang1.x 目录作为模板！"
        exit 1
    fi
    
    cp -r "$LATEST_OLD_DIR" "$TARGET_DIR"
    # 必须修正新目录 Makefile 里的 PKG_NAME 和主版本号
    sed -i "s/^PKG_NAME:=.*/PKG_NAME:=golang$MAJOR_MINOR/" "$MAKEFILE"
    sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$MAKEFILE"
fi

# 3b. 修改目标 Makefile 的补丁版本和 Hash
echo "📝 更新 $MAKEFILE 中的版本号和 Hash..."
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE"

# 4. 关键步骤：在 package 目录下创建软链接，让 OpenWrt 识别新包
echo "🔗 正在注册新包 golang$MAJOR_MINOR 到构建系统..."
./scripts/feeds install "golang$MAJOR_MINOR"
# 同时也重新安装一下 dummy 包，确保依赖关系刷新
./scripts/feeds install golang

# 5. 切换系统默认 Go 版本
echo "⚙️ 正在修改 $VALUES_MK 设置默认版本为 $MAJOR_MINOR..."
sed -i "s/^GO_DEFAULT_VERSION:=.*/GO_DEFAULT_VERSION:=$MAJOR_MINOR/" "$VALUES_MK"

echo "🚀 Golang 已成功升级至 $FULL_VER ！"
