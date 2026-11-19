#!/bin/bash
# proxy-launch 安装脚本（macOS）
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/bin"

cp "$SRC/proxy-launch" "$HOME/bin/proxy-launch"
chmod +x "$HOME/bin/proxy-launch"
echo "✓ ~/bin/proxy-launch"

if command -v swiftc >/dev/null 2>&1; then
  swiftc -O -framework AppKit -o "$HOME/bin/ProxyBar" "$SRC/ProxyBar.swift"
  echo "✓ ~/bin/ProxyBar (编译)"
  # 登录项
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
  echo "✓ ProxyBar 登录项"
else
  echo "⚠ 无 swiftc，跳过 GUI（需 Xcode CLT）"
fi

case ":$PATH:" in *":$HOME/bin:"*) ;; *) echo "提示: 把 export PATH=\"\$HOME/bin:\$PATH\" 加入 ~/.zshrc";; esac
echo "完成。运行: proxy-launch on"
