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
            case "POST_CMD": c.postCmd = Config.unescape(val)
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
        POST_CMD='\(Config.escape(postCmd))'

        """
        try? text.write(toFile: Config.path, atomically: true, encoding: .utf8)
    }

    /// 写入配置时转义：反斜杠 → \\，换行 → \n，单引号 → \'
    /// （配置文件由本程序自行解析，不交给 shell，因此用统一的自定义转义，
    ///   避免 shell 风格转义在多次读写中累积）
    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "'":  out += "\\'"
            default:   out.append(ch)
            }
        }
        return out
    }

    /// 读取配置时反转义（与 escape 严格成对）
    static func unescape(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let ch = it.next() {
            guard ch == "\\" else { out.append(ch); continue }
            switch it.next() {
            case "n":  out += "\n"
            case "'":  out += "'"
            case "\\": out += "\\"
            case let other?: out.append("\\"); out.append(other)
            case nil:  out += "\\"
            }
        }
        return out
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

    /// usbreset 可执行文件：优先 App 内置资源，回退用户目录（兼容早期手工安装）
    static var usbresetPath: String {
        if let r = Bundle.main.resourcePath {
            let bundled = r + "/usbreset"
            if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        }
        return NSHomeDirectory() + "/.local/bin/usbreset"
    }

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

    /// 枚举所有已连接的 USB 设备 -> [(vid, pid, 显示名)]
    static func usbDevices() -> [(String, String, String)] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching(kIOUSBDeviceClassName), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var out: [(String, String, String)] = []
        while case let dev = IOIteratorNext(iter), dev != 0 {
            defer { IOObjectRelease(dev) }
            func prop(_ k: String) -> Any? {
                IORegistryEntryCreateCFProperty(dev, k as CFString, nil, 0)?.takeRetainedValue()
            }
            guard let v = prop("idVendor") as? Int, let p = prop("idProduct") as? Int else { continue }
            let name = (prop("USB Product Name") as? String)
                ?? (prop("USB Vendor Name") as? String)
                ?? String(format: "%04x:%04x", v, p)
            out.append((String(format: "%04x", v), String(format: "%04x", p), name))
        }
        return out.sorted { $0.2.localizedStandardCompare($1.2) == .orderedAscending }
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
            for f in files where f.hasSuffix(".ini") && !f.hasSuffix(".template.ini") {
                let c = String(f.dropLast(4))
                if found[c] == nil { found[c] = I18n.metaName(dir + "/" + f) ?? c }
            }
        }
        // 排序：汉语及其方言 → 中国少数民族语言 → 其他（按代码）
        let priority = [
            // 汉语及其方言
            "zh-Hans", "zh-Hant", "yue", "nan", "nan-chaoshan", "hak", "wuu", "lzh",
            // 中国少数民族语言
            "bo", "ug", "mn-Mong", "kk",
            // 邻近与友好国家
            "ja", "ko", "vi", "th", "km", "my", "ms", "id", "fil",
            "ru", "kk", "uz", "az", "sr", "rw", "sw", "am", "ha",
        ]
        func rank(_ c: String) -> Int { priority.firstIndex(of: c) ?? priority.count }
        return found.sorted {
            let (a, b) = (rank($0.key), rank($1.key))
            return a != b ? a < b : $0.key < $1.key
        }.map { ($0.key, $0.value) }
    }

    /// 应用配置根目录（菜单中一键打开）
    static var appSupportDir: String {
        NSHomeDirectory() + "/Library/Application Support/LTE Guard"
    }

    /// 用户自定义语言目录
    static var userLangDir: String { appSupportDir + "/lang" }

    static var searchDirs: [String] {
        // 新标准位置 → 旧隐藏路径（向后兼容） → App 内置
        var d = [userLangDir, NSHomeDirectory() + "/.lte-guard-lang"]
        if let r = Bundle.main.resourcePath { d.append(r + "/lang") }
        return d
    }

    /// 确保目录存在，并放一份 en.ini 作为翻译模板
    static func prepareUserLangDir() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: userLangDir, withIntermediateDirectories: true)
        let sample = userLangDir + "/README.txt"
        if !fm.fileExists(atPath: sample) {
            let text = """
            把你自己的 <语言代码>.ini 放在这个文件夹里（例如 nl.ini、sr.ini）。

            最简单的做法：把这里的 zhs.template.ini（简体中文）或 en.template.ini
            （英文）复制一份，改名为目标语言代码，然后翻译每行等号右边的文字。
            重启 LTE Guard 后就会出现在「语言」菜单里。

            同名文件会覆盖 App 内置的版本。
            欢迎把翻译提交到项目，让更多人用上：
            https://github.com/oceantangqoit/Mac-lte-guard

            ---

            Put your own <language>.ini files here (e.g. nl.ini, sr.ini).

            Easiest way: copy zhs.template.ini (Simplified Chinese) or
            en.template.ini here, rename it to your language code, and translate
            the right-hand side of each numbered line. Restart LTE Guard and it
            appears in the Language menu.

            A file here overrides a bundled one with the same name.
            Translation pull requests are very welcome.
            """
            try? text.write(toFile: sample, atomically: true, encoding: .utf8)
        }
        // 附带英文与简体中文两份模板，省去用户去 App 包里翻
        if let r = Bundle.main.resourcePath {
            for (src, dst) in [("en", "en"), ("zh-Hans", "zhs")] {
                let from = r + "/lang/\(src).ini", to = userLangDir + "/\(dst).template.ini"
                if !fm.fileExists(atPath: to) { try? fm.copyItem(atPath: from, toPath: to) }
            }
        }
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

    /// 当前语言是否从右向左书写
    var isRTL: Bool {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return ["ar", "he", "fa", "ur", "ug", "ps", "ckb", "yi", "dv"].contains(base)
    }

    // Unicode 双向算法隔离符（W3C i18n 推荐做法）
    private static let FSI = "\u{2068}"   // First Strong Isolate
    private static let PDI = "\u{2069}"   // Pop Directional Isolate
    static let RLM = "\u{200F}"           // Right-to-Left Mark

    /// 取文案：t(21, "Wi-Fi", "USB") -> "已守护 Wi-Fi，方式：USB"
    /// RTL 语言下，插入值用 FSI/PDI 包裹，避免接口名、VID:PID 等拉丁片段
    /// 被 BiDi 算法重排后标点跑到错误一侧。
    func t(_ id: Int, _ args: CVarArg...) -> String {
        var s = table[id] ?? "#\(id)"
        let rtl = isRTL
        for (i, a) in args.enumerated() {
            let v = rtl ? I18n.FSI + "\(a)" + I18n.PDI : "\(a)"
            s = s.replacingOccurrences(of: "{\(i)}", with: v)
        }
        return s
    }

    /// 段落级方向标记：让整段在 RTL 语言下右对齐显示
    func paragraph(_ s: String) -> String { isRTL ? I18n.RLM + s : s }
}

func T(_ id: Int, _ args: CVarArg...) -> String {
    switch args.count {
    case 0: return I18n.shared.t(id)
    case 1: return I18n.shared.t(id, args[0])
    default: return I18n.shared.t(id, args[0], args[1])
    }
}

// MARK: - 自愈

/// 健康状态缓存：菜单渲染读缓存，实际探测在后台线程
final class HealthCache {
    static let shared = HealthCache()
    private(set) var healthy = true
    private var lastCheck = Date.distantPast

    func value(for dev: String) -> Bool {
        if Date().timeIntervalSince(lastCheck) > 20 { refresh(dev) }
        return healthy
    }

    func refresh(_ dev: String) {
        DispatchQueue.global(qos: .utility).async {
            let h = Sys.interfaceHealthy(dev)
            DispatchQueue.main.async {
                let changed = (h != self.healthy)
                self.healthy = h
                self.lastCheck = Date()
                if changed { AppDelegate.shared?.refreshIcon() }
            }
        }
    }
}

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
                let tool = Sys.usbresetPath
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

// MARK: - 开机自启

/// 菜单栏图标显示模式
enum IconMode: Int {
    case always = 0, problemOnly = 1, hidden = 2
    static var current: IconMode {
        get { IconMode(rawValue: UserDefaults.standard.integer(forKey: "iconMode")) ?? .always }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "iconMode") }
    }
}

enum LaunchAtLogin {
    static let label = "com.oceantang.lteguard"
    static var plistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist" }

    static var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistPath),
              let t = try? String(contentsOfFile: plistPath, encoding: .utf8) else { return false }
        return t.contains(Bundle.main.bundlePath)   // 指向当前这份 App 才算已启用
    }

    /// 旧版本写入的 plist 没有 --background 标记，升级后补写一次
    static func upgradeIfNeeded() {
        guard isEnabled,
              let t = try? String(contentsOfFile: plistPath, encoding: .utf8),
              !t.contains("--background") else { return }
        set(true)
    }

    static func set(_ on: Bool) {
        let uid = getuid()
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Sys.run("launchctl bootout gui/\(uid)/\(label) 2>/dev/null")
        guard on else { try? FileManager.default.removeItem(atPath: plistPath); return }
        let exe = Bundle.main.bundlePath + "/Contents/MacOS/" +
            (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "LTEGuard")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(label)</string>
        <key>ProgramArguments</key><array><string>\(exe)</string><string>--background</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><true/>
        </dict></plist>
        """
        try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        Sys.run("launchctl bootstrap gui/\(uid) '\(plistPath)' 2>/dev/null")
    }
}

// MARK: - 自诊断

struct Diagnosis {
    var lines: [String] = []
    var problems: [String] = []

    static func run() -> Diagnosis {
        var d = Diagnosis()
        let cfg = Config.load()
        let fm = FileManager.default

        // 1 安装位置
        let path = Bundle.main.bundlePath
        d.lines.append("\(T(31)): \(path)")
        if path.contains("/Volumes/") { d.problems.append(T(38)) }

        // 2 隔离属性（Gatekeeper）
        let qtn = Sys.run("xattr -p com.apple.quarantine '\(path)' 2>/dev/null")
        d.lines.append("\(T(32)): \(qtn.isEmpty ? T(35) : T(36))")

        // 3 usbreset 工具
        let tool = Sys.usbresetPath
        let ok = fm.isExecutableFile(atPath: tool)
        d.lines.append("\(T(33)): \(ok ? T(35) : T(36))  \(tool)")
        if !ok && !cfg.usbVID.isEmpty { d.problems.append(T(39)) }

        // 4 目标配置
        if cfg.dev.isEmpty || (cfg.usbVID.isEmpty && cfg.service.isEmpty) {
            d.problems.append(T(40))
        }
        d.lines.append("\(T(34)): \(cfg.service.isEmpty ? cfg.dev : cfg.service) / \(cfg.methodText)")

        // 5 接口是否真实存在
        if Sys.run("ifconfig \(cfg.dev) >/dev/null 2>&1 && echo y") != "y" {
            d.problems.append(T(41, cfg.dev))
        }

        // 6 开机自启
        d.lines.append("\(T(30)): \(LaunchAtLogin.isEnabled ? T(35) : T(36))")
        if !LaunchAtLogin.isEnabled { d.problems.append(T(42)) }

        return d
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
    /// 用户主动唤起时，在此时间点之前强制显示图标（便于调整设置）
    private var forceShowUntil: Date?
    private let forceShowSeconds: TimeInterval = 20

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // 不在 Dock 显示
        app.run()
    }

    /// 用户在 App 已运行时再次打开它 —— 用于找回被隐藏的图标
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        unhideIfNeeded()
        return true
    }

    /// 被用户主动唤起：确保图标露面，便于修改设置
    /// - 隐藏模式：直接恢复为「始终显示」（否则永远没有入口）
    /// - 仅异常时显示：保留偏好，但临时强制显示一段时间供操作
    private func unhideIfNeeded() {
        switch IconMode.current {
        case .hidden:
            IconMode.current = .always
            Sys.log("icon: unhidden by user launch")
            notify(T(60))
        case .problemOnly:
            forceShowUntil = Date().addingTimeInterval(forceShowSeconds)
            Sys.log("icon: temporarily shown for \(Int(forceShowSeconds))s (problemOnly)")
            notify(T(61, Int(forceShowSeconds)))
            // 窗口结束后自动回到「仅异常时显示」
            DispatchQueue.main.asyncAfter(deadline: .now() + forceShowSeconds + 0.5) {
                self.refreshIcon()
            }
        case .always:
            break
        }
        statusItem?.isVisible = true
        refreshIcon()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshIcon()
        watcher.start()
        LaunchAtLogin.upgradeIfNeeded()
        // 非后台自启（即用户主动打开）时，确保图标可见，避免隐藏后找不回来
        if !CommandLine.arguments.contains("--background") { unhideIfNeeded() }
        HealthCache.shared.refresh(Config.load().dev)
        if !FileManager.default.fileExists(atPath: Config.path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.firstRunGuide() }
        }
    }

    func refreshIcon() {
        guard let btn = statusItem.button else { return }
        let cfg = Config.load()
        let healthy = HealthCache.shared.value(for: cfg.dev)

        // 显示模式：强制显示窗口 > 隐藏 / 仅异常时显示
        if let until = forceShowUntil, Date() < until {
            statusItem.isVisible = true
        } else {
            forceShowUntil = nil
            switch IconMode.current {
            case .hidden:      statusItem.isVisible = false
            case .problemOnly: statusItem.isVisible = !healthy
            case .always:      statusItem.isVisible = true
            }
        }
        let name = healthy ? "antenna.radiowaves.left.and.right"
                           : "antenna.radiowaves.left.and.right.slash"
        var img = NSImage(systemSymbolName: name, accessibilityDescription: "LTE Guard")
        if img == nil {   // 旧系统缺该符号时回退
            img = NSImage(systemSymbolName: healthy ? "wifi" : "wifi.slash", accessibilityDescription: "LTE Guard")
        }
        img?.isTemplate = true
        if let img = img { btn.image = img; btn.title = "" }
        else { btn.image = nil; btn.title = healthy ? "LTE" : "LTE!" }
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
        m.userInterfaceLayoutDirection = I18n.shared.isRTL ? .rightToLeft : .leftToRight
        m.addItem(withTitle: T(1), action: nil, keyEquivalent: "").isEnabled = false

        let health = HealthCache.shared.value(for: cfg.dev)
        let target = item(T(2, cfg.service.isEmpty ? cfg.dev : cfg.service, health ? T(3) : T(4)), nil,
                          symbol: health ? "checkmark.circle" : "exclamationmark.triangle")
        target.isEnabled = false
        m.addItem(target)
        let method = item(T(5, cfg.methodText), nil)
        method.isEnabled = false
        m.addItem(method)
        m.addItem(.separator())

        m.addItem(.separator())
        m.addItem(item(T(10), #selector(pickTarget), symbol: "target"))
        m.addItem(item(T(11), #selector(healNow), symbol: "wrench.and.screwdriver"))
        m.addItem(item(T(12), #selector(openLog), symbol: "doc.text"))
        m.addItem(item(T(68), #selector(openConfigFolder), symbol: "folder"))
        m.addItem(item(T(30), #selector(toggleLaunch),
                       state: LaunchAtLogin.isEnabled ? .on : .off, symbol: "power.circle"))
        m.addItem(item(T(29), #selector(showDiagnosis), symbol: "stethoscope"))
        m.addItem(item(T(53), #selector(editPostCmd), symbol: "terminal"))

        // 重置任意 USB 设备（音频接口、摄像头、硬盘、扩展坞等同样会睡眠后假死）
        let usbItem = item(T(75), nil, symbol: "cable.connector")
        let usbMenu = NSMenu()
        usbMenu.userInterfaceLayoutDirection = I18n.shared.isRTL ? .rightToLeft : .leftToRight
        let hint = NSMenuItem(title: T(76), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        usbMenu.addItem(hint)
        usbMenu.addItem(.separator())
        for (vid, pid, name) in Sys.usbDevices() {
            let di = NSMenuItem(title: "\(name)  (\(vid):\(pid))",
                                action: #selector(resetUSBDevice(_:)), keyEquivalent: "")
            di.target = self
            di.representedObject = "\(vid) \(pid) \(name)"
            usbMenu.addItem(di)
        }
        usbItem.submenu = usbMenu
        usbItem.isEnabled = true
        m.addItem(usbItem)

        // 菜单栏图标显示方式
        let iconItem = item(T(48), nil, symbol: "menubar.rectangle")
        let iconMenu = NSMenu()
        iconMenu.userInterfaceLayoutDirection = I18n.shared.isRTL ? .rightToLeft : .leftToRight
        for (mode, title) in [(IconMode.always, T(49)), (.problemOnly, T(50)), (.hidden, T(51))] {
            let mi = NSMenuItem(title: title, action: #selector(setIconMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = mode.rawValue
            mi.state = (IconMode.current == mode) ? .on : .off
            iconMenu.addItem(mi)
        }
        iconItem.submenu = iconMenu
        iconItem.isEnabled = true
        m.addItem(iconItem)

        // 语言子菜单
        let langItem = item(T(13), nil, symbol: "globe")
        let langMenu = NSMenu()
        let disc = NSMenuItem(title: T(69), action: nil, keyEquivalent: "")
        disc.isEnabled = false
        langMenu.addItem(disc)
        langMenu.addItem(.separator())
        langMenu.userInterfaceLayoutDirection = I18n.shared.isRTL ? .rightToLeft : .leftToRight
        for (code, name) in I18n.shared.available {
            let li = NSMenuItem(title: name, action: #selector(switchLang(_:)), keyEquivalent: "")
            li.target = self
            li.representedObject = code
            li.state = (code == I18n.shared.code) ? .on : .off
            langMenu.addItem(li)
        }
        langMenu.addItem(.separator())
        let editCur = NSMenuItem(title: T(71), action: #selector(editCurrentLang), keyEquivalent: "")
        editCur.target = self
        langMenu.addItem(editCur)
        let openDir = NSMenuItem(title: T(67), action: #selector(openLangFolder), keyEquivalent: "")
        openDir.target = self
        langMenu.addItem(openDir)
        langItem.submenu = langMenu
        langItem.isEnabled = true
        m.addItem(langItem)
        m.addItem(.separator())
        m.addItem(item(T(56), #selector(showAbout), symbol: "info.circle"))
        m.addItem(item(T(14), #selector(quit), symbol: "power"))
        statusItem.menu = m
    }

    // MARK: 动作

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

    @objc func setIconMode(_ sender: NSMenuItem) {
        guard let mode = IconMode(rawValue: sender.tag) else { return }
        IconMode.current = mode
        if mode == .hidden { notify(T(52)) }
        refreshIcon()
    }

    /// 恢复后执行命令：GUI 编辑（默认空，未配置不会执行任何东西）
    /// 恢复后执行的命令：多行文本，每行一条，按顺序执行。
    /// 下方提供常用命令的勾选项，勾中即追加到文本框。
    @objc func editPostCmd() {
        var cfg = Config.load()
        let a = NSAlert()
        a.messageText = T(53)
        a.informativeText = I18n.shared.paragraph(T(54))

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 210))

        // 多行命令输入
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 86, width: 440, height: 120))
        let tv = NSTextView(frame: scroll.bounds)
        tv.string = cfg.postCmd
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isRichText = false
        tv.alignment = .left
        tv.baseWritingDirection = .leftToRight
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        box.addSubview(scroll)

        // 常用命令：勾选即追加
        let presets: [(String, String)] = [
            (T(80), "open -b com.apple.systempreferences /System/Library/PreferencePanes/Network.prefPane"),
            (T(81), "osascript -e 'display notification \"\(T(82))\" with title \"LTE Guard\"'"),
            (T(83), "afplay /System/Library/Sounds/Glass.aiff"),
        ]
        var y = 58
        for (title, cmd) in presets {
            let cb = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            cb.frame = NSRect(x: 2, y: y, width: 436, height: 20)
            cb.state = tv.string.contains(cmd) ? .on : .off
            cb.identifier = NSUserInterfaceItemIdentifier(cmd)
            box.addSubview(cb)
            y -= 22
        }

        a.accessoryView = box
        a.addButton(withTitle: T(17))
        a.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        // 合并：手写内容 + 勾选项（去重、保序）
        var lines = tv.string.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for v in box.subviews {
            guard let cb = v as? NSButton, let cmd = cb.identifier?.rawValue else { continue }
            if cb.state == .on {
                if !lines.contains(cmd) { lines.append(cmd) }
            } else {
                lines.removeAll { $0 == cmd }
            }
        }
        cfg.postCmd = lines.joined(separator: "\n")
        cfg.save()
        notify(T(55))
    }

    /// 对任意 USB 设备执行软件拔插。用于音频接口、摄像头、外置硬盘、扩展坞等
    /// 同样会在睡眠唤醒后假死、平时只能物理拔插的设备。
    @objc func resetUSBDevice(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 3 else { return }
        let (vid, pid, name) = (parts[0], parts[1], parts[2])

        let a = NSAlert()
        a.messageText = T(77, name)
        a.informativeText = I18n.shared.paragraph(T(78))
        a.alertStyle = .warning
        a.addButton(withTitle: T(17))
        a.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            Sys.log("[manual] reset USB device \(name) (\(vid):\(pid))")
            let out = Sys.run("'\(Sys.usbresetPath)' \(vid) \(pid) 2>&1")
            Sys.log(out)
            DispatchQueue.main.async { self.notify(T(79, name)) }
        }
    }

    @objc func toggleLaunch() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        notify(LaunchAtLogin.isEnabled ? T(43) : T(44))
        refreshIcon()
    }

    @objc func showDiagnosis() {
        let d = Diagnosis.run()
        let a = NSAlert()
        a.messageText = T(29)
        a.informativeText = I18n.shared.paragraph(d.lines.joined(separator: "\n"))
            + (d.problems.isEmpty ? "\n\n✅ " + T(45)
                                  : "\n\n⚠️ " + T(46) + "\n• " + d.problems.joined(separator: "\n• "))
        a.alertStyle = d.problems.isEmpty ? .informational : .warning
        a.addButton(withTitle: T(17))
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// 首次运行引导：说明 → 选网卡 → 开机自启
    private func firstRunGuide() {
        let a = NSAlert()
        a.messageText = T(25)
        a.informativeText = I18n.shared.paragraph(T(26))
        a.alertStyle = .informational
        a.addButton(withTitle: T(27))
        a.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        pickTarget()

        let b = NSAlert()
        b.messageText = T(28)
        b.informativeText = I18n.shared.paragraph(T(47))
        b.addButton(withTitle: T(27))
        b.addButton(withTitle: T(18))
        if b.runModal() == .alertFirstButtonReturn { LaunchAtLogin.set(true) }
        refreshIcon()
    }

    @objc func healNow() {
        notify(T(22))
        Healer.shared.checkAndHeal(reason: "manual")
    }

    /// 编辑当前语言：从 App 内置复制一份到用户目录（同名文件优先级更高）。
    /// 导出的副本会**移除原作者署名并改为当前使用者**——此后该文件的内容
    /// 由使用者自己负责，与原作者无关。改完重启 App 即生效。
    @objc func editCurrentLang() {
        I18n.prepareUserLangDir()
        let code = I18n.shared.code
        let fm = FileManager.default
        let dst = I18n.userLangDir + "/\(code).ini"

        if !fm.fileExists(atPath: dst), let r = Bundle.main.resourcePath {
            // 先给出责任移交提示，用户确认后才导出
            let a = NSAlert()
            a.messageText = T(73)
            a.informativeText = I18n.shared.paragraph(T(74))
            a.alertStyle = .informational
            a.addButton(withTitle: T(17))
            a.addButton(withTitle: T(18))
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }

            guard var text = try? String(contentsOfFile: r + "/lang/\(code).ini", encoding: .utf8)
            else { NSWorkspace.shared.open(URL(fileURLWithPath: I18n.userLangDir)); return }

            // 移除原作者署名与联系方式，改为当前使用者
            let who = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (i, l) in lines.enumerated() {
                if l.hasPrefix("author=") {
                    lines[i] = "author=\(who)"
                } else if l.hasPrefix("64=") {          // 关于中的作者署名
                    lines[i] = "64=\(who)"
                } else if l.hasPrefix("65=") || l.hasPrefix("66=") {   // 邮箱与城市
                    lines[i] = String(l.prefix(3))
                }
            }
            text = lines.joined(separator: "\n")

            // 文件头写明责任归属，避免日后混淆
            let banner = """
            # ⚠️ 本文件已由使用者导出并可自由修改。
            #    原作者署名已移除，本文件内容由 \(who) 负责，与原作者无关。
            #    This file was exported for local editing. The original author's
            #    credit has been removed; \(who) is responsible for its contents.
            #

            """
            text = banner + text
            try? text.write(toFile: dst, atomically: true, encoding: .utf8)
        }

        guard fm.fileExists(atPath: dst) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: I18n.userLangDir)); return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: dst))
        notify(T(72, code))
    }

    /// 在访达中打开自定义语言目录（自动创建并放入模板）
    @objc func openLangFolder() {
        I18n.prepareUserLangDir()
        NSWorkspace.shared.open(URL(fileURLWithPath: I18n.userLangDir))
    }

    /// 一键打开配置文件夹：内含配置文件、日志与语言目录的入口
    @objc func openConfigFolder() {
        let fm = FileManager.default
        let dir = I18n.appSupportDir
        I18n.prepareUserLangDir()   // 顺带建好 lang/ 与模板

        // 配置文件与日志实际在家目录（保持兼容），这里放软链接方便访问
        for (target, name) in [(Config.path, "lte-guard.conf"), (Sys.logPath, "lte-guard.log")] {
            if !fm.fileExists(atPath: target) {
                try? "".write(toFile: target, atomically: true, encoding: .utf8)
            }
            let link = dir + "/" + name
            if !fm.fileExists(atPath: link) {
                try? fm.createSymbolicLink(atPath: link, withDestinationPath: target)
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: Sys.logPath) {
            try? "".write(toFile: Sys.logPath, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: Sys.logPath))
    }

    @objc func showAbout() {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let a = NSAlert()
        a.messageText = "LTE Guard \(ver)"
        a.informativeText = I18n.shared.paragraph("\(T(57))\n\n\(T(64))\n\(T(66))\n\(T(65))\n\n\(T(70))\n\n\(T(59))")
        a.alertStyle = .informational
        a.addButton(withTitle: T(58))       // 项目主页
        a.addButton(withTitle: T(17))       // 确定
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://github.com/oceantangqoit/Mac-lte-guard") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func notify(_ msg: String) {
        Sys.run("osascript -e 'display notification \"\(msg)\" with title \"LTE Guard\"' >/dev/null 2>&1", wait: false)
    }
}
