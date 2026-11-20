// ProxyBar —— 菜单栏代理管理小工具（配合 ~/bin/proxy-launch）
import AppKit

let PL = (NSHomeDirectory() as NSString).appendingPathComponent("bin/proxy-launch")
let WARP = "/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli"

struct St { var sb=0, tun=0, mihomo=0, warp=0, port=0, sysproxy=0, route=0; var mode="rule" }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    var st = St()
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self
        item.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in self.refresh() }
    }

    // 运行 shell 并返回输出
    func sh(_ cmd: String) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    func refresh() {
        let out = sh("\(PL) sj")
        if let d = out.data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            func i(_ k: String) -> Int { (j[k] as? Int) ?? 0 }
            st = St(sb: i("sb"), tun: i("tun"), mihomo: i("mihomo"),
                    warp: i("warp"), port: i("port"),
                    sysproxy: i("sysproxy"), route: i("route"),
                    mode: (j["mode"] as? String) ?? "rule")
        }
        let engineOn = (st.sb + st.tun + st.mihomo) > 0 && st.port == 1
        let title: String
        if engineOn && st.warp == 1 { title = "🟢" }
        else if engineOn { title = "🟡" }
        else { title = "⚪️" }
        item.button?.title = title
        item.button?.toolTip = modeText()
        if let m = item.menu { build(m) }
    }

    func modeText() -> String {
        let engineOn = (st.sb + st.tun + st.mihomo) > 0 && st.port == 1
        let m = st.mode == "global" ? "全局" : "规则"
        if !engineOn { return "纯直连（代理已关）" }
        if st.warp == 1 { return "分流中 · \(m)模式 · 出口CA" }
        return "半断：WARP 断开 · \(m)模式"
    }

    func build(_ m: NSMenu) {
        m.removeAllItems()
        let head = NSMenuItem(title: modeText(), action: nil, keyEquivalent: "")
        head.isEnabled = false; m.addItem(head)
        let w = NSMenuItem(title: "WARP: " + (st.warp == 1 ? "已连接" : "断开"), action: nil, keyEquivalent: "")
        w.isEnabled = false; m.addItem(w)
        m.addItem(.separator())
        let rule = act("规则分流（国内直连）", #selector(modeRule))
        rule.state = st.mode == "rule" ? .on : .off; m.addItem(rule)
        let glob = act("全局代理（全部走CA）", #selector(modeGlobal))
        glob.state = st.mode == "global" ? .on : .off; m.addItem(glob)
        m.addItem(.separator())
        m.addItem(act("开启代理（sing-box TUN）", #selector(onProxy)))
        m.addItem(act("纯直连（关闭代理）", #selector(offProxy)))
        m.addItem(act("重连 WARP", #selector(reconnectWarp)))
        m.addItem(act("刷新状态", #selector(doRefresh)))
        m.addItem(.separator())
        m.addItem(act("退出 ProxyBar", #selector(quit)))
    }

    func act(_ t: String, _ s: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: ""); i.target = self; return i
    }

    func admin(_ arg: String) {
        DispatchQueue.global().async {
            _ = self.sh("/usr/bin/osascript -e 'do shell script \"\(PL) \(arg)\" with administrator privileges'")
            DispatchQueue.main.async { self.refresh() }
        }
    }

    @objc func onProxy() { admin("on") }
    @objc func offProxy() { admin("off") }
    @objc func modeRule() { admin("mode rule") }
    @objc func modeGlobal() { admin("mode global") }
    @objc func reconnectWarp() {
        DispatchQueue.global().async { _ = self.sh("\(WARP) connect"); DispatchQueue.main.async { self.refresh() } }
    }
    @objc func doRefresh() { refresh() }
    @objc func quit() { NSApp.terminate(nil) }

    func menuWillOpen(_ m: NSMenu) { refresh() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let del = AppDelegate()
app.delegate = del
app.run()
