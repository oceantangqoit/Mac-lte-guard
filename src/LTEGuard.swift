// LTE Guard — 菜单栏常驻 App
// 睡眠策略切换 + 治愈对象选择 + 状态查看 + 唤醒自愈守护
import Cocoa
import IOKit
import IOKit.pwr_mgt
import IOKit.usb

// MARK: - 配置

struct Config {
    var dev = "en2"
    var service = ""
    var usbVID = ""
    var usbPID = ""
    var postCmd = ""

    static let path = NSHomeDirectory() + "/.lte-guard.conf"

    static func load() -> Config {
        var c = Config()
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return c }
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { continue }
            let key = String(s[s.startIndex..<eq])
            var val = String(s[s.index(after: eq)...])
            if let hash = val.range(of: "  #") { val = String(val[val.startIndex..<hash.lowerBound]) }
            val = val.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            switch key {
            case "DEV": c.dev = val
            case "SERVICE": c.service = val
            case "USB_VID": c.usbVID = val
            case "USB_PID": c.usbPID = val
            case "POST_CMD": c.postCmd = val
            default: break
            }
        }
        return c
    }

    func save() {
        let text = """
        # LTE Guard 配置（由 App 维护，也可手改）
        DEV="\(dev)"
        SERVICE="\(service)"
        USB_VID="\(usbVID)"
        USB_PID="\(usbPID)"
        POST_CMD='\(postCmd)'

        """
        try? text.write(toFile: Config.path, atomically: true, encoding: .utf8)
    }

    var methodText: String {
        usbVID.isEmpty ? T(7) : T(6, usbVID, usbPID)
    }
}

// MARK: - 系统操作

enum Sys {
    @discardableResult
    static func run(_ cmd: String, wait: Bool = true) -> String {
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        if !wait { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var logPath: String { NSHomeDirectory() + "/.lte-wake.log" }

    static func log(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(msg)\n"
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    /// 枚举网络服务 -> [(服务名, 接口名)]
    static func networkServices() -> [(String, String)] {
        let out = run("networksetup -listnetworkserviceorder")
        var result: [(String, String)] = []
        var svc = ""
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("(") , let r = line.range(of: ") ") {
                svc = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if line.contains("Hardware Port:"),
                      let r = line.range(of: "Device: ") {
                let dev = String(line[r.upperBound...]).replacingOccurrences(of: ")", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !svc.isEmpty && !dev.isEmpty { result.append((svc, dev)) }
            }
        }
        return result
    }

    /// 接口 -> USB (VID, PID)，非 USB 返回 nil
    static func usbIDs(for bsd: String) -> (String, String)? {
        guard let match = IOServiceMatching("IONetworkInterface") as NSMutableDictionary? else { return nil }
        match["BSD Name"] = bsd
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, match as CFDictionary)
        guard svc != 0 else { return nil }
        var cur = svc
        for _ in 0..<12 {
            let v = IORegistryEntryCreateCFProperty(cur, "idVendor" as CFString, nil, 0)?
                .takeRetainedValue() as? Int
            let p = IORegistryEntryCreateCFProperty(cur, "idProduct" as CFString, nil, 0)?
                .takeRetainedValue() as? Int
            if let v = v, let p = p {
                return (String(format: "%04x", v), String(format: "%04x", p))
            }
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(cur, kIOServicePlane, &parent) != KERN_SUCCESS { break }
            cur = parent
        }
        return nil
    }

    static func interfaceHealthy(_ dev: String) -> Bool {
        let hasIP = run("ifconfig \(dev) 2>/dev/null | grep -q 'inet ' && echo y") == "y"
        guard hasIP else { return false }
        var gw = run("ipconfig getoption \(dev) router 2>/dev/null")
        if gw.isEmpty {
            gw = run("netstat -rn -f inet | awk '$1==\"default\" && $NF==\"\(dev)\" {print $2; exit}'")
        }
        guard !gw.isEmpty else { return false }
        return run("ping -c 1 -t 3 -b \(dev) \(gw) >/dev/null 2>&1 && echo y") == "y"
    }
}


// MARK: - 多语言（数字键 INI）

/// 文案全部走数字代码，语言文件在 App 内 Resources/lang/*.ini，
/// 用户自定义可放 ~/.lte-guard-lang/*.ini（同名覆盖内置）。
final class I18n {
    static let shared = I18n()
    private var table: [Int: String] = [:]
    private(set) var code: String = ""

    /// 可选语言列表 [(文件代码, 显示名)]
    var available: [(String, String)] {
        var found: [String: String] = [:]
        for dir in I18n.searchDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".ini") {
                let c = String(f.dropLast(4))
                if found[c] == nil { found[c] = I18n.metaName(dir + "/" + f) ?? c }
            }
        }
        return found.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    static var searchDirs: [String] {
        var d = [NSHomeDirectory() + "/.lte-guard-lang"]
        if let r = Bundle.main.resourcePath { d.append(r + "/lang") }
        return d
    }

    private static func metaName(_ path: String) -> String? {
        guard let t = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in t.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.lowercased().hasPrefix("name=") { return String(s.dropFirst(5)) }
        }
        return nil
    }

    private init() { load(preferred: nil) }

    /// 载入语言：显式指定 > 用户偏好 > 系统语言 > en
    func load(preferred: String?) {
        let want = preferred
            ?? UserDefaults.standard.string(forKey: "lang")
            ?? Locale.preferredLanguages.first.map { l -> String in
                if l.hasPrefix("zh-Hant") || l.hasPrefix("zh-TW") || l.hasPrefix("zh-HK") || l.hasPrefix("zh-MO") { return "zh-Hant" }
                if l.hasPrefix("zh") { return "zh-Hans" }
                // 保留地区变体（pt-BR / es-MX / es-AR），其余取主语言
                let parts = l.split(separator: "-")
                if parts.count >= 2, ["pt","es"].contains(String(parts[0])) {
                    return "\(parts[0])-\(parts[1])"
                }
                return String(l.prefix(2))
            }
            ?? "en"

        // 依次尝试：完整代码 -> 主语言 -> en
        var chain = [want]
        if want.contains("-"), let base = want.split(separator: "-").first { chain.append(String(base)) }
        chain.append("en")

        for cand in chain {
            for dir in I18n.searchDirs {
                let path = "\(dir)/\(cand).ini"
                if let t = try? String(contentsOfFile: path, encoding: .utf8) {
                    parse(t); code = cand
                    if preferred != nil { UserDefaults.standard.set(cand, forKey: "lang") }
                    return
                }
            }
        }
        table = [:]; code = want
    }

    private func parse(_ text: String) {
        table.removeAll()
        var inStrings = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                inStrings = line.lowercased() == "[strings]"
                continue
            }
            guard inStrings, let eq = line.firstIndex(of: "="),
                  let key = Int(line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces))
            else { continue }
            table[key] = String(line[line.index(after: eq)...])
        }
    }

    /// 取文案：t(21, "Wi-Fi", "USB") -> "已守护 Wi-Fi，方式：USB"
    func t(_ id: Int, _ args: CVarArg...) -> String {
        var s = table[id] ?? "#\(id)"
        for (i, a) in args.enumerated() {
            s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)")
        }
        return s
    }
}

func T(_ id: Int, _ args: CVarArg...) -> String {
    switch args.count {
    case 0: return I18n.shared.t(id)
    case 1: return I18n.shared.t(id, args[0])
    default: return I18n.shared.t(id, args[0], args[1])
    }
}

// MARK: - 自愈

final class Healer {
    static let shared = Healer()
    private var lastHeal = Date.distantPast
    private let cooldown: TimeInterval = 90

    func checkAndHeal(reason: String) {
        DispatchQueue.global(qos: .utility).async {
            let cfg = Config.load()
            if Sys.interfaceHealthy(cfg.dev) { return }
            Thread.sleep(forTimeInterval: 3)
            if Sys.interfaceHealthy(cfg.dev) { return }
            guard Date().timeIntervalSince(self.lastHeal) > self.cooldown else { return }
            self.lastHeal = Date()

            if !cfg.usbVID.isEmpty {
                Sys.log("[\(reason)] \(cfg.dev) unhealthy, usb re-enumerate (\(cfg.usbVID):\(cfg.usbPID))...")
                let tool = NSHomeDirectory() + "/.local/bin/usbreset"
                let out = Sys.run("'\(tool)' \(cfg.usbVID) \(cfg.usbPID) 2>&1")
                Sys.log(out)
            } else if !cfg.service.isEmpty {
                Sys.log("[\(reason)] \(cfg.dev) unhealthy, bounce service [\(cfg.service)]...")
                Sys.run("networksetup -setnetworkserviceenabled '\(cfg.service)' off; sleep 3; networksetup -setnetworkserviceenabled '\(cfg.service)' on")
            } else {
                Sys.log("[\(reason)] \(cfg.dev) unhealthy but no target configured")
                return
            }

            for i in 1...12 {
                Thread.sleep(forTimeInterval: 5)
                if Sys.run("ifconfig \(cfg.dev) 2>/dev/null | grep -q 'inet ' && echo y") == "y" {
                    Thread.sleep(forTimeInterval: 2)
                    if !cfg.postCmd.isEmpty { Sys.run(cfg.postCmd) }
                    Sys.log("\(cfg.dev) recovered in ~\(i*5)s")
                    DispatchQueue.main.async { AppDelegate.shared?.refreshIcon() }
                    return
                }
            }
            Sys.log("\(cfg.dev) NOT recovered")
        }
    }
}

// MARK: - 唤醒监听

// IOKit 电源消息常量（Swift 无法导入这些 C 宏，按 IOMessage.h 定义硬编码）
private let kMsgCanSleep:  UInt32 = 0xE000_0270   // kIOMessageCanSystemSleep
private let kMsgWillSleep: UInt32 = 0xE000_0280   // kIOMessageSystemWillSleep
private let kMsgPoweredOn: UInt32 = 0xE000_0300   // kIOMessageSystemHasPoweredOn

final class WakeWatcher {
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notifyPort: IONotificationPortRef?

    func start() {
        let cb: IOServiceInterestCallback = { refcon, _, msgType, msgArg in
            guard let refcon = refcon else { return }
            let me = Unmanaged<WakeWatcher>.fromOpaque(refcon).takeUnretainedValue()
            switch msgType {
            case kMsgCanSleep, kMsgWillSleep:
                IOAllowPowerChange(me.rootPort, Int(bitPattern: msgArg))
            case kMsgPoweredOn:
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    Healer.shared.checkAndHeal(reason: "wake")
                }
            default: break
            }
        }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(ref, &notifyPort, cb, &notifier)
        if rootPort != 0, let np = notifyPort {
            CFRunLoopAddSource(CFRunLoopGetCurrent(),
                               IONotificationPortGetRunLoopSource(np).takeUnretainedValue(),
                               .commonModes)
        }
    }
}

// MARK: - App

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    private let watcher = WakeWatcher()
    private var caffeinate: Process?
    private var keepAwake = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // 不在 Dock 显示
        app.run()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshIcon()
        watcher.start()
        if Config.load().dev.isEmpty || !FileManager.default.fileExists(atPath: Config.path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.pickTarget() }
        }
    }

    func refreshIcon() {
        guard let btn = statusItem.button else { return }
        let cfg = Config.load()
        let healthy = Sys.run("ifconfig \(cfg.dev) 2>/dev/null | grep -q 'inet ' && echo y") == "y"
        let name = keepAwake ? "bolt.horizontal.circle.fill"
                             : (healthy ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "LTE Guard")
        img?.isTemplate = true
        btn.image = img
        buildMenu()
    }

    private func item(_ title: String, _ sel: Selector?, state: NSControl.StateValue = .off,
                      symbol: String? = nil, enabled: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.state = state
        it.isEnabled = enabled
        if let s = symbol {
            let im = NSImage(systemSymbolName: s, accessibilityDescription: nil)
            im?.isTemplate = true
            it.image = im
        }
        return it
    }

    func buildMenu() {
        let cfg = Config.load()
        let m = NSMenu()
        m.addItem(withTitle: T(1), action: nil, keyEquivalent: "").isEnabled = false

        let health = Sys.interfaceHealthy(cfg.dev)
        let target = item(T(2, cfg.service.isEmpty ? cfg.dev : cfg.service, health ? T(3) : T(4)), nil,
                          symbol: health ? "checkmark.circle" : "exclamationmark.triangle")
        target.isEnabled = false
        m.addItem(target)
        let method = item(T(5, cfg.methodText), nil)
        method.isEnabled = false
        m.addItem(method)
        m.addItem(.separator())

        m.addItem(item(T(8), #selector(toggleKeep),
                       state: keepAwake ? .on : .off, symbol: "bolt.fill"))
        m.addItem(item(T(9), #selector(toggleNormal),
                       state: keepAwake ? .off : .on, symbol: "moon.zzz.fill"))
        m.addItem(.separator())
        m.addItem(item(T(10), #selector(pickTarget), symbol: "target"))
        m.addItem(item(T(11), #selector(healNow), symbol: "wrench.and.screwdriver"))
        m.addItem(item(T(12), #selector(openLog), symbol: "doc.text"))

        // 语言子菜单
        let langItem = item(T(13), nil, symbol: "globe")
        let langMenu = NSMenu()
        for (code, name) in I18n.shared.available {
            let li = NSMenuItem(title: name, action: #selector(switchLang(_:)), keyEquivalent: "")
            li.target = self
            li.representedObject = code
            li.state = (code == I18n.shared.code) ? .on : .off
            langMenu.addItem(li)
        }
        langItem.submenu = langMenu
        langItem.isEnabled = true
        m.addItem(langItem)
        m.addItem(.separator())
        m.addItem(item(T(14), #selector(quit), symbol: "power"))
        statusItem.menu = m
    }

    // MARK: 动作

    @objc func toggleKeep() {
        guard !keepAwake else { return }
        let p = Process()
        p.launchPath = "/usr/bin/caffeinate"
        p.arguments = ["-i", "-s"]
        try? p.run()
        caffeinate = p
        keepAwake = true
        Sys.run("sudo -n /usr/bin/pmset -b disablesleep 1 2>/dev/null")
        Sys.log("mode=keep")
        notify(T(19))
        refreshIcon()
    }

    @objc func toggleNormal() {
        caffeinate?.terminate(); caffeinate = nil
        keepAwake = false
        Sys.run("sudo -n /usr/bin/pmset -b disablesleep 0 2>/dev/null")
        Sys.log("mode=normal")
        notify(T(20))
        refreshIcon()
    }

    @objc func pickTarget() {
        let services = Sys.networkServices()
        guard !services.isEmpty else { notify(T(23)); return }

        let alert = NSAlert()
        alert.messageText = T(15)
        alert.informativeText = T(16)
        alert.alertStyle = .informational
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        for (svc, dev) in services {
            let usb = Sys.usbIDs(for: dev) != nil ? "  · USB" : ""
            popup.addItem(withTitle: "\(svc)  [\(dev)]\(usb)")
        }
        let cur = Config.load().dev
        if let idx = services.firstIndex(where: { $0.1 == cur }) { popup.selectItem(at: idx) }
        alert.accessoryView = popup
        alert.addButton(withTitle: T(17))
        alert.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let (svc, dev) = services[popup.indexOfSelectedItem]
        var cfg = Config.load()
        let oldDev = cfg.dev
        cfg.dev = dev
        cfg.service = svc
        if let (v, p) = Sys.usbIDs(for: dev) { cfg.usbVID = v; cfg.usbPID = p }
        else { cfg.usbVID = ""; cfg.usbPID = "" }
        if dev != oldDev { cfg.postCmd = "" }
        cfg.save()
        Sys.log("target -> \(svc) [\(dev)] \(cfg.methodText)")
        notify(T(21, svc, cfg.methodText))
        refreshIcon()
    }

    @objc func switchLang(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        I18n.shared.load(preferred: code)
        Sys.log("lang=\(code)")
        notify(T(24))
        refreshIcon()
    }

    @objc func healNow() {
        notify(T(22))
        Healer.shared.checkAndHeal(reason: "manual")
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: Sys.logPath) {
            try? "".write(toFile: Sys.logPath, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: Sys.logPath))
    }

    @objc func quit() {
        caffeinate?.terminate()
        NSApp.terminate(nil)
    }

    private func notify(_ msg: String) {
        Sys.run("osascript -e 'display notification \"\(msg)\" with title \"LTE Guard\"' >/dev/null 2>&1", wait: false)
    }
}
