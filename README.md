# proxy-launch

macOS 命令行 + 菜单栏的代理管理工具。用 **sing-box TUN** 做统一分流（国内直连 / 国外走代理），
配合 **Cloudflare WARP** 作为运输层，支持全局/规则/纯直连切换，附原生菜单栏 GUI（ProxyBar）。

> 面向「本机已有 WARP + 一个境外代理节点（SOCKS/HTTP）」的场景。节点地址在脚本内
> `PROXY_HOST / PROXY_PORT / SOCKS_PORT` 配置，默认 `172.100.0.2:8443 / :1080`，按需修改。

## 架构

```
应用 / CLI / 裸socket
   ├─ 认系统代理 → 127.0.0.1:7890 (sing-box mixed)
   └─ 其余全部   → sing-box TUN (默认路由)
                     ├─ 国内/内网/直连清单 → direct (en0, 真实国内IP)
                     └─ 境外/代理清单/兜底 → PROXY → sharenet节点(境外出口)
ToDesk 等特例网段 ─ 内核/16路由(优先于TUN) → WARP(国内出口)
WARP: 提供 172.100.0.0/24 运输到 sharenet；自身出口为国内
```

分流判定（rule 模式，自上而下）：sniff+DNS劫持 → 运输层/内网直连 → 禁IPv6/拒QUIC →
直连清单 → 代理清单 → geoip-cn/geosite-cn 直连 → 兜底 PROXY。

## 依赖

- macOS（Apple Silicon / Intel），Xcode Command Line Tools（`swiftc`）
- [sing-box](https://sing-box.sagernet.org)：`brew install sing-box`
- Cloudflare WARP（可选，作为运输层/国内出口）
- 一个境外 SOCKS5/HTTP 代理节点

## 安装

```bash
./install.sh          # 拷贝到 ~/bin、编译 ProxyBar、装登录项
```

或手动：

```bash
mkdir -p ~/bin && cp proxy-launch ~/bin/ && chmod +x ~/bin/proxy-launch
swiftc -O -framework AppKit -o ~/bin/ProxyBar ProxyBar.swift
```

## 使用

```bash
proxy-launch on            # 启用 sing-box TUN 分流
proxy-launch off           # 纯直连（关代理）
proxy-launch sb on|off     # sing-box TUN 开/关
proxy-launch clash on|off  # 备用: 用户级 mihomo（仅代理感知流量）
proxy-launch mode rule     # 规则分流（国内直连）
proxy-launch mode global   # 全局（全部走代理）
proxy-launch routes sync   # 补齐特例路由/学习网段/裁日志/系统代理守护
proxy-launch sj            # JSON 状态（供 GUI）
proxy-launch env           # 输出临时代理环境变量，可 eval
proxy-launch zsh|git|curl|npm|pip|brew|claude-cli|codex ...   # 单命令带代理
```

CLI 临时环境变量：

```bash
eval "$(proxy-launch env)"   # HTTP(S)_PROXY/ALL_PROXY=http://127.0.0.1:7890
```

## 菜单栏 GUI（ProxyBar）

- 🟢 分流中 / 🟡 半断(WARP断) / ⚪️ 纯直连
- 菜单：规则/全局切换、开/关、重连WARP、刷新、退出
- 登录自启（LaunchAgent `com.zyc.proxybar`）

## 常驻守护

`com.zyc.proxy-routes`（root，每15分钟）：补 ToDesk/特例路由、学习新网段、裁剪日志、
**系统代理守护**（WARP 重连会重置系统代理，自动改回 7890）。

## 常见问题

- **Gemini 一直加载模型**：sharenet 不支持 IPv6/QUIC，已默认禁 IPv6+拒 UDP443 强制 IPv4/TCP。
- **ToDesk 无连接**：先确认 root 服务 `ToDesk_Service` 在跑
  （`launchctl bootstrap system /Library/LaunchDaemons/com.youqu.todesk.service.plist`），再谈分流。
- **国内站绕道/变慢**：检查国内 DNS（默认 114）与直连清单；个别域名解析到境外 EdgeOne 需显式处理。
- **WARP 断开**：境外上游失效（半断），点菜单栏 WARP 重连或 `proxy-launch off` 切纯直连。

## 说明

- 规则清单内嵌于 `proxy-launch`（`direct-extra`/`proxy-extra`），改后 `sb build` 重载。
- 不含任何账号/密码；节点地址为示例私有地址，请替换为自己的。
