# proxy-launch

macOS 命令行 + 菜单栏的代理管理工具。用 **sing-box TUN** 做统一分流（国内直连 / 国外走代理），
配合 **Cloudflare WARP** 作为运输层，支持全局/规则/纯直连切换，附原生菜单栏 GUI（ProxyBar）。

> 面向「本机已有 WARP + 一个境外代理节点（SOCKS/HTTP）」的场景。节点地址在
> `~/.config/proxy-launch/config`（`PROXY_HOST / PROXY_PORT / SOCKS_PORT`）配置，
> 默认 `172.100.0.2:8443 / :1080`，安装脚本会自动生成配置模板，按需修改即可。

## 架构

```
应用 / CLI / 裸socket
   ├─ 认系统代理 → 127.0.0.1:7890 (sing-box mixed)
   └─ 其余全部   → sing-box TUN (默认路由)
                     ├─ 国内/内网/直连清单 → direct (en0, 真实国内IP)
                     └─ 境外/代理清单/兜底          → PROXY → sharenet节点(境外出口)
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

### 方式一：下载 `.pkg` 图形化安装包（最省事，零命令行）

前往 [GitHub Releases](https://github.com/ZYC99/proxy-launch/releases) 下载 **`proxy-launch-v*-darwin-arm64.pkg`**：

1. **右键点击 `.pkg` → 打开**（因未购 Apple 开发者签名，首次需右键打开绕过 Gatekeeper 提示）。
2. 一路点击「继续 / 安装」，自动完成：
   - 安装 CLI 到 `/usr/local/bin/proxy-launch`（以及一键卸载命令 `proxy-launch-uninstall`）
   - 内置 `sing-box` 与 `ProxyBar` 到 `/usr/local/libexec/proxy-launch/`（无需 Homebrew / Xcode CLT）
   - 自动注册并拉起右上角菜单栏 **ProxyBar** 图标
   - 自动生成配置文件模板 `~/.config/proxy-launch/config`
3. 按需修改 `~/.config/proxy-launch/config` 中的上游节点地址，点击菜单栏 **开启代理**（或终端运行 `proxy-launch on`）即可。

> 如需卸载，在终端执行 `proxy-launch-uninstall` 即可一键清理。

### 方式二：下载 Release `.tar.gz` 压缩包

前往 [GitHub Releases](https://github.com/ZYC99/proxy-launch/releases) 下载对应包：

- **`proxy-launch-v*-darwin-arm64-full.tar.gz`（完整包）**：内置 `sing-box` 二进制与预编译 `ProxyBar`，**无需安装 Homebrew 和 Xcode Command Line Tools**。
- **`proxy-launch-v*-darwin-arm64-lite.tar.gz`（轻量包）**：内置预编译 `ProxyBar`，复用系统已通过 `brew install sing-box` 安装的 `sing-box`。

解压并一键安装：

```bash
tar -xzf proxy-launch-v*-darwin-arm64-full.tar.gz
cd proxy-launch-v*-darwin-arm64-full
./install.sh
```

> 安装脚本会自动清理 macOS 的 `com.apple.quarantine` 隔离属性，拷贝文件到 `~/bin`、注册 `ProxyBar` 登录项并生成默认配置文件 `~/.config/proxy-launch/config`。
> 如果系统已通过 Homebrew 安装 `sing-box`，脚本会自动优先复用系统版本。

### 方式三：源码安装

需要预先安装 `Xcode Command Line Tools`（提供 `swiftc`）与 `sing-box`（`brew install sing-box`）：

```bash
./install.sh          # 拷贝到 ~/bin、编译 ProxyBar、装登录项、生成配置模板
```

### 配置上游节点

编辑 `~/.config/proxy-launch/config` 修改为你的境外代理节点地址与端口：

```bash
PROXY_HOST=172.100.0.2
PROXY_PORT=8443
SOCKS_PORT=1080
SYSTEM_KIND=http
```

改完后启动（或重载）：

```bash
proxy-launch on       # 启用 sing-box TUN 分流（会请求管理员权限）
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

`com.zyc.proxy-routes`（root，每15分钟）：补特例路由、学习新网段、裁剪日志、
**系统代理守护**（WARP 重连会重置系统代理，自动改回 7890）。

`com.zyc.warp-heal`（root，每60秒）：**WARP 假连接自愈**——状态 Connected 但
`172.100.0.2:1080` 不可达时（连续2次失败、5分钟冷静期）自动 disconnect/connect。
健康时完全静默，日志 `/var/log/warp-heal.log`。

## 常见问题

- **Gemini 一直加载模型**：sharenet 不支持 IPv6/QUIC，已默认禁 IPv6+拒 UDP443 强制 IPv4/TCP。
- **国内站绕道/变慢**：检查国内 DNS（默认 114）与直连清单；个别域名解析到境外 EdgeOne 需显式处理。
- **WARP 断开**：境外上游失效（半断），点菜单栏 WARP 重连或 `proxy-launch off` 切纯直连。


## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PROXY_HOST` / `PROXY_PORT` / `SOCKS_PORT` | `172.100.0.2` / `8443` / `1080` | 上游节点 |
| `CN_DNS` / `FOREIGN_DNS` | `114.114.114.114` / `1.1.1.1` | 国内/境外 DNS |
| `WARP_IF` | 自动探测 | 手动指定 WARP 隧道接口 |
| `WARP_EXTRA_CIDRS` | — | 追加免环路网段 |
| `DIRECT_IF` | 自动(PrimaryInterface) | 直连网卡 |
| `MIHOMO_PORT` | `7890` | 本地代理端口 |
| `TUN_MTU` | `1280` | TUN MTU（需小于隧道实际 MTU，过大易丢包） |

## 版本说明

- v1.1.4（2026-11-23）：**修复 Chrome 无法打开 YouTube**——移除 `tun-in` IPv6 地址避免系统写入全局 IPv6 路由后被 TUN 假握手+RST 阻断回退；修复 QUIC 拦截规则字段（`protocol: udp` → `network: udp` + `protocol: quic`）；补全 `ytimg.com`/`youtu.be` 代理规则；TUN 运行时 `proxy-launch chrome` 不再附加 `7890` 代理参数。
- v1.1.3（2026-11-23）：**移除出站 bind_interface / 关闭 auto_detect_interface**，改由内核路由到达上游，彻底消除 WARP 重连后接口名变化导致的 `device not configured`；IPv6 改为快速 reject，浏览器不再干等。
- v1.1.2（2026-11-22）：warp-heal 改为**双端口探测**（1080+8443，任一不通即计失败），覆盖"单端口超时"盲区；日志标注具体失败端口。
- v1.1.1（2026-11-21）：TUN MTU 默认 9000→1280，修复长连接/流式响应在 WARP 隧道下丢包（表现为能连上但反复 network issue）；新增 `TUN_MTU` 环境变量。
- v1.1.0（2026-11-21）：新增 `warp-heal` WARP 假连接自愈守护（`proxy-launch warp-heal`，
  60s 探测 + 连续2次失败 + 5分钟冷静期）；系统代理守护改为 TUN 模式保持关闭。
- v1.0.0（2026-11-20）：首次发布。sing-box TUN 规则分流 + 菜单栏 GUI；
  隧道接口/二进制/WARP 端点全部运行时动态探测（换网、改交换机名无需改脚本）；
  TUN 模式下系统代理保持关闭（全流量走 TUN，避免 mixed 路径域名被上游拒绝）；
  支持全局/规则/纯直连模式切换与系统代理守护。

## 说明

- 规则清单内嵌于 `proxy-launch`（`direct-extra`/`proxy-extra`），改后 `sb build` 重载。
- 不含任何账号/密码；节点地址为示例私有地址，请替换为自己的。
