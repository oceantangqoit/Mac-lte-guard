import Cocoa
import CoreGraphics
import SystemConfiguration

// MARK: - 共享采集核心（插件2/3 共用）
// 原则：只调零权限或尽力而为的 API，失败一律留空，绝不弹权限框。

/// 一次采样的全部信号
struct SensorData {
    var ts = ""             // 时间戳 yyyy-MM-dd HH:mm:ss
    var app = ""            // 前台 App 名
    var bundleID = ""
    var pid = -1
    var windowTitle = ""    // 窗口标题（需屏幕录制权限，无则空）
    var dir = ""            // 启发式提取的"激活目录"
    var idleSec = -1        // 键鼠空闲秒数
    var mouseMovedSec = -1  // 鼠标/触摸板移动距今秒数
    var charging = false
    var onBattery = false
    var batteryPct = -1
    var iface = ""          // 默认路由接口：en0 Wi-Fi / en2 LTE / enX 以太网
    var gateway = ""
    var ip = ""
    var ssid = ""           // 尽力而为，拿不到为空
    var displays = 0        // 外接显示器数量（含内建）
    var displaySleep = false
    var cpu = 0.0           // CPU 占用率 0-100
    var memFree = 0.0       // 可用内存 GB
    var btDevices: [String] = []   // 蓝牙配对设备名列表（尽力而为）
}

/// 转 JSON 字典（供 JSONL 输出）
extension SensorData {
    var json: [String: Any] {
        [
            "ts": ts, "app": app, "bundle_id": bundleID, "pid": pid,
            "window_title": windowTitle, "dir": dir,
            "idle_sec": idleSec, "mouse_moved_sec": mouseMovedSec,
            "charging": charging, "on_battery": onBattery, "battery_pct": batteryPct,
            "iface": iface, "gateway": gateway, "ip": ip, "ssid": ssid,
            "displays": displays, "display_sleep": displaySleep,
            "cpu": cpu, "mem_free_gb": memFree,
            "bt": btDevices,
        ]
    }
    var jsonLine: String {
        (try? JSONSerialization.data(withJSONObject: json))!
            .withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
    }
}

enum Sensors {

    // ── 命令辅助 ──

    static func run(_ cmd: String, _ args: [String]) -> String {
        let p = Process()
        p.launchPath = cmd
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // ── 时间 ──

    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    // ── 前台 App（零权限）──

    static func frontmostApp() -> (name: String, bundleID: String, pid: Int) {
        if let fg = NSWorkspace.shared.frontmostApplication {
            return (fg.localizedName ?? "", fg.bundleIdentifier ?? "", Int(fg.processIdentifier))
        }
        return ("", "", -1)
    }

    // ── 窗口标题（需要屏幕录制权限，无权限返回空，绝不弹框）──

    static func frontWindowTitle(pid: Int) -> String {
        guard pid > 0 else { return "" }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int) == pid else { continue }
            guard (w[kCGWindowLayer as String] as? Int ?? 0) == 0 else { continue }
            if let name = w[kCGWindowName as String] as? String, !name.isEmpty { return name }
            return w[kCGWindowOwnerName as String] as? String ?? ""
        }
        return ""
    }

    // ── 激活目录（启发式：从窗口标题提取路径；cwd 无权限拿不到）──

    static func activeDirectory(windowTitle: String) -> String {
        // 启发式：从窗口标题提取路径片段（如 ~/cases/张三诉李四/合同.pdf、/Volumes/卷宗/...），
        // 取最长片段作为"激活目录"；cwd 无权限拿不到，标题里也没有就返回空。
        let pattern = #"(?:\.\./|~/)?(?:[\w.\-]+/){1,}[\w.\-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = windowTitle as NSString
        var candidates: [String] = []
        for m in regex.matches(in: windowTitle, range: NSRange(location: 0, length: ns.length)) {
            candidates.append(ns.substring(with: m.range))
        }
        return candidates.max(by: { $0.count < $1.count }) ?? ""
    }

    // ── 键鼠空闲（零权限）──

    static func idleSeconds() -> (idle: Int, mouseMovedSec: Int) {
        let keyIdle = Int(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown))
        let mouseIdle = Int(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved))
        return (keyIdle, mouseIdle)
    }

    // ── 电源（pmset，零权限）──

    static func power() -> (charging: Bool, onBattery: Bool, pct: Int) {
        let out = run("/usr/bin/pmset", ["-g", "batt"])
        let charging = out.contains("AC Power")
        let onBattery = out.contains("Battery Power")
        var pct = -1
        if let open = out.range(of: "\t"), let close = out[open.upperBound...].range(of: "%") {
            pct = Int(out[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)) ?? -1
        }
        return (charging, onBattery, pct)
    }

    // ── 网络：默认路由接口 / 网关 / IP（零权限）──

    static func defaultRoute() -> (iface: String, gateway: String) {
        let out = run("/sbin/route", ["-n", "get", "default"])
        var iface = "", gateway = ""
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "interface": iface = parts[1]
            case "gateway": gateway = parts[1]
            default: break
            }
        }
        return (iface, gateway)
    }

    static func ifIP(_ iface: String) -> String {
        guard !iface.isEmpty else { return "" }
        return run("/usr/sbin/ipconfig", ["getifaddr", iface]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ── SSID（尽力而为：SCDynamicStore，不申请位置权限）──

    static func ssid(_ iface: String) -> String {
        guard !iface.isEmpty, let store = SCDynamicStoreCreate(nil, "lteguard-plugin" as CFString, nil, nil) else { return "" }
        let key = "State:/Network/Interface/\(iface)/AirPort/CurrentNetwork" as CFString
        guard let val = SCDynamicStoreCopyValue(store, key) as? [CFString: Any] else { return "" }
        if let name = val["SSID" as CFString] as? String { return name }
        if let data = val["SSID" as CFString] as? Data { return String(data: data, encoding: .utf8) ?? "" }
        return ""
    }

    // ── 显示器（零权限）──

    static func displays() -> (count: Int, asleep: Bool) {
        (NSScreen.screens.count, CGDisplayIsAsleep(CGMainDisplayID()) == 1)
    }

    // ── CPU / 内存（mach，零权限）──

    static func cpuUsage() -> Double {
        var info = host_cpu_load_info_data_t()
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { $0 } }, &size)
        guard r == KERN_SUCCESS else { return 0 }
        let used = Double(info.cpu_ticks.0 + info.cpu_ticks.1 + info.cpu_ticks.2)
        let total = used + Double(info.cpu_ticks.3)
        return total > 0 ? used / total * 100 : 0
    }

    static func memFreeGB() -> Double {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        return Double(stats.free_count + stats.inactive_count) * page / 1e9
    }

    // ── 蓝牙配对设备（尽力而为，读系统 plist；读不到返回空）──

    static func btPairedDevices() -> [String] {
        let path = "/Library/Preferences/com.apple.Bluetooth.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else { return [] }
        var names: [String] = []
        if let cache = dict["DeviceCache"] as? [String: [String: Any]] {
            for (_, v) in cache {
                if let n = v["Name"] as? String, !n.isEmpty { names.append(n) }
            }
        }
        return names.sorted()
    }

    // ── 全量采样 ──

    static func sample() -> SensorData {
        var s = SensorData()
        s.ts = now()
        let fg = frontmostApp()
        s.app = fg.name; s.bundleID = fg.bundleID; s.pid = fg.pid
        s.windowTitle = frontWindowTitle(pid: fg.pid)
        s.dir = activeDirectory(windowTitle: s.windowTitle)
        let idle = idleSeconds()
        s.idleSec = idle.idle; s.mouseMovedSec = idle.mouseMovedSec
        let pw = power()
        s.charging = pw.charging; s.onBattery = pw.onBattery; s.batteryPct = pw.pct
        let rt = defaultRoute()
        s.iface = rt.iface; s.gateway = rt.gateway
        s.ip = ifIP(rt.iface)
        s.ssid = ssid(rt.iface)
        let d = displays()
        s.displays = d.count; s.displaySleep = d.asleep
        s.cpu = cpuUsage()
        s.memFree = memFreeGB()
        s.btDevices = btPairedDevices()
        return s
    }
}
