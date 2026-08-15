import Cocoa
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

// MARK: - 插件2：律师工作日志守护程序
// 观察屏幕/盖子/网络/键鼠/窗口/目录 → 规则引擎判定工作片段 → 只写有价值的工作日志 CSV。
// 无法归属案件的片段会弹对话框询问（可 --ask off 关闭）。
//
// 用法：
//   ./build.sh
//   bin/lawyer_log                       # 默认规则 + 默认日志 ~/Documents/lawyer-work-log.csv
//   bin/lawyer_log --rules Rules.json    # 加载 AI 分析产出的规则
//   bin/lawyer_log --csv /path/log.csv   # 指定日志文件
//   bin/lawyer_log --ask off             # 关闭询问
//   bin/lawyer_log --debug               # 每 5 秒打印当前状态

// ── 规则模型（对应 ../PROMPT.md 的输出格式）──

struct SegmentRule: Codable {
    var idleCutoffSec: Int = 600
    var minSegmentMin: Int = 3
    var mergeGapMin: Int = 10
    enum CodingKeys: String, CodingKey {
        case idleCutoffSec = "idle_cutoff_sec"
        case minSegmentMin = "min_segment_min"
        case mergeGapMin = "merge_gap_min"
    }
}

struct ActivityType: Codable {
    var type: String
    var labelZh: String
    var rules: [String]
    var note: String = ""
    enum CodingKeys: String, CodingKey {
        case type, rules, note
        case labelZh = "label_zh"
    }
}

struct CaseRule: Codable {
    var pathPatterns: [String] = []
    var personSuffixes: [String] = ["诉", "vs", "v."]
    var companySuffixes: [String] = ["有限公司", "股份公司", "有限责任公司", "事务所", "集团", "律所"]
    var docKeywords: [String] = ["起诉状", "答辩状", "上诉状", "代理词", "合同", "尽调报告", "法律意见书", "协议"]
    var askWhen: String = ""
    enum CodingKeys: String, CodingKey {
        case pathPatterns = "path_patterns"
        case personSuffixes = "person_suffixes"
        case companySuffixes = "company_suffixes"
        case docKeywords = "doc_keywords"
        case askWhen = "ask_when"
    }
}

struct RuleConfig: Codable {
    var schemaVersion: Int = 1
    var segment: SegmentRule = SegmentRule()
    var activityTypes: [ActivityType] = []
    var caseExtraction: CaseRule = CaseRule()
    var common: [String] = []
    var personal: [String] = []
    enum CodingKeys: String, CodingKey {
        case segment = "segment"
        case activityTypes = "activity_types"
        case caseExtraction = "case_extraction"
        case common, personal
        case schemaVersion = "schema_version"
    }

    /// 内置兜底规则：没有 Rules.json 时也能跑起来（通用启发式，非律师专用）
    static var builtin: RuleConfig {
        var c = RuleConfig()
        c.activityTypes = [
            ActivityType(type: "drafting", labelZh: "文书写作", rules: [
                "app in [Word, Pages, Typora, WPS]",
                "title matches /起诉状|答辩状|上诉状|代理词|合同|意见书|.docx?|.pages/",
            ], note: "文字类软件 + 法律文书/办公文档标题"),
            ActivityType(type: "research", labelZh: "案例检索", rules: [
                "app in [Safari, Chrome, Edge]",
                "title matches /裁判文书|北大法宝|威科|无讼|alpha|法信|裁判/",
            ], note: "浏览器 + 法律数据库域名"),
            ActivityType(type: "client_comms", labelZh: "当事人沟通", rules: [
                "app in [微信, WeChat, QQ, Mail, 邮件]",
                "title matches /微信|WeChat|邮件|Mail/",
            ], note: "通讯/邮件软件"),
            ActivityType(type: "meeting", labelZh: "会议/会见", rules: [
                "app in [腾讯会议, Zoom, Teams, 钉钉]",
                "title matches /会议|Meeting|会见|zoom|teams/",
            ], note: "视频会议软件"),
            ActivityType(type: "research_docs", labelZh: "卷宗研读", rules: [
                "title matches /pdf|PDF|扫描|卷宗/",
            ], note: "PDF/卷宗类阅读"),
            ActivityType(type: "admin", labelZh: "行政事务", rules: [
                "app in [Numbers, Excel, 日历, Calendar, 提醒事项, Reminders]",
            ], note: "表格/日程类"),
        ]
        return c
    }

    static func load(path: String?) -> RuleConfig {
        guard let p = path, let data = FileManager.default.contents(atPath: p),
              let cfg = try? JSONDecoder().decode(RuleConfig.self, from: data) else {
            print("未找到 Rules.json，使用内置兜底规则")
            return builtin
        }
        print("已加载规则: \(p)")
        return cfg
    }
}

// ── 日志写入 ──

final class LogWriter {
    let path: String
    private let lock = NSLock()
    init(path: String) {
        self.path = path
        if !FileManager.default.fileExists(atPath: path) {
            let header = "start,end,duration_min,case,type,type_zh,app,dir,window_title,note\n"
            try? header.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
    func append(_ cols: [String]) {
        lock.lock(); defer { lock.unlock() }
        let esc = cols.map { c in
            c.contains(",") || c.contains("\"") ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c
        }.joined(separator: ",")
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write((esc + "\n").data(using: .utf8) ?? Data())
            h.closeFile()
        }
    }
    var lastLine: [String]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.split(separator: "\n").map(String.init)
        guard lines.count >= 2 else { return nil }
        return lines.last!.split(separator: ",").map(String.init)
    }
}

// ── 询问机制（osascript 弹对话框）──

func askUser(_ q: String) -> String {
    let script = "set v to text returned of (display dialog \"\(q)\" default answer \"\" buttons {\"跳过\", \"确定\"} default button 2)"
    let p = Process()
    p.launchPath = "/usr/bin/osascript"
    p.arguments = ["-e", script]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run(); p.waitUntilExit() } catch { return "" }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// ── 规则引擎 ──

struct Segment {
    var start = Date()
    var appCounts: [String: Int] = [:]
    var titleCounts: [String: Int] = [:]
    var dirCounts: [String: Int] = [:]
    var bundle = ""
    func dominant(_ dict: [String: Int]) -> String {
        dict.max(by: { $0.value < $1.value })?.key ?? ""
    }
    var durationMin: Double { Date().timeIntervalSince(start) / 60 }
}

final class Engine {
    let rules: RuleConfig
    let writer: LogWriter
    let askEnabled: Bool
    let debug: Bool
    var current: Segment?
    var lastFinalized: (caseName: String, end: Date)?
    let fmt: DateFormatter

    init(rules: RuleConfig, writer: LogWriter, askEnabled: Bool, debug: Bool) {
        self.rules = rules
        self.writer = writer
        self.askEnabled = askEnabled
        self.debug = debug
        self.fmt = DateFormatter()
        self.fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    /// 每次采样驱动状态机
    func onSample(_ s: SensorData) {
        // 键鼠都空闲超阈值/屏幕熄 → 结束片段（取两者较小值：任一设备有活动都算人在）
        if min(s.kbdIdleSec, s.mouseIdleSec) >= rules.segment.idleCutoffSec || s.displaySleep {
            if current != nil { finalize(note: s.displaySleep ? "屏幕熄灭" : "空闲超时") }
            return
        }
        if current == nil {
            current = Segment()
            current!.bundle = s.bundleID
        }
        var seg = current!
        seg.appCounts[s.app, default: 0] += 1
        if !s.windowTitle.isEmpty { seg.titleCounts[s.windowTitle, default: 0] += 1 }
        if !s.dir.isEmpty { seg.dirCounts[s.dir, default: 0] += 1 }
        current = seg
        if debug { print("[\(s.ts)] \(s.app) · \(s.windowTitle) · kbd_idle=\(s.kbdIdleSec) mouse_idle=\(s.mouseIdleSec)") }
    }

    /// 系统睡眠 → 结束片段
    func onPower(_ ev: String) {
        if ev == "sleep" { finalize(note: "系统睡眠") }
    }

    private func finalize(note: String) {
        guard let seg = current else { return }
        current = nil
        let dmin = seg.durationMin
        guard dmin >= Double(rules.segment.minSegmentMin) else { return } // 过短丢弃
        let app = seg.dominant(seg.appCounts)
        let title = seg.dominant(seg.titleCounts)
        let dir = seg.dominant(seg.dirCounts)
        let type = classify(app: app, title: title, dir: dir)
        let caseName = extractCase(title: title, dir: dir)

        // 合并：同案且间隔小于 merge_gap → 更新上一条
        let end = Date()
        if let last = writer.lastLine, last.count >= 8,
           last[3] == caseName,
           let lastEnd = parse(last[1]),
           end.timeIntervalSince(lastEnd) < Double(rules.segment.mergeGapMin) * 60,
           last[5] == type {
            // 就地更新：重新写一行合并后的
            let startStr = last[0]
            let dur = String(format: "%.0f", end.timeIntervalSince(parse(last[0])!) / 60)
            writer.append([startStr, fmt.string(from: end), dur, caseName, type,
                           label(type), last[6], last[7], last[8], "合并"])
            print("  [合并] \(caseName) 延长至 \(fmt.string(from: end))")
            return
        }

        var extraNote = note
        // 无法归属且是实质工作 → 询问
        if caseName.isEmpty && type != "break" && askEnabled {
            let q = "刚才约 \(Int(dmin)) 分钟在做「\(label(type))」（\(app)）。办的是谁的案件/什么事？"
            let answer = askUser(q)
            if !answer.isEmpty {
                writer.append([fmt.string(from: seg.start), fmt.string(from: end),
                               String(format: "%.0f", dmin), answer, type,
                               label(type), app, dir, title, ""])
                print("  [记录·已补答] \(answer)")
                lastFinalized = (answer, end)
                return
            }
            extraNote = "待补充案件"
        }
        writer.append([fmt.string(from: seg.start), fmt.string(from: end),
                       String(format: "%.0f", dmin), caseName, type,
                       label(type), app, dir, title, extraNote])
        print("  [记录] \(fmt.string(from: seg.start)) ~ \(fmt.string(from: end)) \(dmin)min · \(caseName.isEmpty ? "?" : caseName) · \(label(type))")
        lastFinalized = (caseName, end)
    }

    private func parse(_ s: String) -> Date? {
        fmt.date(from: s)
    }

    // ── 活动类型判定 ──
    private func classify(app: String, title: String, dir: String) -> String {
        let t = "\(app) \(title) \(dir)"
        for at in rules.activityTypes {
            for r in at.rules {
                if match(rule: r, text: t, app: app) { return at.type }
            }
        }
        return "other_work"
    }
    private func label(_ type: String) -> String {
        rules.activityTypes.first { $0.type == type }?.labelZh ?? type
    }
    /// 规则匹配：支持 "app in [a, b]"、"title matches /re/"、"key contains x"
    private func match(rule: String, text: String, app: String) -> Bool {
        let r = rule.trimmingCharacters(in: .whitespaces)
        if r.hasPrefix("app in") {
            let inner = r.replacingOccurrences(of: "app in", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let names = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return names.contains { app.contains($0) || $0.contains(app) }
        }
        if r.hasPrefix("title matches") {
            guard let open = r.firstIndex(of: "/"), let close = r.lastIndex(of: "/"),
                  open < close else { return false }
            let pattern = String(r[r.index(after: open)..<close])
            if let regex = try? NSRegularExpression(pattern: pattern) {
                return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
            }
            return false
        }
        if r.contains(" contains ") {
            let parts = r.components(separatedBy: " contains ")
            return parts.count == 2 && text.contains(parts[1])
        }
        return false
    }

    // ── 案件归属提取 ──
    private func extractCase(title: String, dir: String) -> String {
        let ce = rules.caseExtraction
        let text = "\(title) \(dir)"
        // "X诉Y" 模式
        for suf in ce.personSuffixes {
            let pattern = "([\\u4e00-\\u9fa5]{1,6})\(NSRegularExpression.escapedPattern(for: suf))([\\u4e00-\\u9fa5]{1,6})"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                return (text as NSString).substring(with: m.range)
            }
        }
        // 公司名模式
        for suf in ce.companySuffixes {
            let pattern = "[\\u4e00-\\u9fa5A-Za-z0-9]{2,20}\(NSRegularExpression.escapedPattern(for: suf))"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                return (text as NSString).substring(with: m.range)
            }
        }
        // 路径倒数第二段（若含法律文书关键词则取整段上一级）
        let dirParts = dir.split(separator: "/").map(String.init)
        if dirParts.count >= 2, ce.docKeywords.contains(where: { dirParts.last?.contains($0) ?? false }) {
            return dirParts[dirParts.count - 2]
        }
        return ""
    }
}

// ── 电源监听（IOKit）──

private let kMsgWillSleep: UInt32 = 0xE000_0280
private let kMsgPoweredOn: UInt32 = 0xE000_0300

final class PowerWatcher {
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notifyPort: IONotificationPortRef?
    private var onEvent: ((String) -> Void)?
    func start(onEvent: @escaping (String) -> Void) {
        self.onEvent = onEvent
        DispatchQueue.global(qos: .background).async { [self] in
            let cb: IOServiceInterestCallback = { refcon, _, msgType, _ in
                guard let refcon = refcon else { return }
                let me = Unmanaged<PowerWatcher>.fromOpaque(refcon).takeUnretainedValue()
                if msgType == kMsgWillSleep { me.onEvent?("sleep") }
                if msgType == kMsgPoweredOn { me.onEvent?("wake") }
            }
            let ref = Unmanaged.passUnretained(self).toOpaque()
            self.rootPort = IORegisterForSystemPower(ref, &self.notifyPort, cb, &self.notifier)
            if self.rootPort != 0, let np = self.notifyPort {
                CFRunLoopAddSource(CFRunLoopGetCurrent(),
                                   IONotificationPortGetRunLoopSource(np).takeUnretainedValue(),
                                   .commonModes)
            }
            CFRunLoopRun()
        }
    }
}

// ── 入口 ──

var rulesPath: String?
var csvPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Documents").appendingPathComponent("lawyer-work-log.csv").path
var askEnabled = true
var debug = false

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--rules": rulesPath = args.removeFirst()
    case "--csv": csvPath = args.removeFirst()
    case "--ask": askEnabled = args.removeFirst() != "off"
    case "--debug": debug = true
    default: break
    }
}

let rules = RuleConfig.load(path: rulesPath)
let writer = LogWriter(path: csvPath)
let engine = Engine(rules: rules, writer: writer, askEnabled: askEnabled, debug: debug)
print("律师工作日志守护程序运行中")
print("  规则: \(rulesPath ?? "内置兜底") · 日志: \(csvPath) · 询问: \(askEnabled ? "开" : "关")")

let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
timer.schedule(deadline: .now() + 2, repeating: 5)
timer.setEventHandler {
    let s = Sensors.sample()
    engine.onSample(s)
}
timer.resume()

PowerWatcher().start { ev in engine.onPower(ev) }

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sig.setEventHandler { print("停止"); exit(0) }
sig.resume()
let sigT = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigT.setEventHandler { print("停止"); exit(0) }
sigT.resume()

dispatchMain()
