import Cocoa
import CoreGraphics

// MARK: - 活动感知（插件性质，默认关闭）

/// 三种感知模式
enum ActivitySenseMode: Int {
    case off = 0       // 不感知
    case builtin = 1   // 内建（零权限：前台App + 空闲时间 + 电源状态）
    case activityWatch = 2  // 对接 ActivityWatch（localhost:5600）
}

/// 当前活动的快照
struct ActivitySnapshot {
    var app = ""          // 前台 App 名称
    var bundleID = ""     // 包标识
    var idleSeconds = 0   // 用户无操作秒数
    var onBattery = false
    var charging = false
    var batteryPct = -1
    var awExtra = ""      // ActivityWatch 返回的附加上下文
}

/// 插件性质的活动感知模块。绝大多数用户不会开启——默认 off，
/// 开启后只在发 webhook/写日志时附带一行「当前活动」摘要。
/// 提供两种实现：内建（零权限，用 macOS 公开 API）与对接
/// 开源项目 ActivityWatch（需用户自行安装并运行 aw-server）。
final class ActivitySense {
    static let shared = ActivitySense()

    private var timer: DispatchSourceTimer?
    private let csvLock = NSLock()
    /// 采样间隔（秒）
    private let interval: TimeInterval = 60

    var mode: ActivitySenseMode {
        ActivitySenseMode(rawValue: Config.load().activitySense) ?? .off
    }

    /// 单次快照，不缓存——调一次取一次
    func snapshot() -> ActivitySnapshot {
        guard mode != .off else { return ActivitySnapshot() }
        var s = sampleBuiltin()
        if mode == .activityWatch { s.awExtra = queryAW() }
        return s
    }

    /// 供 webhook / 日志追加使用的一行中文摘要
    func summary() -> String {
        let s = snapshot()
        var parts: [String] = []
        if !s.app.isEmpty {
            parts.append(s.app)
        }
        if s.idleSeconds > 10 {
            let m = s.idleSeconds / 60
            parts.append(m > 0 ? T(248, "\(m)") : T(249))
        }
        if s.batteryPct >= 0 {
            parts.append(s.charging ? T(250, "\(s.batteryPct)") : T(251, "\(s.batteryPct)"))
        }
        if !s.awExtra.isEmpty { parts.append(s.awExtra) }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    // ── 内建采样（零权限：NSWorkspace + CGEventSource + IOKit）──

    private func sampleBuiltin() -> ActivitySnapshot {
        var s = ActivitySnapshot()
        // 前台 App —— NSWorkspace 无需权限
        if let fg = NSWorkspace.shared.frontmostApplication {
            s.app = fg.localizedName ?? ""
            s.bundleID = fg.bundleIdentifier ?? ""
        }
        // 空闲时间 —— CGEventSource 无需权限
        s.idleSeconds = Int(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown))
        let mouseIdle = Int(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved))
        if mouseIdle < s.idleSeconds { s.idleSeconds = mouseIdle }

        // 电源状态 —— pmset 无需特殊权限
        let pmset = Process()
        pmset.launchPath = "/usr/bin/pmset"
        pmset.arguments = ["-g", "batt"]
        let pipe = Pipe(); pmset.standardOutput = pipe; pmset.standardError = FileHandle.nullDevice
        pmset.launch(); pmset.waitUntilExit()
        let batt = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // pmset 输出如："Now drawing from 'AC Power'  -InternalBattery-0 (id=xxx)	100%; charged; ..."
        s.charging = batt.contains("AC Power")
        s.onBattery = batt.contains("Battery Power")
        if let open = batt.range(of: "\t"), let close = batt[open.upperBound...].range(of: "%") {
            let num = batt[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            s.batteryPct = Int(num) ?? -1
        }
        return s
    }

    // ── ActivityWatch 对接 ──

    private func queryAW() -> String {
        let base = "http://127.0.0.1:5600/api/0"
        let host = (Host.current().localizedName ?? "").replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".local", with: "")
        // 尝试读窗口 watcher 的最新事件
        let buckets = ["aw-watcher-window_\(host)", "aw-watcher-afk_\(host)"]
        var extras: [String] = []
        for bid in buckets {
            guard let raw = httpGET("\(base)/buckets/\(bid)/events?limit=1"),
                  let data = raw.data(using: .utf8),
                  let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
                  let last = arr.last,
                  let dataObj = last["data"] as? [String: Any] else { continue }
            if bid.contains("window"), let title = dataObj["title"] as? String, !title.isEmpty {
                extras.append(title)
            } else if bid.contains("afk"), let status = dataObj["status"] as? String {
                if status != "not-afk" { extras.append(T(252)) }
            }
        }
        return extras.joined(separator: " | ")
    }

    private func httpGET(_ url: String) -> String? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 2)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data { result = String(data: data, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 2.5)
        return result
    }

    // MARK: - CSV 记录

    /// 启动定时采样写入 CSV。mode=off 或路径为空时不启动。
    /// 每次 App 启动 / 用户改设置后调一次——先停旧 timer 再起新的。
    func startCSVRecording() {
        timer?.cancel()
        timer = nil
        let cfg = Config.load()
        guard cfg.activitySense != 0, !cfg.activityCSV.isEmpty else { return }
        ensureHeader(cfg.activityCSV)
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now() + 5, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// 停止记录（切到 off 时调）
    func stopCSVRecording() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let s = snapshot()
        let cfg = Config.load()
        guard !cfg.activityCSV.isEmpty else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let row = [
            f.string(from: Date()),
            csvEsc(s.app),
            csvEsc(s.bundleID),
            "\(s.idleSeconds)",
            s.onBattery ? "1" : "0",
            s.charging ? "1" : "0",
            "\(s.batteryPct)",
            csvEsc(s.awExtra),
        ].joined(separator: ",")
        appendRow(row, to: cfg.activityCSV)
    }

    /// CSV 转义：含逗号、引号、换行的字段用双引号包裹，内部引号翻倍
    private func csvEsc(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func ensureHeader(_ path: String) {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let header = "time,app,bundle_id,idle_sec,on_battery,charging,battery_pct,aw_extra\n"
        try? header.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func appendRow(_ row: String, to path: String) {
        csvLock.lock(); defer { csvLock.unlock() }
        let line = row + "\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8) ?? Data())
            h.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
