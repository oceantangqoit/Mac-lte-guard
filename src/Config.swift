import Cocoa

// MARK: - 配置

/// 一个治愈对象：一块网卡（或其背后的 USB 设备）
struct Target: Equatable {
    var dev = ""       // BSD 接口名，如 en2
    var service = ""   // 网络服务名
    var vid = ""       // USB VID；为空 = 非 USB，降级为重启网络服务
    var pid = ""

    var display: String { service.isEmpty ? dev : service }
    var methodText: String { vid.isEmpty ? T(7) : T(6, vid, pid) }
}

struct Config {
    var targets: [Target] = []
    var preCmd = ""    // 发现断联时执行（此刻网络不可用）
    var postCmd = ""   // 恢复后执行
    /// 勾选了「操作通报」的敏感操作代号（发生时发 webhook）
    var notifyOps: Set<String> = []
    /// Webhook 配置（单一真相源：只在「通知与通报」里设，由程序内建发送）
    var whPlatform = 0
    var whURL = ""
    var whRich = false
    /// 被守护的 USB 设备（vid、pid、名称）。与网卡守护刻意分开：
    /// 网卡有 IP、网关、ping 三重判据可断健康，普通 USB 设备没有——
    /// 守护它只能是「唤醒后无条件复位一次」，风险与语义都不同，不该混为一谈
    var usbGuards: [(vid: String, pid: String, name: String)] = []
    /// 查到新版本后是否直接装上（不提示）。不勾就只下载好并留一条「已就绪」
    var silentInstall = false
    /// 查询间隔（秒）。0 表示「从不」，即完全不查。
    /// 档位见 Updater.intervalChoices：30 秒到 1 个月，开发调试用得上最短那档
    var updateInterval = 0
    /// 活动感知模式（插件性质，默认关闭）：
    /// 0 = 关闭，1 = 内建（零权限），2 = 对接 ActivityWatch
    var activitySense = 0
    /// 活动感知 CSV 记录文件路径（空 = 不写文件，只在 webhook 里附带）
    var activityCSV = ""

    // 兼容视图：部分旧代码路径仍以"第一个对象"工作
    var dev: String { targets.first?.dev ?? "" }
    var service: String { targets.first?.service ?? "" }
    var usbVID: String { targets.first?.vid ?? "" }
    var usbPID: String { targets.first?.pid ?? "" }

    static var path: String { I18n.appSupportDir + "/lte-guard.conf" }

    static func load() -> Config {
        var c = Config()
        var old = Target()   // 旧版单对象四键
        var sawTargets = false
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return c }
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { continue }
            let key = String(s[s.startIndex..<eq])
            let raw = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            // TARGETS/PRE_CMD/POST_CMD 的值里可能含 \n、'、"   #lteguard" 标记，
            // 绝不能走"剥行尾注释"，必须按引号边界+转义规则解析（\' 不是结束，裸 ' 才是）
            if key == "WEBHOOK_URL" {
                c.whURL = Config.parseQuoted(raw) ?? raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                continue
            }
            if key == "WEBHOOK_PLATFORM" || key == "WEBHOOK_RICH"
                || key == "SILENT_UPDATE" || key == "UPDATE_INTERVAL"
                || key == "ACTIVITY_SENSE" || key == "ACTIVITY_CSV" {
                let v = Config.parseQuoted(raw) ?? raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                switch key {
                case "WEBHOOK_PLATFORM": c.whPlatform = Int(v) ?? 0
                case "WEBHOOK_RICH":     c.whRich = (v == "1")
                case "SILENT_UPDATE":    c.silentInstall = (v == "1")
                case "ACTIVITY_SENSE":   c.activitySense = max(0, min(2, Int(v) ?? 0))
                case "ACTIVITY_CSV":     c.activityCSV = v
                default:                 c.updateInterval = max(0, Int(v) ?? 0)
                }
                continue
            }
            if key == "USB_GUARDS" {
                let v = Config.parseQuoted(raw) ?? Config.unescape(
                    raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")))
                c.usbGuards = v.split(separator: "\n").compactMap { row in
                    let f = row.components(separatedBy: "\t")
                    guard f.count >= 3, !f[0].isEmpty else { return nil }
                    return (vid: f[0], pid: f[1], name: f[2])
                }
                continue
            }
            if key == "NOTIFY_OPS" {
                let v = Config.parseQuoted(raw) ?? raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                c.notifyOps = Set(v.split(separator: ",").map(String.init).filter { !$0.isEmpty })
                continue
            }
            if key == "POST_CMD" || key == "PRE_CMD" || key == "TARGETS" {
                let v = Config.parseQuoted(raw) ?? Config.unescape(
                    raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")))
                switch key {
                case "PRE_CMD":  c.preCmd = v
                case "POST_CMD": c.postCmd = v
                default:
                    sawTargets = true
                    c.targets = v.split(separator: "\n").compactMap { row in
                        let f = row.components(separatedBy: "\t")
                        guard f.count >= 4, !f[0].isEmpty else { return nil }
                        return Target(dev: f[0], service: f[1], vid: f[2], pid: f[3])
                    }
                }
                continue
            }

            var val = raw
            if let hash = val.range(of: "  #") { val = String(val[val.startIndex..<hash.lowerBound]) }
            val = val.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            switch key {
            case "DEV": old.dev = val
            case "SERVICE": old.service = val
            case "USB_VID": old.vid = val
            case "USB_PID": old.pid = val
            default: break
            }
        }
        // 旧版 conf（无 TARGETS 键）→ 单对象升级
        if !sawTargets && !old.dev.isEmpty { c.targets = [old] }
        return c
    }

    func save() {
        let rows = targets.map { "\($0.dev)\t\($0.service)\t\($0.vid)\t\($0.pid)" }
            .joined(separator: "\n")
        let text = """
        # LTE Guard 配置（由 App 维护，也可手改）
        # TARGETS：每行一个治愈对象，字段以制表符分隔：接口\t服务名\tUSB_VID\tUSB_PID
        TARGETS='\(Config.escape(rows))'
        USB_GUARDS='\(Config.escape(usbGuards.map { "\($0.vid)\t\($0.pid)\t\($0.name)" }.joined(separator: "\n")))'
        NOTIFY_OPS='\(notifyOps.sorted().joined(separator: ","))'
        WEBHOOK_PLATFORM='\(whPlatform)'
        WEBHOOK_URL='\(whURL)'
        WEBHOOK_RICH='\(whRich ? 1 : 0)'
        SILENT_UPDATE='\(silentInstall ? 1 : 0)'
        UPDATE_INTERVAL='\(updateInterval)'
        ACTIVITY_SENSE='\(activitySense)'
        ACTIVITY_CSV='\(Config.escape(activityCSV))'
        PRE_CMD='\(Config.escape(preCmd))'
        POST_CMD='\(Config.escape(postCmd))'

        """
        try? FileManager.default.createDirectory(atPath: I18n.appSupportDir, withIntermediateDirectories: true)
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

    /// 解析单引号包裹、内含转义的值：提取引号内内容并反转义。
    /// 值内的单引号在写入时被转为 \'，因此扫描中跳过转义对，
    /// 遇到的第一个裸单引号即值的终点（其后即使有注释也安全忽略）。
    /// 不是单引号开头则返回 nil（交给兼容回退路径）。
    static func parseQuoted(_ raw: String) -> String? {
        guard raw.first == "'" else { return nil }
        var out = ""
        var it = raw.dropFirst().makeIterator()
        while let ch = it.next() {
            if ch == "'" { return out }
            guard ch == "\\" else { out.append(ch); continue }
            switch it.next() {
            case "n":  out += "\n"
            case "'":  out += "'"
            case "\\": out += "\\"
            case let other?: out.append("\\"); out.append(other)
            case nil:  out += "\\"
            }
        }
        return out   // 未见闭引号：容错，返回已解析部分
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

    /// v2.3 一次性迁移：只处理带 #lteguard 标记的程序行，手写行永不触碰。
    /// - 旧「打开网络设置」预设 → 换成新 URL 并挪到 PRE_CMD（观察修复过程）
    /// - 旧「提示恢复」「验证能否上网」预设 → 移除（已内建为原生通知）
    mutating func migrateV23() -> Bool {
        var changed = false
        var post: [String] = []
        for raw in postCmd.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix("#lteguard") else { post.append(raw); continue }
            if Sys.isNetworkPaneCmd(line) {
                let entry = "\(Sys.openNetworkPaneCmd)   #lteguard"
                let already = preCmd.split(separator: "\n").contains { Sys.isNetworkPaneCmd(String($0)) }
                if !already {
                    preCmd = preCmd.isEmpty ? entry : preCmd + "\n" + entry
                }
                changed = true
            } else if line.contains("captive.apple.com") || line.contains("display notification") {
                changed = true   // 功能已内建，移除
            } else {
                post.append(raw)
            }
        }
        if changed { postCmd = post.joined(separator: "\n") }
        return changed
    }
}
