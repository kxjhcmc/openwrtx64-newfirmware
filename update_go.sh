#!/bin/bash
set -e
set -u
set -o pipefail

BASE_DIR="feeds/packages/lang/golang"
VALUES_MK="$BASE_DIR/golang-values.mk"
BOOTSTRAP_DIR="$BASE_DIR/golang-bootstrap"
BOOTSTRAP_MAKEFILE="$BOOTSTRAP_DIR/Makefile"

# 获取全量索引
GO_API_URL_ALL="https://go.dev/dl/?mode=json&include=all"
CURL_OPTIONS="" 

echo "🛠️ 开始执行 Golang 自动更新脚本 (全量模板重写)..."

# --- 1. 获取全量数据 ---
echo "🌐 正在从官网拉取版本索引..."
JSON_ALL=$(curl -s "$CURL_OPTIONS" "$GO_API_URL_ALL")

# 辅助函数：根据前缀获取最新版本和Hash
get_vh() {
    local data=$(echo "$JSON_ALL" | jq -r --arg mm "go$1" '[.[] | select(.version | startswith($mm))][0]')
    local v=$(echo "$data" | jq -r '.version' | sed 's/go//')
    local h=$(echo "$data" | jq -r '.files[] | select(.kind=="source") | .sha256')
    echo "$v|$h"
}

# 计算目标版本 (1.26.0)
T_VH=$(get_vh "1.26"); T_VER=$(echo $T_VH | cut -d'|' -f1); T_HASH=$(echo $T_VH | cut -d'|' -f2)
T_MM=$(echo "$T_VER" | cut -d. -f1,2); T_P=$(echo "$T_VER" | cut -d. -f3); T_P=${T_P:-0}

# 自动推导自举链 (1.24 -> 1.22 -> 1.20)
FB_VH=$(get_vh "1.24"); FB_VER=$(echo $FB_VH | cut -d'|' -f1); FB_HASH=$(echo $FB_VH | cut -d'|' -f2)
FB_MM=$(echo $FB_VER | cut -d. -f1,2); FB_P=$(echo $FB_VER | cut -d. -f3)

IB1_VH=$(get_vh "1.22"); IB1_VER=$(echo $IB1_VH | cut -d'|' -f1); IB1_HASH=$(echo $IB1_VH | cut -d'|' -f2)
IB2_VH=$(get_vh "1.20"); IB2_VER=$(echo $IB2_VH | cut -d'|' -f1); IB2_HASH=$(echo $IB2_VH | cut -d'|' -f2)

echo "🔎 目标: $T_VER | 自举链: $IB2_VER -> $IB1_VER -> $FB_VER"

# --- 2. 核心：从零重写 golang-bootstrap/Makefile ---
# 使用 cat > 直接覆盖旧文件，确保没有任何 sed 残留
echo "📝 正在生成全新的、结构完美的 Makefile ..."

cat > "$BOOTSTRAP_MAKEFILE" <<EOF
# SPDX-License-Identifier: GPL-2.0-only
include \$(TOPDIR)/rules.mk

GO_VERSION_MAJOR_MINOR:=$FB_MM
GO_VERSION_PATCH:=$FB_P
PKG_HASH:=$FB_HASH

PKG_NAME:=golang-bootstrap
PKG_VERSION:=\$(GO_VERSION_MAJOR_MINOR)\$(if \$(GO_VERSION_PATCH),.\$(GO_VERSION_PATCH))
PKG_RELEASE:=1

GO_SOURCE_URLS:=https://go.dev/dl/ \\
                https://dl.google.com/go/ \\
                https://golang.google.cn/dl/ \\
                https://mirrors.nju.edu.cn/golang/ \\
                https://mirrors.ustc.edu.cn/golang/

PKG_SOURCE:=go\$(PKG_VERSION).src.tar.gz
PKG_SOURCE_URL:=\$(GO_SOURCE_URLS)

PKG_MAINTAINER:=George Sapkin <george@sapk.in>
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:golang:go

PKG_HOST_ONLY:=1
HOST_BUILD_DIR:=\$(BUILD_DIR_HOST)/go-\$(PKG_VERSION)
HOST_BUILD_PARALLEL:=1
HOST_GO_PREFIX:=\$(STAGING_DIR_HOSTPKG)
HOST_GO_VERSION_ID:=bootstrap
HOST_GO_ROOT:=\$(HOST_GO_PREFIX)/lib/go-\$(HOST_GO_VERSION_ID)

HOST_GO_VALID_OS_ARCH:= \\
  aix/ppc64 android/386 android/amd64 android/arm android/arm64 \\
  darwin/amd64 darwin/arm64 dragonfly/amd64 \\
  freebsd/386 freebsd/amd64 freebsd/arm freebsd/arm64 freebsd/riscv64 \\
  illumos/amd64 ios/amd64 ios/arm64 js/wasm linux/386 linux/amd64 \\
  linux/arm linux/arm64 linux/loong64 linux/mips linux/mips64 \\
  linux/mips64le linux/mipsle linux/ppc64 linux/ppc64le \\
  linux/riscv64 linux/s390x netbsd/386 netbsd/amd64 netbsd/arm \\
  netbsd/arm64 openbsd/386 openbsd/amd64 openbsd/arm openbsd/arm64 \\
  openbsd/ppc64 openbsd/riscv64 plan9/386 plan9/amd64 plan9/arm \\
  solaris/amd64 wasip1/wasm windows/386 windows/amd64 windows/arm64

BOOTSTRAP_SOURCE:=go1.4-bootstrap-20171003.tar.gz
BOOTSTRAP_HASH:=f4ff5b5eb3a3cae1c993723f3eab519c5bae18866b5e5f96fe1102f0cb5c3e52
BOOTSTRAP_BUILD_DIR:=\$(HOST_BUILD_DIR)/.go_bootstrap

BOOTSTRAP_1_17_SOURCE:=go1.17.13.src.tar.gz
BOOTSTRAP_1_17_HASH:=a1a48b23afb206f95e7bbaa9b898d965f90826f6f1d1fc0c1d784ada0cd300fd
BOOTSTRAP_1_17_BUILD_DIR:=\$(HOST_BUILD_DIR)/.go_bootstrap_1.17

BOOTSTRAP_1_20_SOURCE:=go$IB2_VER.src.tar.gz
BOOTSTRAP_1_20_HASH:=$IB2_HASH
BOOTSTRAP_1_20_BUILD_DIR:=\$(HOST_BUILD_DIR)/.go_bootstrap_1.20

BOOTSTRAP_1_22_SOURCE:=go$IB1_VER.src.tar.gz
BOOTSTRAP_1_22_HASH:=$IB1_HASH
BOOTSTRAP_1_22_BUILD_DIR:=\$(HOST_BUILD_DIR)/.go_bootstrap_1.22

include \$(INCLUDE_DIR)/host-build.mk
include \$(INCLUDE_DIR)/package.mk
include ../golang-compiler.mk
include ../golang-package.mk

PKG_UNPACK:=\$(HOST_TAR) -C "\$(PKG_BUILD_DIR)" --strip-components=1 -xzf "\$(DL_DIR)/\$(PKG_SOURCE)"
HOST_UNPACK:=\$(HOST_TAR) -C "\$(HOST_BUILD_DIR)" --strip-components=1 -xzf "\$(DL_DIR)/\$(PKG_SOURCE)"
BOOTSTRAP_UNPACK:=\$(HOST_TAR) -C "\$(BOOTSTRAP_BUILD_DIR)" --strip-components=1 -xzf "\$(DL_DIR)/\$(BOOTSTRAP_SOURCE)"
BOOTSTRAP_1_17_UNPACK:=\$(HOST_TAR) -C "\$(BOOTSTRAP_1_17_BUILD_DIR)" --strip-components=1 -xzf "\$(DL_DIR)/\$(BOOTSTRAP_1_17_SOURCE)"
BOOTSTRAP_1_20_UNPACK:=\$(HOST_TAR) -C "\$(BOOTSTRAP_1_20_BUILD_DIR)" --strip-components=1 -xzf "\$(DL_DIR)/\$(BOOTSTRAP_1_20_SOURCE)"
BOOTSTRAP_1_22_UNPACK:=\$(HOST_TAR) -C "\$(BOOTSTRAP_1_22_BUILD_DIR)" --strip-components=1 -xzf "\$(DL_DIR)/\$(BOOTSTRAP_1_22_SOURCE)"

RSTRIP:=:

define Package/golang-bootstrap
  \$(call GoPackage/GoSubMenu)
  TITLE:=Go programming language (bootstrap)
  DEPENDS:=\$(GO_ARCH_DEPENDS)
endef

BOOTSTRAP_ROOT_DIR:=\$(call qstrip,\$(CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT))

ifeq (\$(BOOTSTRAP_ROOT_DIR),)
  BOOTSTRAP_ROOT_DIR:=\$(BOOTSTRAP_BUILD_DIR)
  define Download/golang-bootstrap
    FILE:=\$(BOOTSTRAP_SOURCE)
    URL:=\$(GO_SOURCE_URLS)
    HASH:=\$(BOOTSTRAP_HASH)
  endef
  \$(eval \$(call Download,golang-bootstrap))
  define Bootstrap/Prepare
	mkdir -p "\$(BOOTSTRAP_BUILD_DIR)" && \$(BOOTSTRAP_UNPACK) ;
  endef
  Hooks/HostPrepare/Post+=Bootstrap/Prepare
  \$(eval \$(call GoCompiler/AddProfile,Bootstrap,\$(BOOTSTRAP_BUILD_DIR),,bootstrap,\$(GO_HOST_OS_ARCH)))
endif

ifeq (\$(CONFIG_GOLANG_BUILD_BOOTSTRAP),y)

define Download/golang-bootstrap-1.17
  FILE:=\$(BOOTSTRAP_1_17_SOURCE)
  URL:=\$(GO_SOURCE_URLS)
  HASH:=\$(BOOTSTRAP_1_17_HASH)
endef
\$(eval \$(call Download,golang-bootstrap-1.17))
define Bootstrap-1.17/Prepare
	mkdir -p "\$(BOOTSTRAP_1_17_BUILD_DIR)" && \$(BOOTSTRAP_1_17_UNPACK) ;
endef
Hooks/HostPrepare/Post+=Bootstrap-1.17/Prepare
\$(eval \$(call GoCompiler/AddProfile,Bootstrap-1.17,\$(BOOTSTRAP_1_17_BUILD_DIR),,bootstrap-1.17,\$(GO_HOST_OS_ARCH)))

define Download/golang-bootstrap-1.20
  FILE:=\$(BOOTSTRAP_1_20_SOURCE)
  URL:=\$(GO_SOURCE_URLS)
  HASH:=\$(BOOTSTRAP_1_20_HASH)
endef
\$(eval \$(call Download,golang-bootstrap-1.20))
define Bootstrap-1.20/Prepare
	mkdir -p "\$(BOOTSTRAP_1_20_BUILD_DIR)" && \$(BOOTSTRAP_1_20_UNPACK) ;
endef
Hooks/HostPrepare/Post+=Bootstrap-1.20/Prepare
\$(eval \$(call GoCompiler/AddProfile,Bootstrap-1.20,\$(BOOTSTRAP_1_20_BUILD_DIR),,bootstrap-1.20,\$(GO_HOST_OS_ARCH)))

define Download/golang-bootstrap-1.22
  FILE:=\$(BOOTSTRAP_1_22_SOURCE)
  URL:=\$(GO_SOURCE_URLS)
  HASH:=\$(BOOTSTRAP_1_22_HASH)
endef
\$(eval \$(call Download,golang-bootstrap-1.22))
define Bootstrap-1.22/Prepare
	mkdir -p "\$(BOOTSTRAP_1_22_BUILD_DIR)" && \$(BOOTSTRAP_1_22_UNPACK) ;
endef
Hooks/HostPrepare/Post+=Bootstrap-1.22/Prepare
\$(eval \$(call GoCompiler/AddProfile,Bootstrap-1.22,\$(BOOTSTRAP_1_22_BUILD_DIR),,bootstrap-1.22,\$(GO_HOST_OS_ARCH)))

endif

ifeq (\$(CONFIG_GOLANG_BUILD_BOOTSTRAP),y)
  \$(eval \$(call GoCompiler/AddProfile,Host,\$(HOST_BUILD_DIR),\$(HOST_GO_PREFIX),\$(HOST_GO_VERSION_ID),\$(GO_HOST_OS_ARCH)))
endif

HOST_GO_VARS= \\
	GOHOSTARCH="\$(GO_HOST_ARCH)" \\
	GOCACHE="\$(GO_BUILD_CACHE_DIR)" \\
	GOENV=off \\
	CC="\$(HOSTCC_NOCACHE)" \\
	CXX="\$(HOSTCXX_NOCACHE)"

define Host/Configure
	\$(call GoCompiler/Bootstrap/CheckHost,\$(BOOTSTRAP_GO_VALID_OS_ARCH))
	\$(call GoCompiler/Host/CheckHost,\$(HOST_GO_VALID_OS_ARCH))
	mkdir -p "\$(GO_BUILD_CACHE_DIR)"
endef

define Host/Compile
	\$(call GoCompiler/Bootstrap/Make, \\
		\$(HOST_GO_VARS) \\
		CC="\$(HOSTCC_NOCACHE) -std=gnu17" \\
	)
	\$(call GoCompiler/Bootstrap-1.17/Make, \\
		GOROOT_BOOTSTRAP="\$(BOOTSTRAP_ROOT_DIR)" \\
		\$(HOST_GO_VARS) \\
	)
	\$(call GoCompiler/Bootstrap-1.20/Make, \\
		GOROOT_BOOTSTRAP="\$(BOOTSTRAP_1_17_BUILD_DIR)" \\
		\$(HOST_GO_VARS) \\
	)
	\$(call GoCompiler/Bootstrap-1.22/Make, \\
		GOROOT_BOOTSTRAP="\$(BOOTSTRAP_1_20_BUILD_DIR)" \\
		\$(HOST_GO_VARS) \\
	)
	\$(call GoCompiler/Host/Make, \\
		GOROOT_BOOTSTRAP="\$(BOOTSTRAP_1_22_BUILD_DIR)" \\
		\$(if \$(HOST_GO_ENABLE_PIE),GO_LDFLAGS="-buildmode pie") \\
		\$(HOST_GO_VARS) \\
	)
endef

define Host/Install
	\$(call Host/Uninstall)
	\$(call GoCompiler/Host/Install/Bin)
	\$(call GoCompiler/Host/Install/Src)
	rm -rf "\$(HOST_GO_ROOT)/pkg/\$(GO_HOST_OS_ARCH)"
	\$(INSTALL_DIR) "\$(STAGING_DIR_HOSTPKG)/bin"
	\$(INSTALL_BIN) ../go-strip-helper "\$(STAGING_DIR_HOSTPKG)/bin"
	\$(INSTALL_DIR) "\$(HOST_GO_ROOT)/openwrt"
	\$(INSTALL_BIN) ../go-gcc-helper "\$(HOST_GO_ROOT)/openwrt"
	\$(LN) go-gcc-helper "\$(HOST_GO_ROOT)/openwrt/gcc"
	\$(LN) go-gcc-helper "\$(HOST_GO_ROOT)/openwrt/g++"
endef

define Host/Uninstall
	rm -f "\$(STAGING_DIR_HOSTPKG)/bin/go-strip-helper"
	rm -rf "\$(HOST_GO_ROOT)/openwrt"
	\$(call GoCompiler/Host/Uninstall)
endef

ifeq (\$(CONFIG_GOLANG_BUILD_BOOTSTRAP),y)
  \$(eval \$(call HostBuild))
else
  host-compile:
endif

\$(eval \$(call BuildPackage,golang-bootstrap))
EOF

echo "✅ golang-bootstrap/Makefile 重构完成！"
./scripts/feeds install golang-bootstrap

# --- 3. 更新主程序 golang1.xx ---
echo "---------------------------------------------------------"
echo "🌐 检查主程序 $T_MM 状态..."
TARGET_DIR="$BASE_DIR/golang$T_MM"
MAKEFILE_T="$TARGET_DIR/Makefile"
NEEDS_REFRESH=false

if [ ! -d "$TARGET_DIR" ]; then 
    echo "⚠️ 创建新目录: $TARGET_DIR ..."
    LATEST_OLD=$(ls -d $BASE_DIR/golang1.* 2>/dev/null | sort -V | tail -n1)
    cp -r "$LATEST_OLD" "$TARGET_DIR"
    sed -i -E "s/^(PKG_NAME\s*[:?]=\s*).*/\1golang$T_MM/" "$MAKEFILE_T"
    sed -i -E "s/^(GO_VERSION_MAJOR_MINOR\s*[:?]=\s*).*/\1$T_MM/" "$MAKEFILE_T"
    rm -rf "$TARGET_DIR/patches"
    sed -i -E '/^HOST_GO_VALID_OS_ARCH:=/,/^[[:space:]]*$/ s/([a-z0-9]+)_([a-z0-9]+)/\1\/\2/g' "$MAKEFILE_T"
    NEEDS_REFRESH=true
fi

sed -i -E "s/^(GO_VERSION_PATCH\s*[:?]=\s*).*/\1$T_P/" "$MAKEFILE_T"
sed -i -E "s/^(PKG_HASH\s*[:?]=\s*).*/\1$T_HASH/" "$MAKEFILE_T"
sed -i -E "s/^(PKG_RELEASE\s*[:?]=\s*).*/\11/" "$MAKEFILE_T"

# --- 4. 默认版本开关 ---
if [ -f "$VALUES_MK" ]; then
    sed -i -E "s/^(GO_DEFAULT_VERSION\s*[:?]=\s*).*/\1$T_MM/" "$VALUES_MK"
fi

if [ "$NEEDS_REFRESH" = true ]; then
    ./scripts/feeds update -i
    ./scripts/feeds install "golang$T_MM"
    ./scripts/feeds install golang
fi

echo "🚀 全部流程成功完成！"
