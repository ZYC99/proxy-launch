#!/bin/bash
# proxy-launch 安装脚本（macOS）
# 支持：1) Release 预编译完整包（含 sing-box + ProxyBar，开箱即用，无需 Xcode CLT / Homebrew）
#       2) 源码安装（本地 swiftc 编译 ProxyBar，自动检测系统 sing-box）
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/bin"

# 清理从浏览器/GitHub 下载解压后的 macOS quarantine 属性，避免 Gatekeeper 拦截
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

# 1. 安装核心脚本
cp "$SRC/proxy-launch" "$HOME/bin/proxy-launch"
chmod +x "$HOME/bin/proxy-launch"
echo "✓ ~/bin/proxy-launch"

# 2. 安装 sing-box（优先复用系统已安装的 brew 版本；若无则安装随包附带的二进制）
if command -v sing-box >/dev/null 2>&1 || [ -x /opt/homebrew/bin/sing-box ] || [ -x /usr/local/bin/sing-box ]; then
  echo "✓ 检测到系统已安装 sing-box，跳过内置拷贝"
elif [ -x "$SRC/bin/sing-box" ]; then
  cp "$SRC/bin/sing-box" "$HOME/bin/sing-box"
  chmod +x "$HOME/bin/sing-box"
  xattr -d com.apple.quarantine "$HOME/bin/sing-box" 2>/dev/null || true
  echo "✓ ~/bin/sing-box (随包内置)"
elif [ -x "$SRC/sing-box" ]; then
  cp "$SRC/sing-box" "$HOME/bin/sing-box"
  chmod +x "$HOME/bin/sing-box"
  xattr -d com.apple.quarantine "$HOME/bin/sing-box" 2>/dev/null || true
  echo "✓ ~/bin/sing-box (随包内置)"
else
  echo "⚠ 未检测到 sing-box，请执行: brew install sing-box"
fi

# 3. 安装 ProxyBar 菜单栏 GUI（优先使用 Release 预编译二进制，否则用 swiftc 源码编译）
BAR_INSTALLED=0
if [ -x "$SRC/bin/ProxyBar" ]; then
  cp "$SRC/bin/ProxyBar" "$HOME/bin/ProxyBar"
  chmod +x "$HOME/bin/ProxyBar"
  xattr -d com.apple.quarantine "$HOME/bin/ProxyBar" 2>/dev/null || true
  echo "✓ ~/bin/ProxyBar (预编译)"
  BAR_INSTALLED=1
elif [ -x "$SRC/ProxyBar" ]; then
  cp "$SRC/ProxyBar" "$HOME/bin/ProxyBar"
  chmod +x "$HOME/bin/ProxyBar"
  xattr -d com.apple.quarantine "$HOME/bin/ProxyBar" 2>/dev/null || true
  echo "✓ ~/bin/ProxyBar (预编译)"
  BAR_INSTALLED=1
elif command -v swiftc >/dev/null 2>&1 && [ -f "$SRC/ProxyBar.swift" ]; then
  swiftc -O -framework AppKit -o "$HOME/bin/ProxyBar" "$SRC/ProxyBar.swift"
  echo "✓ ~/bin/ProxyBar (源码编译)"
  BAR_INSTALLED=1
else
  echo "⚠ 无预编译 ProxyBar 且未安装 swiftc，跳过 GUI（可装 Xcode CLT 后重跑）"
fi

if [ "$BAR_INSTALLED" -eq 1 ]; then
  PL="$HOME/Library/LaunchAgents/com.zyc.proxybar.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.zyc.proxybar</string>
<key>ProgramArguments</key><array><string>$HOME/bin/ProxyBar</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)/com.zyc.proxybar" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PL"
  echo "✓ ProxyBar 登录项已启动"
fi

# 4. 生成默认配置文件模板（不覆盖已有配置）
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/proxy-launch"
CFG_FILE="$CFG_DIR/config"
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
  echo "✓ 已生成默认配置: $CFG_FILE（请按需修改节点地址）"
fi

case ":$PATH:" in *":$HOME/bin:"*) ;; *) echo "提示: 把 export PATH=\"\$HOME/bin:\$PATH\" 加入 ~/.zshrc";; esac
echo "完成。请先确认 $CFG_FILE 中的节点地址，然后运行: proxy-launch on"
