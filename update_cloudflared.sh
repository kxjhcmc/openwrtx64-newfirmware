#!/bin/bash

# update_cloudflared.sh
# 放在 OpenWrt 根目录运行
# 自动检查 cloudflared 最新版本，并更新 feeds/packages/net/cloudflared/Makefile

MAKEFILE="feeds/packages/net/cloudflared/Makefile"
GITHUB_API_URL="https://api.github.com/repos/cloudflare/cloudflared/releases/latest"

# 检查依赖
for cmd in curl jq sha256sum; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误：$cmd 未安装。请先安装 $cmd。"
        exit 1
    fi
done

# 检查 Makefile 是否存在
if [ ! -f "$MAKEFILE" ]; then
    echo "错误：找不到 Makefile: $MAKEFILE"
    exit 1
fi

# 获取最新版本号
echo "正在检查 cloudflared 最新版本..."
LATEST_VERSION=$(curl -s $GITHUB_API_URL | jq -r '.tag_name' | sed 's/^v//')
if [ -z "$LATEST_VERSION" ]; then
    echo "错误：无法获取最新版本号。"
    exit 1
fi
echo "最新版本: $LATEST_VERSION"

# 读取当前版本号
CURRENT_VERSION=$(grep '^PKG_VERSION:=' $MAKEFILE | cut -d= -f2 | tr -d ' ')
if [ -z "$CURRENT_VERSION" ]; then
    echo "错误：无法读取当前版本号。"
    exit 1
fi
echo "当前版本: $CURRENT_VERSION"

# 比较版本号
if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
    echo "当前已是最新版本，无需更新。"
    exit 0
fi

# 获取最新版本的 SHA256 哈希值
echo "正在下载源码包并计算 SHA256 哈希值..."
TARBALL_URL="https://codeload.github.com/cloudflare/cloudflared/tar.gz/$LATEST_VERSION"
TMP_FILE="/tmp/cloudflared-$LATEST_VERSION.tar.gz"
curl -s -L -o $TMP_FILE $TARBALL_URL
if [ $? -ne 0 ]; then
    echo "错误：下载源码包失败。"
    exit 1
fi
LATEST_HASH=$(sha256sum $TMP_FILE | awk '{print $1}')
rm -f $TMP_FILE
if [ -z "$LATEST_HASH" ]; then
    echo "错误：无法计算 SHA256 哈希值。"
    exit 1
fi
echo "最新版本 SHA256: $LATEST_HASH"

# 更新 Makefile
echo "正在更新 Makefile..."
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$LATEST_VERSION/" $MAKEFILE
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$LATEST_HASH/" $MAKEFILE

echo "更新完成！"
echo "新版本: $LATEST_VERSION"
echo "SHA256: $LATEST_HASH"
