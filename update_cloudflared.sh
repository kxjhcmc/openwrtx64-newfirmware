#!/bin/bash

MAKEFILE="feeds/packages/net/cloudflared/Makefile"
GITHUB_API_URL="https://api.github.com/repos/cloudflare/cloudflared/releases/latest"

# 检查依赖
for cmd in curl jq sha256sum tar; do
    if ! command -v $cmd > /dev/null 2>&1; then
        echo "错误：$cmd 未安装。请先安装 $cmd。"
        exit 1
    fi
done

# 可选：使用 GITHUB_TOKEN 认证访问 API（Actions 中默认就有，额度 5000 次/小时，
# 避免 runner IP 被匿名限流导致解析出 null）
API_AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    API_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

# 获取最新版本号
echo "正在检查 cloudflared 最新版本..."
API_RESPONSE=$(curl -s --max-time 60 "${API_AUTH[@]}" "$GITHUB_API_URL")
CURL_RC=$?
if [ $CURL_RC -ne 0 ]; then
    echo "错误：访问 GitHub API 失败（curl 退出码 $CURL_RC）。"
    exit 1
fi

API_MSG=$(echo "$API_RESPONSE" | jq -r '.message // empty')
[ -n "$API_MSG" ] && echo "API 提示: $API_MSG"

LATEST_VERSION=$(echo "$API_RESPONSE" | jq -r '.tag_name // empty' | sed 's/^v//')

# 熔断检查：版本必须是合法的版本号格式（如 2026.10.5 / 2026.10.5-1），
# null、空串、错误消息等直接退出，保持 Makefile 原状
if ! echo "$LATEST_VERSION" | grep -qE '^[0-9]{4}\.[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?$'; then
    echo "错误：未能解析出有效版本号（解析结果: '$LATEST_VERSION'），放弃更新。"
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

# 获取最新版本的 SHA256 哈希值（使用与 OpenWrt 完全一致的 URL）
echo "正在下载源码包并计算 SHA256 哈希值..."
TARBALL_URL="https://codeload.github.com/cloudflare/cloudflared/tar.gz/$LATEST_VERSION"
TMP_FILE="/tmp/cloudflared-$LATEST_VERSION.tar.gz"
# -f 让 404 等错误直接报错而不是把错误页面存下来
curl -fSL --retry 3 --max-time 600 -o "$TMP_FILE" "$TARBALL_URL"
if [ $? -ne 0 ]; then
    echo "错误：下载源码包失败。"
    rm -f "$TMP_FILE"
    exit 1
fi

# 二次校验：确认真的是有效 gzip/tar 包（防止错误页面混入）
if ! tar -tzf "$TMP_FILE" > /dev/null 2>&1; then
    echo "错误：下载内容不是有效的 tar.gz 包，放弃更新。"
    rm -f "$TMP_FILE"
    exit 1
fi

LATEST_HASH=$(sha256sum "$TMP_FILE" | awk '{print $1}')
rm -f "$TMP_FILE"
if [ -z "$LATEST_HASH" ]; then
    echo "错误：无法计算 SHA256 哈希值。"
    exit 1
fi
echo "最新版本 SHA256: $LATEST_HASH"

# 以上全部通过后才写入 Makefile
echo "正在更新 Makefile..."
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$LATEST_VERSION/" $MAKEFILE
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$LATEST_HASH/" $MAKEFILE

echo "更新完成！"
echo "新版本: $LATEST_VERSION"
echo "SHA256: $LATEST_HASH"
