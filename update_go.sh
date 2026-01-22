#!/bin/bash

# 配置 Makefile 的相对路径
MAKEFILE_PATH="feeds/packages/lang/golang/golang/Makefile"

# 使用中国官方镜像 API (无需梯子，直连访问)
API_URL="https://golang.google.cn/dl/?mode=json"

if [ ! -f "$MAKEFILE_PATH" ]; then
    echo "错误: 未找到 Makefile，请检查路径: $MAKEFILE_PATH"
    exit 1
fi

# 检查 jq 依赖
if ! command -v jq &> /dev/null; then
    echo "正在安装 jq..."
    sudo apt update && sudo apt install jq -y
fi

echo "正在从中国官方镜像检测最新 Golang 版本..."

# 获取数据：-k 跳过 SSL 检查，-s 静默，-L 跟随重定向
RAW_JSON=$(curl -fskL --retry 3 --connect-timeout 10 "$API_URL")

if [ $? -ne 0 ] || [ -z "$RAW_JSON" ]; then
    echo "错误: 依然无法访问 API。这通常是网络极其不稳定或 DNS 污染导致的。"
    echo "请尝试手动执行: curl -I $API_URL 查看结果。"
    exit 1
fi

# 解析最新的稳定版 (stable)
GO_DATA=$(echo "$RAW_JSON" | jq -r '[.[] | select(.stable==true)][0]')
LATEST_VERSION_FULL=$(echo "$GO_DATA" | jq -r '.version' | sed 's/go//')
PKG_HASH=$(echo "$GO_DATA" | jq -r '.files[] | select(.kind=="source") | .sha256')

if [ "$LATEST_VERSION_FULL" == "null" ] || [ -z "$PKG_HASH" ]; then
    echo "错误: 无法解析版本数据。"
    exit 1
fi

# 解析版本号 (例如 1.23.5 -> 1.23 和 5)
if [[ $LATEST_VERSION_FULL =~ ^([0-9]+\.[0-9]+)\.([0-9]+)$ ]]; then
    MAJOR_MINOR="${BASH_REMATCH[1]}"
    PATCH="${BASH_REMATCH[2]}"
elif [[ $LATEST_VERSION_FULL =~ ^([0-9]+\.[0-9]+)$ ]]; then
    # 处理类似 1.24 这种没有三位版本号的情况
    MAJOR_MINOR="$LATEST_VERSION_FULL"
    PATCH="0"
fi

echo "-------------------------------------------------------"
echo "成功获取最新稳定版信息："
echo "最新版本: $LATEST_VERSION_FULL"
echo "主次版本: $MAJOR_MINOR"
echo "修订版本: $PATCH"
echo "源码哈希: $PKG_HASH"
echo "-------------------------------------------------------"

# 开始修改 Makefile
echo "正在修改 Makefile..."

# 替换 GO_VERSION_MAJOR_MINOR
sed -i "s/^GO_VERSION_MAJOR_MINOR:=.*/GO_VERSION_MAJOR_MINOR:=$MAJOR_MINOR/" "$MAKEFILE_PATH"

# 替换 GO_VERSION_PATCH (如果 PATCH 是 0，根据 OpenWrt 习惯有时可以留空，但写 0 最稳妥)
sed -i "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=$PATCH/" "$MAKEFILE_PATH"

# 替换 PKG_HASH
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$PKG_HASH/" "$MAKEFILE_PATH"

# 重置 PKG_RELEASE 为 1
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" "$MAKEFILE_PATH"

echo "修改完成！"
echo "-------------------------------------------------------"
echo "建议后续操作："
echo "1. 清理旧版本缓存: rm -rf dl/go${LATEST_VERSION_FULL}.src.tar.gz"
echo "2. 强制重新编译 host-golang:"
echo "   make package/feeds/packages/golang/host/compile V=s"