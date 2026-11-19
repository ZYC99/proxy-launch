#!/bin/bash
# 打包 macOS Release 产物（支持生成：完整包[含 sing-box + ProxyBar] 与 轻量包[含 ProxyBar]）
# 用法: ./scripts/package-release.sh [version]   # 例如 ./scripts/package-release.sh v0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:-v0.1.0}"
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

# 2. 组装完整包（含 sing-box + ProxyBar）
FULL_NAME="proxy-launch-${VER}-darwin-${ARCH}-full"
FULL_DIR="$DIST/$FULL_NAME"
mkdir -p "$FULL_DIR/bin"
cp "$ROOT/proxy-launch" "$ROOT/install.sh" "$ROOT/README.md" "$FULL_DIR/"
cp "$BAR_BIN" "$FULL_DIR/bin/ProxyBar"
cp -L "$SB_SRC" "$FULL_DIR/bin/sing-box"
chmod +x "$FULL_DIR/proxy-launch" "$FULL_DIR/install.sh" "$FULL_DIR/bin/ProxyBar" "$FULL_DIR/bin/sing-box"

cat > "$FULL_DIR/THIRD_PARTY_NOTICES.md" <<EOF
# Third-Party Notices

This release archive bundles the following third-party software:

- **sing-box** (${SB_VER})
  - Project: https://github.com/SagerNet/sing-box
  - License: GNU General Public License v3.0 (GPL-3.0-or-later)
  - Source code is available from the upstream repository above.
EOF

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

# 4. 生成 SHA256 校验文件
(cd "$DIST" && shasum -a 256 "${FULL_NAME}.tar.gz" "${LITE_NAME}.tar.gz" > "checksums-${VER}.txt")
echo "✓ 校验文件: dist/checksums-${VER}.txt"
cat "$DIST/checksums-${VER}.txt"
