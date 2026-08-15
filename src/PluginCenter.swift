import Cocoa

// MARK: - 插件中心
// 外置插件（采集器/律师日志/DDNS）的统一登记处：二进制路径、运行状态探测、
// 启动参数组装、输出目录与运行标志的持久化（UserDefaults）。
// 运行标志的语义：用户点过「启动」即视为"应该在跑"——App 重启后照此恢复，
// 点「停止」即清除，不再拉起。

enum PluginID: String {
    case raw = "raw"
    case lawyer = "lawyer"
    case ddns = "ddns"
}

enum PluginCenter {

    // ── 路径与状态 ──

    /// 开发仓库内插件二进制路径（本机 = 开发机）
    static func bin(_ id: PluginID) -> String {
        let rel: String
        switch id {
        case .raw: rel = "3_raw_recorder/bin/raw_recorder"
        case .lawyer: rel = "2_lawyer_log/bin/lawyer_log"
        case .ddns: rel = "4_cloudflare_ddns/bin/cf_ddns"
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("lte-guard-share/plugins").appendingPathComponent(rel).path
    }

    /// pgrep 匹配片段
    static func match(_ id: PluginID) -> String {
        switch id {
        case .raw: return "bin/raw_recorder"
        case .lawyer: return "bin/lawyer_log"
        case .ddns: return "bin/cf_ddns"
        }
    }

    static func built(_ id: PluginID) -> Bool {
        FileManager.default.isExecutableFile(atPath: bin(id))
    }

    /// 默认输出目录
    static func defaultDir(_ id: PluginID) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch id {
        case .raw: return home.appendingPathComponent("Documents/lte-guard-raw").path
        case .lawyer: return home.appendingPathComponent("Documents").path
        case .ddns: return home.appendingPathComponent("Documents/lte-guard-ddns").path
        }
    }

    /// 用户指定的输出目录（未指定用默认）
    static func outDir(_ id: PluginID) -> String {
        let v = UserDefaults.standard.string(forKey: "plugin.\(id.rawValue).dir") ?? ""
        return v.isEmpty ? defaultDir(id) : v
    }

    static func setOutDir(_ id: PluginID, _ dir: String) {
        UserDefaults.standard.set(dir, forKey: "plugin.\(id.rawValue).dir")
        // 换了目录且正在跑：重启进程让新目录立即生效
        if running(id) { stop(id); start(id) }
    }

    // ── 运行标志（持久化）与进程状态（实时）──

    static func flagged(_ id: PluginID) -> Bool {
        UserDefaults.standard.bool(forKey: "plugin.\(id.rawValue).on")
    }

    static func running(_ id: PluginID) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", match(id)]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return !pipe.fileHandleForReading.readDataToEndOfFile().isEmpty
    }

    // ── 启动 / 停止 ──

    @discardableResult
    static func start(_ id: PluginID) -> Bool {
        guard built(id), !running(id) else { return flagged(id) }
        let dir = outDir(id)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let args: [String]
        switch id {
        case .raw:
            args = [dir + "/raw.jsonl"]
        case .lawyer:
            args = ["--csv", dir + "/lawyer-work-log.csv", "--ask", "off"]
        case .ddns:
            let c = ddnsConfig()
            guard c.complete else { return false }
            args = ["--token", c.token, "--zone", c.zone, "--record", c.record,
                    "--interval", "\(c.interval)", "--ttl", "\(c.ttl)", "--dir", dir]
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin(id))
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            UserDefaults.standard.set(true, forKey: "plugin.\(id.rawValue).on")
            return true
        } catch { return false }
    }

    static func stop(_ id: PluginID) {
        UserDefaults.standard.set(false, forKey: "plugin.\(id.rawValue).on")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-INT", "-f", match(id)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// App 启动时调用：凡标记"应该在跑"而实际没在跑的，拉起来。
    /// 覆盖重启、崩溃、被系统杀掉三种情形；用户主动停过的不动。
    static func restoreAll() {
        DispatchQueue.global(qos: .utility).async {
            for id in [PluginID.raw, .lawyer, .ddns] where flagged(id) && !running(id) {
                if start(id) { Sys.log(T(272, name(id))) }
            }
        }
    }

    static func name(_ id: PluginID) -> String {
        switch id {
        case .raw: return T(262)
        case .lawyer: return T(263)
        case .ddns: return T(276)
        }
    }

    // ── DDNS 配置（UserDefaults 持久化）──

    struct DDNSConfig {
        var token = "", zone = "", record = ""
        var interval = 300, ttl = 1
        var complete: Bool { !token.isEmpty && !zone.isEmpty && !record.isEmpty }
    }

    static func ddnsConfig() -> DDNSConfig {
        let d = UserDefaults.standard
        var c = DDNSConfig()
        c.token = d.string(forKey: "plugin.ddns.token") ?? ""
        c.zone = d.string(forKey: "plugin.ddns.zone") ?? ""
        c.record = d.string(forKey: "plugin.ddns.record") ?? ""
        c.interval = max(30, d.object(forKey: "plugin.ddns.interval") as? Int ?? 300)
        c.ttl = max(1, d.object(forKey: "plugin.ddns.ttl") as? Int ?? 1)
        return c
    }

    static func saveDDNS(_ c: DDNSConfig) {
        let d = UserDefaults.standard
        d.set(c.token, forKey: "plugin.ddns.token")
        d.set(c.zone, forKey: "plugin.ddns.zone")
        d.set(c.record, forKey: "plugin.ddns.record")
        d.set(c.interval, forKey: "plugin.ddns.interval")
        d.set(c.ttl, forKey: "plugin.ddns.ttl")
    }

    /// DDNS 状态（面板展示用）：读插件写的 ddns-state.json
    static func ddnsState() -> (ip: String, update: String, result: String)? {
        let path = outDir(.ddns) + "/ddns-state.json"
        guard let data = FileManager.default.contents(atPath: path),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (d["ip"] as? String ?? "", d["last_update"] as? String ?? "",
                d["last_result"] as? String ?? "")
    }
}
