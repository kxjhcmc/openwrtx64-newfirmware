echo "🧩 复制 FastNet 及 LuCI 插件到 packages 目录"

LOCAL_FASTNET_DIR="$GITHUB_WORKSPACE/fastnet"
TARGET_DIR="feeds/packages"

if [ -d "$LOCAL_FASTNET_DIR" ]; then
  # 复制 fastnet 主包
  if [ -d "$LOCAL_FASTNET_DIR/fastnet" ]; then
    cp -rf "$LOCAL_FASTNET_DIR/fastnet" "$TARGET_DIR/"
    echo "✅ fastnet 主包已复制到 $TARGET_DIR/"
  fi

  # 复制 luci-app-fastnet
  if [ -d "$LOCAL_FASTNET_DIR/luci-app-fastnet" ]; then
    cp -rf "$LOCAL_FASTNET_DIR/luci-app-fastnet" "feeds/luci/applications/"
    echo "✅ luci-app-fastnet 已复制到 feeds/luci/applications/"
  fi
else
  echo "⚠️ 未找到 fastnet 目录: $LOCAL_FASTNET_DIR"
fi
