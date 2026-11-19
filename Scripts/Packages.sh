#!/bin/bash
# 京东云雅典娜 AX6600 自定义插件拉取脚本
# 该脚本在 wrt/package/ 目录下执行（WRT-CORE.yml: cd ./wrt/package/）。
set -euo pipefail

PROFILE=${WRT_PROFILE:-PURE}
CACHE=.athena-pkg-cache
mkdir -p "$CACHE"

log() { echo "[athena-pkg] $*"; }

record_version() {  # name repo branch
	if [ -n "${GITHUB_WORKSPACE:-}" ]; then
		echo "$1 $2 $3 $4" >> "$GITHUB_WORKSPACE/package-versions.txt"
	fi
}

# 删除 feeds 中同名的包目录，避免与本地克隆版本重复定义（同名 package 会导致 defconfig 冲突）
drop_feed_pkg() {
	local NAME
	for NAME in "$@"; do
		find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -name "$NAME" \
			-exec rm -rf {} + 2>/dev/null || true
	done
}

clone_repo() {  # repo branch dest
	local REPO=$1 BRANCH=$2 DEST=$3
	rm -rf "$DEST"
	log "clone $REPO@$BRANCH -> $DEST"
	git clone --depth=1 --single-branch --branch "$BRANCH" "https://github.com/$REPO.git" "$DEST"
	record_version "$DEST" "$REPO" "$BRANCH" "$(git -C "$DEST" rev-parse --short HEAD)"
}

take_pkgs() {  # src-dir pkg-name...
	local SRC=$1; shift
	local NAME
	for NAME in "$@"; do
		if [ -d "$SRC/$NAME" ]; then
			rm -rf "./$NAME"
			cp -r "$SRC/$NAME" "./$NAME"
		else
			log "警告：$SRC 中不存在包目录 $NAME，已跳过"
		fi
	done
}

# ---------------------------------------------------------------- 主题
drop_feed_pkg luci-theme-vantage luci-theme-7dollar luci-theme-carbon
clone_repo anothaDev/luci-theme-vantage     main luci-theme-vantage
clone_repo itsmaiGe/luci-theme-7dollar      main luci-theme-7dollar
clone_repo mrjoechen/luci-theme-carbon      main luci-theme-carbon

# 7dollar 的 .ut 模板静态导入了目标端模块 luci.7dollar，主机侧 ucode 预编译时
# 无法解析该模块（上一次构建失败原因：Unable to resolve path for module 'luci.7dollar'）。
# 关闭该主题的模板预编译，直接安装 .ut 源模板，由路由器运行时解析模块。
if [ -f ./luci-theme-7dollar/Makefile ]; then
	if ! grep -q '^LUCI_MINIFY_UT' ./luci-theme-7dollar/Makefile; then
		sed -i '1i LUCI_MINIFY_UT:=0' ./luci-theme-7dollar/Makefile
	fi
fi

# ---------------------------------------------------------------- dae / honk / Nikki
drop_feed_pkg dae luci-app-dae honk luci-app-honk luci-lib-daeuniverse nikki luci-app-nikki mihomo-meta

clone_repo daeuniverse/openwrt-packages main "$CACHE/daeuniverse"
take_pkgs "$CACHE/daeuniverse" dae honk luci-app-honk luci-app-dae luci-lib-daeuniverse

clone_repo nikkinikki-org/OpenWrt-nikki main "$CACHE/nikki"
take_pkgs "$CACHE/nikki" nikki luci-app-nikki mihomo-meta

# ---------------------------------------------------------------- Open-Box（官方安装器入口）
# Open-Box 内核为闭源发行物，仓库不含可在 buildroot 内编译的 OpenWrt 包配方。
# 固件只内置一个调用官方安装脚本的命令，运行时不打包其专有程序。
mkdir -p ./openbox-athena-installer/files/usr/sbin
cat > ./openbox-athena-installer/files/usr/sbin/openbox-athena-install <<'OPENBOX_EOF'
#!/bin/sh
# 调用 Open-Box 官方安装脚本（固件不包含其专有运行时）
set -eu
fetch() { # url dest
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 10 --max-time 120 "$1" -o "$2"
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -O "$2" "$1"
	else
		wget -q -O "$2" "$1"
	fi
}
for url in \
	https://raw.githubusercontent.com/liandu2024/Open-Box/main/install.sh \
	https://github.com/liandu2024/Open-Box/releases/latest/download/install.sh
do
	tmp=$(mktemp 2>/dev/null || echo /tmp/openbox-install.sh)
	if fetch "$url" "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
		exec sh "$tmp" "$@"
	fi
	rm -f "$tmp"
done
echo "未能下载 Open-Box 官方安装脚本，请访问 https://github.com/liandu2024/Open-Box 手动安装" >&2
exit 1
OPENBOX_EOF
chmod 0755 ./openbox-athena-installer/files/usr/sbin/openbox-athena-install

cat > ./openbox-athena-installer/Makefile <<'OPENBOX_MK'
include $(TOPDIR)/rules.mk

PKG_NAME:=openbox-athena-installer
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/openbox-athena-installer
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Open-Box official installer helper
  URL:=https://github.com/liandu2024/Open-Box
  DEPENDS:=+curl +ca-bundle
endef

define Package/openbox-athena-installer/description
 提供 openbox-athena-install 命令，用于调用 Open-Box 官方安装脚本。
 固件不包含 Open-Box 的专有运行时程序。
endef

define Package/openbox-athena-installer/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/sbin/openbox-athena-install $(1)/usr/sbin/openbox-athena-install
endef

$(eval $(call BuildPackage,openbox-athena-installer))
OPENBOX_MK

# ---------------------------------------------------------------- NaiLink（daed 后继）
# 上游只为 ARM64 发布 daed-router 运行包，LuCI 包没有单独发布（build.py 仅在
# x86_64 目标下产出 LuCI 包）。因此这里用官方源码包提供两个包的配方，运行所需
# 的三个静态二进制取自官方 daed-router 运行包，并按官方 ipk-arm64.tsv 校验摘要。
if [ "$PROFILE" = "PLUS" ]; then
	NAILINK_VERSION=0.6.90
	NAILINK_TAG="openwrt-v${NAILINK_VERSION}"
	NAILINK_BASE="https://github.com/slobys/NaiLink/releases/download/${NAILINK_TAG}"
	NAILINK_IPK="daed-router-${NAILINK_VERSION}-aarch64_cortex-a53.ipk"

	curl -fsSL --retry 3 "${NAILINK_BASE}/${NAILINK_IPK}" -o "$CACHE/$NAILINK_IPK"
	curl -fsSL --retry 3 "${NAILINK_BASE}/ipk-arm64.tsv" -o "$CACHE/ipk-arm64.tsv"
	curl -fsSL --retry 3 "${NAILINK_BASE}/daed-openwrt-source.tar.gz" -o "$CACHE/nailink-src.tar.gz"

	HASH=$(awk -F '\t' -v f="$NAILINK_IPK" '$4==f {print $5}' "$CACHE/ipk-arm64.tsv")
	[ "${#HASH}" = 64 ] || { log "NaiLink 校验清单中找不到 $NAILINK_IPK"; exit 1; }
	case "$HASH" in *[!0-9a-f]*) log "NaiLink 校验值格式非法"; exit 1 ;; esac
	echo "$HASH  $CACHE/$NAILINK_IPK" | sha256sum -c - >/dev/null
	log "NaiLink 运行包校验通过：$HASH"

	# 解出运行包中的三个静态二进制
	rm -rf "$CACHE/nailink-unpack"
	mkdir -p "$CACHE/nailink-unpack"
	tar -xOzf "$CACHE/$NAILINK_IPK" ./data.tar.gz > "$CACHE/nailink-data.tar.gz"
	tar -xzf "$CACHE/nailink-data.tar.gz" -C "$CACHE/nailink-unpack" \
		./usr/bin/daed ./usr/libexec/daed/btf-probe ./usr/libexec/daed/luci-proxy \
		./etc/init.d/daed ./etc/config/daed ./usr/share/daed-router/version 2>/dev/null || true

	# 解出官方源码包里的 openwrt 目录（Makefile + files + htdocs + 安装脚本）
	rm -rf "$CACHE/nailink-src"
	mkdir -p "$CACHE/nailink-src"
	tar -xzf "$CACHE/nailink-src.tar.gz" -C "$CACHE/nailink-src" --strip-components=0 ./openwrt 2>/dev/null \
		|| tar -xzf "$CACHE/nailink-src.tar.gz" -C "$CACHE/nailink-src" openwrt
	[ -f "$CACHE/nailink-src/openwrt/Makefile" ] || { log "NaiLink 源码包结构异常"; exit 1; }

	rm -rf ./daed-router
	mkdir -p ./daed-router
	cp -r "$CACHE/nailink-src/openwrt/." ./daed-router/
	mkdir -p ./daed-router/bin
	cp -f "$CACHE/nailink-unpack/usr/bin/daed" ./daed-router/bin/daed
	cp -f "$CACHE/nailink-unpack/usr/libexec/daed/btf-probe" ./daed-router/bin/btf-probe
	cp -f "$CACHE/nailink-unpack/usr/libexec/daed/luci-proxy" ./daed-router/bin/luci-proxy
	chmod 0755 ./daed-router/bin/daed ./daed-router/bin/btf-probe ./daed-router/bin/luci-proxy

	# 上游 Makefile 通过 DAED_BINARY / DAED_BTF_PROBE / DAED_LUCI_PROXY 取二进制，
	# buildroot 不便于逐包注入这些变量，这里改为指向包目录内的 bin/ 副本。
	sed -i 's|\$(DAED_BINARY)|./bin/daed|g; s|\$(DAED_BTF_PROBE)|./bin/btf-probe|g; s|\$(DAED_LUCI_PROXY)|./bin/luci-proxy|g' ./daed-router/Makefile
	grep -q './bin/daed' ./daed-router/Makefile || { log "上游 Makefile 的二进制变量未被替换"; exit 1; }

	record_version "daed-router" "slobys/NaiLink" "$NAILINK_TAG" "$NAILINK_VERSION"
	log "NaiLink 包配方就绪：daed-router + luci-app-daed-router"
fi

# ---------------------------------------------------------------- PLUS 其余插件（非关键，失败只告警）
soft_clone() {  # repo branch dest
	clone_repo "$@" || log "警告：$1 克隆失败，相关插件本次不集成"
}
if [ "$PROFILE" = "PLUS" ]; then
	soft_clone vernesong/OpenClash                master "$CACHE/openclash"
	take_pkgs "$CACHE/openclash" luci-app-openclash

	soft_clone Openwrt-Passwall/openwrt-passwall2 main   "$CACHE/passwall2"
	take_pkgs "$CACHE/passwall2" luci-app-passwall2

	drop_feed_pkg luci-app-partexp luci-app-wolplus luci-app-timewol
	rm -rf ./luci-app-partexp
	soft_clone sirpdboy/luci-app-partexp          main   ./luci-app-partexp
	soft_clone ones20250/packages                 main   "$CACHE/ones-packages"
	take_pkgs "$CACHE/ones-packages" luci-app-timewol luci-app-wolplus
fi

# ---------------------------------------------------------------- 完整性自检
# 任何一个关键包目录缺失都会让 .config 里的选择被 make defconfig 静默丢弃，
# 因此这里显式失败，避免产出缺失插件的固件。
REQUIRED="luci-theme-vantage luci-theme-7dollar luci-theme-carbon dae honk luci-app-honk nikki luci-app-nikki mihomo-meta openbox-athena-installer"
if [ "$PROFILE" = "PLUS" ]; then
	REQUIRED="$REQUIRED daed-router"
fi
for PKG in $REQUIRED; do
	[ -d "./$PKG" ] || { log "缺少必需包目录：$PKG"; exit 1; }
done

rm -rf "$CACHE"
log "全部插件源码就绪（$PROFILE）"
