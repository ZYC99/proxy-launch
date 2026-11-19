#!/bin/bash
# 打包 macOS Release 产物：
#   1) 图形化安装包 .pkg（内置 proxy-launch + ProxyBar + sing-box + 卸载脚本，双击安装即用）
#   2) 完整压缩包 -full.tar.gz（内置 sing-box + ProxyBar）
#   3) 轻量压缩包 -lite.tar.gz（内置 ProxyBar，复用系统 brew sing-box）
# 用法: ./scripts/package-release.sh [version]   # 例如 ./scripts/package-release.sh v0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:-v0.1.0}"
PKG_VER="${VER#v}"
ARCH="$(uname -m)"
DIST="$ROOT/dist"
SB_SRC="${SB_BIN:-$(command -v sing-box || echo /opt/homebrew/bin/sing-box)}"

[ -x "$SB_SRC" ] || { echo "错误: 未找到 sing-box ($SB_SRC)，请先 brew install sing-box" >&2; exit 1; }
command -v swiftc >/dev/null 2>&1 || { echo "错误: 未找到 swiftc，需要 Xcode Command Line Tools" >&2; exit 1; }

SB_VER="$("$SB_SRC" version 2>/dev/null | head -1 || echo "unknown")"
echo "==> 打包版本: ${VER} (darwin-${ARCH})"
echo "==> sing-box: ${SB_SRC} (${SB_VER})"

rm -rf "$DIST"
mkdir -p "$DIST"

# 1. 编译 ProxyBar（预编译二进制）
BAR_BIN="$DIST/ProxyBar"
swiftc -O -framework AppKit -o "$BAR_BIN" "$ROOT/ProxyBar.swift"
chmod +x "$BAR_BIN"

THIRD_PARTY_DOC="$DIST/THIRD_PARTY_NOTICES.md"
cat > "$THIRD_PARTY_DOC" <<EOF
# Third-Party Notices

This release archive bundles the following third-party software:

- **sing-box** (${SB_VER})
  - Project: https://github.com/SagerNet/sing-box
  - License: GNU General Public License v3.0 (GPL-3.0-or-later)
  - Source code is available from the upstream repository above.
EOF

# 2. 组装完整包（含 sing-box + ProxyBar）
FULL_NAME="proxy-launch-${VER}-darwin-${ARCH}-full"
FULL_DIR="$DIST/$FULL_NAME"
mkdir -p "$FULL_DIR/bin"
cp "$ROOT/proxy-launch" "$ROOT/install.sh" "$ROOT/README.md" "$THIRD_PARTY_DOC" "$FULL_DIR/"
cp "$BAR_BIN" "$FULL_DIR/bin/ProxyBar"
cp -L "$SB_SRC" "$FULL_DIR/bin/sing-box"
chmod +x "$FULL_DIR/proxy-launch" "$FULL_DIR/install.sh" "$FULL_DIR/bin/ProxyBar" "$FULL_DIR/bin/sing-box"

tar -C "$DIST" -czf "$DIST/${FULL_NAME}.tar.gz" "$FULL_NAME"
echo "✓ 完整包: dist/${FULL_NAME}.tar.gz ($(du -h "$DIST/${FULL_NAME}.tar.gz" | awk '{print $1}'))"

# 3. 组装轻量包（含预编译 ProxyBar，不含 sing-box）
LITE_NAME="proxy-launch-${VER}-darwin-${ARCH}-lite"
LITE_DIR="$DIST/$LITE_NAME"
mkdir -p "$LITE_DIR/bin"
cp "$ROOT/proxy-launch" "$ROOT/install.sh" "$ROOT/README.md" "$LITE_DIR/"
cp "$BAR_BIN" "$LITE_DIR/bin/ProxyBar"
chmod +x "$LITE_DIR/proxy-launch" "$LITE_DIR/install.sh" "$LITE_DIR/bin/ProxyBar"

tar -C "$DIST" -czf "$DIST/${LITE_NAME}.tar.gz" "$LITE_NAME"
echo "✓ 轻量包: dist/${LITE_NAME}.tar.gz ($(du -h "$DIST/${LITE_NAME}.tar.gz" | awk '{print $1}'))"

# 4. 构建 macOS 图形化安装包 (.pkg)
PKG_NAME="proxy-launch-${VER}-darwin-${ARCH}.pkg"
PKG_ROOT="$DIST/pkgroot"
PKG_SCRIPTS="$DIST/pkgscripts"
mkdir -p "$PKG_ROOT/usr/local/bin" \
         "$PKG_ROOT/usr/local/libexec/proxy-launch" \
         "$PKG_ROOT/usr/local/share/proxy-launch" \
         "$PKG_SCRIPTS"

cp "$ROOT/proxy-launch" "$PKG_ROOT/usr/local/bin/proxy-launch"
cp "$BAR_BIN" "$PKG_ROOT/usr/local/libexec/proxy-launch/ProxyBar"
cp -L "$SB_SRC" "$PKG_ROOT/usr/local/libexec/proxy-launch/sing-box"
cp "$ROOT/README.md" "$THIRD_PARTY_DOC" "$PKG_ROOT/usr/local/share/proxy-launch/"
chmod 755 "$PKG_ROOT/usr/local/bin/proxy-launch" \
          "$PKG_ROOT/usr/local/libexec/proxy-launch/ProxyBar" \
          "$PKG_ROOT/usr/local/libexec/proxy-launch/sing-box"

# 附带一键卸载脚本
cat > "$PKG_ROOT/usr/local/bin/proxy-launch-uninstall" <<'UNINSTALL'
#!/bin/bash
# 一键卸载通过 .pkg 安装的 proxy-launch
set -euo pipefail
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || id -un)"
CONSOLE_UID="$(id -u "$CONSOLE_USER")"
USER_HOME="$(eval echo "~${CONSOLE_USER}")"

echo "==> 停止代理服务与菜单栏程序..."
if [ -x /usr/local/bin/proxy-launch ]; then
  /usr/local/bin/proxy-launch off 2>/dev/null || true
fi
launchctl bootout "gui/${CONSOLE_UID}/com.zyc.proxybar" 2>/dev/null || true
rm -f "${USER_HOME}/Library/LaunchAgents/com.zyc.proxybar.plist"

echo "==> 清理安装文件..."
sudo rm -f /usr/local/bin/proxy-launch /usr/local/bin/proxy-launch-uninstall
sudo rm -rf /usr/local/libexec/proxy-launch /usr/local/share/proxy-launch
sudo pkgutil --forget com.zyc.proxy-launch 2>/dev/null || true

echo "✓ proxy-launch 已卸载（个人配置保留在 ${USER_HOME}/.config/proxy-launch，如需彻底删除可手动移除）"
UNINSTALL
chmod 755 "$PKG_ROOT/usr/local/bin/proxy-launch-uninstall"

# postinstall：以当前桌面登录用户身份写入配置模板并启动 ProxyBar 菜单栏图标
cat > "$PKG_SCRIPTS/postinstall" <<'POSTINSTALL'
#!/bin/bash
set -euo pipefail

CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "loginwindow" ]; then
  exit 0
fi
CONSOLE_UID="$(id -u "$CONSOLE_USER")"
USER_HOME="$(eval echo "~${CONSOLE_USER}")"
USER_GROUP="$(id -gn "$CONSOLE_USER")"

# 1. 生成默认配置模板（不覆盖已有配置）
CFG_DIR="${USER_HOME}/.config/proxy-launch"
CFG_FILE="${CFG_DIR}/config"
mkdir -p "$CFG_DIR"
if [ ! -f "$CFG_FILE" ]; then
  cat > "$CFG_FILE" <<'CONF'
# proxy-launch 用户配置（按需修改你的上游代理节点）
PROXY_HOST=172.100.0.2
PROXY_PORT=8443
SOCKS_PORT=1080
SYSTEM_KIND=http
# 可选覆盖：
# MIHOMO_PORT=7890
# WARP_IF=utun4
# DIRECT_IF=en0
# SB_BIN=/opt/homebrew/bin/sing-box
CONF
fi
chown -R "${CONSOLE_USER}:${USER_GROUP}" "$CFG_DIR"

# 2. 注册并立即拉起 ProxyBar 菜单栏程序
LA_DIR="${USER_HOME}/Library/LaunchAgents"
PL="${LA_DIR}/com.zyc.proxybar.plist"
mkdir -p "$LA_DIR"
cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.zyc.proxybar</string>
<key>ProgramArguments</key><array><string>/usr/local/libexec/proxy-launch/ProxyBar</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
chown "${CONSOLE_USER}:${USER_GROUP}" "$PL"
chmod 644 "$PL"

launchctl bootout "gui/${CONSOLE_UID}/com.zyc.proxybar" 2>/dev/null || true
launchctl bootstrap "gui/${CONSOLE_UID}" "$PL" 2>/dev/null || true
exit 0
POSTINSTALL
chmod 755 "$PKG_SCRIPTS/postinstall"

pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "com.zyc.proxy-launch" \
  --version "$PKG_VER" \
  --install-location "/" \
  "$DIST/component.pkg" >/dev/null

# 包装为带欢迎说明的图形化产品包
DIST_XML="$DIST/distribution.xml"
RES_DIR="$DIST/pkgres"
mkdir -p "$RES_DIR"
cat > "$RES_DIR/welcome.html" <<EOF
<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 13px; line-height: 1.6; color: #222; }
code { background: #f2f2f2; padding: 1px 4px; border-radius: 3px; }
</style></head><body>
<h2>proxy-launch ${VER} (Apple Silicon)</h2>
<p>macOS 统一代理分流工具（内置 <code>sing-box</code> 与原生菜单栏 GUI <code>ProxyBar</code>），支持国内直连 / 境外代理智能分流。</p>
<ul>
  <li>命令行工具安装到：<code>/usr/local/bin/proxy-launch</code></li>
  <li>卸载命令安装到：<code>/usr/local/bin/proxy-launch-uninstall</code></li>
  <li>菜单栏程序 <code>ProxyBar</code> 安装完成后会自动启动并加入登录项</li>
  <li>首次安装会在 <code>~/.config/proxy-launch/config</code> 生成节点配置模板，请按需修改后点击菜单栏 <b>开启代理</b> 或运行 <code>proxy-launch on</code></li>
</ul>
</body></html>
EOF

cat > "$DIST_XML" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>proxy-launch ${VER}</title>
    <welcome file="welcome.html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.zyc.proxy-launch"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.zyc.proxy-launch" visible="false">
        <pkg-ref id="com.zyc.proxy-launch"/>
    </choice>
    <pkg-ref id="com.zyc.proxy-launch" version="${PKG_VER}" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild \
  --distribution "$DIST_XML" \
  --resources "$RES_DIR" \
  --package-path "$DIST" \
  "$DIST/$PKG_NAME" >/dev/null

echo "✓ 图形安装包: dist/${PKG_NAME} ($(du -h "$DIST/${PKG_NAME}" | awk '{print $1}'))"

# 5. 生成 SHA256 校验文件
(cd "$DIST" && shasum -a 256 "${PKG_NAME}" "${FULL_NAME}.tar.gz" "${LITE_NAME}.tar.gz" > "checksums-${VER}.txt")
echo "✓ 校验文件: dist/checksums-${VER}.txt"
cat "$DIST/checksums-${VER}.txt"
