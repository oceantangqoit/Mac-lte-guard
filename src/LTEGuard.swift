// LTE Guard — 菜单栏常驻 App
// 睡眠策略切换 + 治愈对象选择 + 状态查看 + 唤醒自愈守护
import Cocoa
import IOKit
import IOKit.pwr_mgt
import IOKit.usb
import UserNotifications
import LocalAuthentication

// MARK: - 身份验证（Touch ID / 锁屏密码）
// 不自建密码：LocalAuthentication 由系统管理凭据，App 零存储。
// 两类场景：
//   · 敏感操作（命令编辑/退出/关自启/拍照开关/配置文件夹）——受总开关控制
//   · 签约场景（语言文件责任移交、USB 数据风险确认）——始终验证，
//     生物识别/密码即签名，确认动作可归属到本人
enum Auth {
    static var guardEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "authGuard") }
        set { UserDefaults.standard.set(newValue, forKey: "authGuard") }
    }

    /// 模态对话框期间主队列不排程，回调必须用 common modes 派发才能及时执行
    static func onMain(_ block: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common], block: block)
    }

    /// 验证通过才执行 action；机器没有任何验证手段（未设锁屏密码）时直接放行
    static func require(then action: @escaping () -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            action(); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: T(131)) { ok, _ in
            if ok { onMain(action) }
        }
    }

    /// 敏感操作入口：开关未开则直接执行
    static func gate(then action: @escaping () -> Void) {
        guardEnabled ? require(then: action) : action()
    }

    /// 签约场景：始终验证，并把使用的验证方式告知回调（供签约存档记录）
    static func sign(then action: @escaping (_ method: String) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // 机器未设锁屏密码：无凭据可验，仅凭点击确认（存档中如实记录）
            action("confirmation click only — no device credential set")
            return
        }
        let bio = ctx.biometryType == .touchID ? "Touch ID or device password"
                                                : "device password"
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: T(131)) { ok, _ in
            if ok { onMain { action("\(bio) (LocalAuthentication)") } }
        }
    }
}

// MARK: - 签约存档
// 责任移交/风险确认属于"签约"：验证即签名，存档即立据。
// 每次签约在配置目录 agreement/ 下留一份可读文本，内容固定中英双语，
// 并原文保留确认时展示的条款（按当时的界面语言）。
enum Agreement {
    static var dir: String { I18n.appSupportDir + "/agreement" }

    static func record(kind: String, subject: String, terms: String, method: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let now = Date()
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let human = DateFormatter(); human.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let who = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let text = """
        LTE Guard \(ver) — Agreement Record / 签约存档
        =============================================
        Time    时间：\(human.string(from: now))
        Type    类型：\(kind)
        Subject 对象：\(subject)
        Signer  签署人：\(who)
        Method  确认方式：\(method)

        Terms as shown at confirmation / 确认时展示的条款原文：
        ---------------------------------------------
        \(terms)
        ---------------------------------------------
        The signer confirmed and accepted the terms above via the method stated.
        签署人已通过上述方式确认并接受以上条款。
        """
        let safe = subject.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let name = "\(stamp.string(from: now))_\(kind)_\(String(safe)).txt"
        try? text.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8)
        Sys.log(T(135, name))
    }

    /// 是否已签署过某类协议（如拍照协议签一次即可，不重复打扰）
    static func hasRecord(kind: String) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .contains { $0.contains("_\(kind)_") }
    }

    /// 《门卫室拍照功能使用协议》——中文为准，英文为参考译文
    static let cameraTerms = """
    《门卫室拍照功能使用协议》

    一、功能说明。开启本功能后，本软件将在检测到网络断联和/或恢复时调用本机摄像头拍摄照片。照片仅保存于本机配置目录 gatehouse 文件夹，本软件不上传、不对外传输，作者亦无法接触照片内容。

    二、用户承诺。用户承诺仅将本功能用于保护本人合法持有之设备的正当目的；不得用于偷拍、监视、跟踪他人，或实施其他侵害他人肖像权、名誉权、隐私权、个人信息权益的行为；拍摄范围可能涉及第三人的，用户应依法自行履行告知、提示义务并取得必要同意。

    三、责任承担与免责。用户使用本功能的一切行为及其后果由用户自行承担；因用户违反法律法规或本协议使用本功能而产生的任何民事、行政或刑事责任，均由用户自行承担，与作者无关。本软件系依 MIT 许可按"现状"免费提供的开源软件，作者不对本功能的适用性、连续性及照片的完整性作出任何明示或默示的保证。

    四、数据管理。照片的保管、使用与删除均由用户自行负责。

    五、法律适用。本协议的订立、效力、解释与争议解决，适用中华人民共和国法律。

    六、签署。用户通过 Touch ID 或设备密码完成身份验证，即视为已阅读、理解并同意本协议全部条款；签署记录存于配置目录 agreement 文件夹。本协议以中文文本为准，英文译文仅供参考。

    Gatehouse Camera Feature Agreement (reference translation — the Chinese text prevails)
    1. When enabled, this software takes photos via the built-in camera upon network disconnection and/or recovery. Photos are stored only in the local "gatehouse" folder; nothing is uploaded, and the author has no access to them.
    2. The user undertakes to use this feature solely for the legitimate purpose of protecting the user's own lawfully held device; not for candid photography, surveillance, stalking, or any act infringing others' portrait, reputation, privacy, or personal-information rights; where third parties may be captured, the user shall give due notice and obtain necessary consent as required by law.
    3. All consequences of using this feature are borne by the user alone. Any civil, administrative, or criminal liability arising from unlawful or non-compliant use rests with the user and not the author. This is open-source software provided free of charge "as is" under the MIT License, without any express or implied warranty.
    4. Storage, use, and deletion of photos are the user's own responsibility.
    5. This agreement is governed by the laws of the People's Republic of China.
    6. Verification via Touch ID or the device password constitutes the user's signature and acceptance of all terms; the signed record is kept in the "agreement" folder.
    """
}
import AVFoundation

// MARK: - 门卫室（断联/恢复时拍照留档）

/// 拍照核心，两条触发路径共用：
/// - App 进程内：Healer 执行 pre/post 命令时拦截含 --snap 的行，直接调 take()（快，无第二进程）
/// - 命令行：`LTEGuard --snap [标签]` 第二实例拍完把照片路径打到 stdout 后退出——
///   供用户 shell 组合，如 curl -T "$(… --snap)" 'ntfy地址' 把照片推到手机（webhook 接口）
enum CameraSnap {
    /// 目录实名固定英文（跨语言稳定）；各语言界面里的「门卫室/gatehouse/garita…」都指它
    static var dir: String { I18n.appSupportDir + "/gatehouse" }

    static var authorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// 拍一张存进门卫室，文件名 = 时间戳_标签.jpg。完成回调带路径（失败为 nil）
    static func take(tag: String, completion: @escaping (String?) -> Void) {
        guard authorized else { completion(nil); return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let session = AVCaptureSession()
        session.sessionPreset = .photo
        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else { completion(nil); return }
        session.addInput(input)
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else { completion(nil); return }
        session.addOutput(output)
        session.startRunning()

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let path = "\(dir)/\(f.string(from: Date()))_\(tag).jpg"

        // 等曝光/白平衡稳定再拍，否则常是一张全黑
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            let delegate = SnapDelegate { data in
                session.stopRunning()
                if let d = data, (try? d.write(to: URL(fileURLWithPath: path))) != nil {
                    Sys.log(T(127, path))
                    completion(path)
                } else {
                    completion(nil)
                }
            }
            snapDelegateKeeper = delegate   // 持有到回调完成
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    /// 命令行模式：同步等待拍照完成，打印路径。photo 权限未授权时先请求（会弹系统框）
    static func runCLI(tag: String) -> Never {
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { sem.signal(); return }
            DispatchQueue.main.async {
                take(tag: tag) { p in result = p; sem.signal() }
            }
        }
        // 主线程跑 RunLoop 让 AVFoundation 回调得以派发，后台线程等结果
        DispatchQueue.global().async {
            _ = sem.wait(timeout: .now() + 15)
            if let p = result { print(p); exit(0) } else { exit(1) }
        }
        RunLoop.main.run()
        exit(1)
    }
}

private var snapDelegateKeeper: AnyObject?

private final class SnapDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let done: (Data?) -> Void
    init(_ done: @escaping (Data?) -> Void) { self.done = done }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        done(error == nil ? photo.fileDataRepresentation() : nil)
        snapDelegateKeeper = nil
    }
}

// MARK: - 原生通知
// osascript 的 display notification 在现代 macOS 上会被静默丢弃
//（发送者是"脚本编辑器"，默认无通知权限），必须用 App 自己的通知。
enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, err in
            Sys.log(granted ? T(114) : T(115, err?.localizedDescription ?? ""))
        }
    }

    static func post(_ body: String, title: String = "LTE Guard") {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { st in
            if st.authorizationStatus == .authorized {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let req = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
                center.add(req) { err in
                    if let err = err { Sys.log(T(115, err.localizedDescription)) }
                }
            } else {
                // 未授权 / ad-hoc 签名被拒 → 老 API 兜底（已废弃但仍可投递）
                let n = NSUserNotification()
                n.title = title
                n.informativeText = body
                NSUserNotificationCenter.default.deliver(n)
            }
        }
    }
}

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

// MARK: - 系统操作

enum Sys {
    @discardableResult
    static func run(_ cmd: String, wait: Bool = true) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
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

    static var logPath: String { I18n.appSupportDir + "/lte-guard.log" }

    /// IOKit 默认端口。kIOMainPortDefault（12+）与 kIOMasterPortDefault（已废弃）
    /// 的值都是 0，用命名常量同时兼容新旧系统
    static let ioDefaultPort: mach_port_t = 0

    /// 打开「系统设置 → 网络」——macOS 13 起是 x-apple URL，
    /// 更早的系统只认 prefPane 路径（在 13+ 上反而会落到 Wi-Fi 页）
    static var openNetworkPaneCmd: String {
        if #available(macOS 13.0, *) {
            return "open \"x-apple.systempreferences:com.apple.Network-Settings.extension\""
        }
        return "open -b com.apple.systempreferences /System/Library/PreferencePanes/Network.prefPane"
    }

    /// 该行是否为「打开网络面板」命令（任一历史变体）。
    /// 迁移去重、执行时替换共用这一份判定，新增变体只改这里
    static func isNetworkPaneCmd(_ line: String) -> Bool {
        line.contains("Network-Settings.extension") || line.contains("Network.prefPane")
    }

    /// 执行用户配置的命令前逐行解析：配置里可能存着在其他系统版本上写入的
    /// 网络面板命令变体（配置会跟着系统升级走），执行时刻替换为当前系统的
    /// 正确形式——版本分支挂在执行层，持久化的字符串形态就无所谓了
    static func resolveUserCmds(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                isNetworkPaneCmd(String(line)) ? openNetworkPaneCmd : String(line)
            }
            .joined(separator: "\n")
    }

    /// 执行用户命令：含 --snap 的行走 App 进程内拍照（快，不起第二实例），
    /// 其余合并交给 shell。用户手写的 $(… --snap) 组合行含命令替换符，
    /// 不拆——整行交 shell 由 CLI 模式接住
    static func runUserCmds(_ text: String, wait: Bool) {
        var shellLines: [String] = []
        for raw in resolveUserCmds(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("--snap") && !t.contains("$(") {
                let tag = t.contains("restored") ? "restored" : (t.contains("wake") ? "wake" : "snap")
                DispatchQueue.main.async { CameraSnap.take(tag: tag) { _ in } }
            } else if !t.isEmpty {
                shellLines.append(line)
            }
        }
        if !shellLines.isEmpty { run(shellLines.joined(separator: "\n"), wait: wait) }
    }

    /// 一次性迁移：配置与日志的真身从家目录隐藏文件搬到标准
    /// Application Support 目录（此前那里只放替身）。历史日志保留。
    static func migrateLegacyFiles() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: I18n.appSupportDir, withIntermediateDirectories: true)
        for (old, new) in [(NSHomeDirectory() + "/.lte-guard.conf", Config.path),
                           (NSHomeDirectory() + "/.lte-wake.log", logPath)] {
            guard fm.fileExists(atPath: old) else { continue }
            // 新位置若是此前放的替身，先删替身再搬真身
            if let t = (try? fm.attributesOfItem(atPath: new))?[.type] as? FileAttributeType,
               t == .typeSymbolicLink {
                try? fm.removeItem(atPath: new)
            }
            if !fm.fileExists(atPath: new) { try? fm.moveItem(atPath: old, toPath: new) }
        }
        // v2.8 短暂用过中文目录名「门卫室」，统一为 gatehouse
        let oldSnap = I18n.appSupportDir + "/门卫室"
        if fm.fileExists(atPath: oldSnap) && !fm.fileExists(atPath: CameraSnap.dir) {
            try? fm.moveItem(atPath: oldSnap, toPath: CameraSnap.dir)
        }
    }

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
            try? FileManager.default.createDirectory(atPath: I18n.appSupportDir, withIntermediateDirectories: true)
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
        guard IOServiceGetMatchingServices(Sys.ioDefaultPort,
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
        let svc = IOServiceGetMatchingService(Sys.ioDefaultPort, match as CFDictionary)
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
        // 局域网关正常 <10ms 应答，1 秒超时足够；假死时快速失败让修复更早启动
        return run("ping -c 1 -t 1 -b \(dev) \(gw) >/dev/null 2>&1 && echo y") == "y"
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
            "zh-Hans", "zh-Hant", "yue", "cmn-sichuan", "cmn-dongbei", "cmn-henan",
            "cmn-shaanxi", "hsn", "cmn-xinjiang", "nan", "nan-chaoshan", "hak", "wuu", "lzh",
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
        // 附带英文与简体中文两份模板，省去用户去 App 包里翻。
        // 无条件覆盖：模板不应被用户编辑（应复制改名后翻译），
        // 覆盖才能保证升级后模板始终与当前版本的键位同步
        if let r = Bundle.main.resourcePath {
            for (src, dst) in [("en", "en"), ("zh-Hans", "zhs")] {
                let from = r + "/lang/\(src).ini", to = userLangDir + "/\(dst).template.ini"
                try? fm.removeItem(atPath: to)
                try? fm.copyItem(atPath: from, toPath: to)
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
        // ini 是单行格式，文案里的换行写作字面 \n——在这里统一还原，
        // 否则对话框会把 "\n\n" 原样显示出来
        s = s.replacingOccurrences(of: "\\n", with: "\n")
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
    case 2: return I18n.shared.t(id, args[0], args[1])
    default: return I18n.shared.t(id, args[0], args[1], args[2])
    }
}

// MARK: - 自愈

/// 健康状态缓存：菜单渲染读缓存，实际探测在后台线程
final class HealthCache {
    static let shared = HealthCache()
    private var map: [String: Bool] = [:]   // 接口 → 健康（主线程访问）
    private var lastCheck = Date.distantPast

    /// 单接口状态（菜单逐对象显示用）
    func healthy(_ dev: String) -> Bool { map[dev] ?? true }

    /// 全部对象都健康才算健康（图标用）；超过 20 秒自动后台刷新
    func value(for devs: [String]) -> Bool {
        if Date().timeIntervalSince(lastCheck) > 20 { refresh(devs) }
        return devs.allSatisfy { healthy($0) }
    }

    func refresh(_ devs: [String]) {
        lastCheck = Date()
        DispatchQueue.global(qos: .utility).async {
            let results = devs.map { ($0, Sys.interfaceHealthy($0)) }
            DispatchQueue.main.async {
                var changed = false
                for (dev, h) in results {
                    if self.map[dev] != h { changed = true }
                    self.map[dev] = h
                }
                if changed { AppDelegate.shared?.refreshIcon() }
            }
        }
    }
}

final class Healer {
    static let shared = Healer()
    /// 按对象记录上次修复时间。冷却期只为吸收双路唤醒信号
    ///（IOKit + NSWorkspace）的重复触发；再次唤醒/手动时立即可再修
    private var lastHeal: [String: Date] = [:]
    private let cooldown: TimeInterval = 15
    /// 串行队列保护冷却表与修复计数；修复本体并行执行
    private let q = DispatchQueue(label: "lteguard.healer", qos: .utility)

    /// 有修复在进行中（图标显示用，主线程访问）
    private(set) var healing = false
    private var active = 0

    private func healingDelta(_ d: Int) {
        DispatchQueue.main.async {
            self.active += d
            self.healing = self.active > 0
            AppDelegate.shared?.refreshIcon()
        }
    }

    /// 唤醒（wake）：不做状态预检——装本工具的人就是假死受害者，唤醒即修，
    /// 对健康设备多做一次软件拔插无害，预检反而白白拖慢恢复。
    /// 手动（manual）：「检测并修复」——先逐个检测，全部正常就反馈无需修复；
    /// 只修异常的，且不受冷却期限制（用户点了就要立即响应）。
    /// 启动（launch）：补救"App 启动前就发生过睡眠"的空档（如开机停在
    /// 登录界面时睡过，登录后 App 才起来，唤醒事件早已错过）——
    /// 逻辑同手动（先检测、坏才修），但全部健康时静默，不打扰。
    func checkAndHeal(reason: String) {
        q.async {
            let cfg = Config.load()
            let now = Date()
            let due: [Target]
            if reason == "manual" || reason == "launch" {
                let sick = cfg.targets.filter { !$0.dev.isEmpty && !Sys.interfaceHealthy($0.dev) }
                HealthCache.shared.refresh(cfg.targets.map(\.dev))
                if sick.isEmpty {
                    if reason == "manual" {
                        Notifier.post(T(119))
                        AppDelegate.shared?.flashResult("✓")
                    }
                    return
                }
                due = sick
            } else {
                due = cfg.targets.filter { t in
                    !t.dev.isEmpty &&
                    now.timeIntervalSince(self.lastHeal[t.dev] ?? .distantPast) > self.cooldown
                }
            }
            guard !due.isEmpty else { return }
            due.forEach { self.lastHeal[$0.dev] = now }

            // ── 「断联时命令」第一时间抢跑（如打开网络面板——它冷启动要 2-4 秒，
            //    必须赶在拔插前开跑，用户才能看到从断联到恢复的全过程）──
            if !cfg.preCmd.isEmpty { Sys.runUserCmds(cfg.preCmd, wait: false) }
            // USB 子系统上电就绪缓冲（原唤醒延迟挪到这里，不再拖累 preCmd）
            Thread.sleep(forTimeInterval: 1)

            // 各对象并行修复；全部结束且至少一个成功后，执行一次「恢复后命令」
            let group = DispatchGroup()
            var anyOK = false
            for t in due {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let ok = self.heal(t, reason: reason)
                    self.q.async { anyOK = anyOK || ok; group.leave() }
                }
            }
            group.notify(queue: self.q) {
                if anyOK && !cfg.postCmd.isEmpty { Sys.runUserCmds(cfg.postCmd, wait: true) }
            }
        }
    }

    /// 修复单个对象：拔插 → 1 秒粒度轮询 → 内建联网验证。
    /// 通知只报喜（一切正常才发）；修复中/网不通/失败由图标表达
    ///（转圈 / ⚠︎ / ✕），不打扰用户。
    private func heal(_ t: Target, reason: String) -> Bool {
        healingDelta(+1)
        defer { healingDelta(-1) }
        let t0 = Date()
        let rTxt = reason == "wake" ? T(110)
                 : reason == "launch" ? T(130)
                 : T(111)   // 日志里的触发原因也本地化

        if !t.vid.isEmpty {
            Sys.log(T(93, rTxt, t.dev, "\(t.vid):\(t.pid)"))
            let out = Sys.run("'\(Sys.usbresetPath)' \(t.vid) \(t.pid) 2>&1")
            // usbreset 是英文输出的 C 工具：成功时记本地化文案，失败才保留原始输出便于排查
            Sys.log(out.contains("OK") ? T(112, "\(t.vid):\(t.pid)") : T(113, out))
        } else if !t.service.isEmpty {
            Sys.log(T(94, rTxt, t.dev, t.service))
            Sys.run("networksetup -setnetworkserviceenabled '\(t.service)' off; sleep 3; networksetup -setnetworkserviceenabled '\(t.service)' on")
        } else {
            Sys.log(T(95, rTxt, t.dev))
            AppDelegate.shared?.flashResult("✕")
            return false
        }

        // 1 秒粒度轮询。确认标准是 interfaceHealthy（有 IP 且网关 ping 通）——
        // 不能只看 ifconfig 的 inet：拔插后头几秒僵尸 IP 仍残留，会误判"3 秒恢复"
        for _ in 1...30 {
            Thread.sleep(forTimeInterval: 1)
            if Sys.interfaceHealthy(t.dev) {
                let secs = Int(Date().timeIntervalSince(t0).rounded())
                Sys.log(T(96, t.dev, secs))
                HealthCache.shared.refresh([t.dev])   // 立刻把图标/菜单状态刷成最新

                // ── 内建联网验证：绑定该接口直测外网，结果进通知+图标 ──
                let online = Sys.run("curl -s -m 5 --interface \(t.dev) -o /dev/null -w '%{http_code}' http://captive.apple.com")
                if online == "200" {
                    Notifier.post(T(105, t.display, secs))
                    AppDelegate.shared?.flashResult("✓\(secs)s")
                } else {
                    AppDelegate.shared?.flashResult("⚠︎")
                }
                return true
            }
        }
        Sys.log(T(97, t.dev))
        HealthCache.shared.refresh([t.dev])
        AppDelegate.shared?.flashResult("✕")
        return false
    }
}


// MARK: - 环境探测（用于「恢复后执行命令」的动态勾选项）

/// 一条可勾选的命令。程序添加的行会带 #lteguard 标记，
/// 以便与用户手写的内容严格区分——用户手写的行程序永不删除。
struct PresetCmd {
    let title: String       // 勾选框显示文字
    var command: String     // 实际命令（不含标记）；可变——如提示音预设随选择的声音更新
    let hint: String        // 宽松匹配用的关键字；为空则只做精确匹配
    var tooltip: String = ""
    var pre = false         // true = 写入「发现断联时执行」，false = 「恢复后执行」
}

enum Detect {
    static let mark = "#lteguard"

    /// 扫描用户 LaunchAgent，找出参数中提到指定网络接口的服务。
    /// 这样不论用户用的是 gost、v2ray、clash 还是自写脚本，只要绑定了
    /// 这块网卡就能被发现，无需在代码里硬编码任何工具名。
    static func agentsBound(to dev: String) -> [(label: String, reason: String)] {
        guard !dev.isEmpty else { return [] }
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [(String, String)] = []
        for f in files where f.hasSuffix(".plist") {
            guard let text = try? String(contentsOfFile: dir + "/" + f, encoding: .utf8) else { continue }
            // 跳过本程序自己
            guard !text.contains("com.oceantang.lteguard") else { continue }
            // 参数里出现 interface=en2 / %en2 / 独立的 en2 才算绑定
            let patterns = ["interface=\(dev)", "%\(dev)", "bind=\(dev)", "dev=\(dev)", "-i \(dev)"]
            guard patterns.contains(where: { text.contains($0) }) else { continue }
            let label = (f as NSString).deletingPathExtension
            out.append((label, dev))
        }
        return out
    }

    /// 已挂载的网络卷（SMB / NFS / AFP / WebDAV）
    static func networkVolumes() -> [String] {
        let out = Sys.run("mount | awk '/smbfs|nfs|afpfs|webdav/ {for(i=1;i<=NF;i++) if($i==\"on\"){print $(i+1); break}}'")
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// 正在运行的 VPN 类进程
    static func vpnProcesses() -> [String] {
        var found: [String] = []
        for (proc, name) in [("tailscaled", "Tailscale"), ("wireguard-go", "WireGuard"),
                             ("openvpn", "OpenVPN"), ("com.wireguard", "WireGuard")] {
            if Sys.run("pgrep -x \(proc) >/dev/null 2>&1 && echo y") == "y", !found.contains(name) {
                found.append(name)
            }
        }
        return found
    }

    /// 正在运行的、依赖网络的同步/下载类 App
    static func networkApps() -> [(name: String, bundleID: String)] {
        let known: [String: String] = [
            "com.synology.SynologyDrive": "Synology Drive",
            "com.synology.CloudStation": "Synology Drive",
            "com.getdropbox.dropbox": "Dropbox",
            "com.microsoft.OneDrive": "OneDrive",
            "com.jianguoyun.nutstore": "Nutstore",
            "org.m0k.transmission": "Transmission",
            "org.qbittorrent.qBittorrent": "qBittorrent",
            "com.baidu.BaiduNetdisk": "Baidu Netdisk",
        ]
        var out: [(String, String)] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, let name = known[bid] else { continue }
            if !out.contains(where: { $0.1 == bid }) { out.append((name, bid)) }
        }
        return out
    }
}


// MARK: - 「恢复后执行命令」对话框

/// 勾选项与命令文本的双向实时同步控制器。
///
/// 所有权规则（重要）：程序添加的行末尾带 `#lteguard` 标记，取消勾选时只删
/// 带标记的行；**用户手写的行程序永不触碰**，只能由用户自己删除。因此勾选框
/// 有三种状态：
///   - on     该命令存在且由程序添加（可通过取消勾选移除）
///   - mixed  该命令存在但是用户手写的（勾选框置灰，仅提示不可自动移除）
///   - off    不存在
final class PostCmdEditor: NSObject, NSTextViewDelegate {
    private let preTV: NSTextView    // 「发现断联时执行」
    private let postTV: NSTextView   // 「恢复后执行」
    private var boxes: [(NSButton, PresetCmd)] = []
    private var syncing = false
    /// 勾选前的放行检查（如摄像头权限）。返回 false 则本次不勾；
    /// 检查方可在异步授权成功后再 performClick 该按钮补勾
    var willEnable: ((PresetCmd, NSButton) -> Bool)?

    init(preTV: NSTextView, postTV: NSTextView) {
        self.preTV = preTV
        self.postTV = postTV
        super.init()
        preTV.delegate = self
        postTV.delegate = self
    }

    /// 每个预设归属其中一个文本框，由 preset.pre 决定
    private func tv(for p: PresetCmd) -> NSTextView { p.pre ? preTV : postTV }

    func register(_ button: NSButton, _ preset: PresetCmd) {
        button.target = self
        button.action = #selector(toggled(_:))
        button.allowsMixedState = true
        boxes.append((button, preset))
    }

    var currentPre: String { preTV.string }
    var currentPost: String { postTV.string }

    /// 依据文本内容刷新所有勾选框状态
    func refreshBoxes() {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        for (btn, p) in boxes {
            let lines = tv(for: p).string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var state: NSControl.StateValue = .off
            for raw in lines {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                let tagged = line.hasSuffix(Detect.mark)
                let body = tagged
                    ? String(line.dropLast(Detect.mark.count)).trimmingCharacters(in: .whitespaces)
                    : line
                let hit = (body == p.command) || (!p.hint.isEmpty && line.contains(p.hint))
                guard hit else { continue }
                // 带标记 = 程序所加，可取消；无标记 = 用户手写，仅提示
                state = tagged ? .on : .mixed
                if state == .mixed { break }   // 手写优先，不再被后续行覆盖
            }
            btn.state = state
            btn.isEnabled = (state != .mixed)   // 手写的置灰，避免误以为能点掉
            if state == .mixed && btn.toolTip == nil { btn.toolTip = p.tooltip }
        }
    }

    /// 勾选/取消 → 立即改写文本（所勾即所得）
    ///
    /// 注意：不能依据 sender.state 判断意图——allowsMixedState 会让点击循环变成
    /// off→mixed→on，第一跳落在 .mixed 上，永远走不到 .on。因此这里改为从
    /// 文本内容推导：已有带标记的行→本次点击=取消；没有→本次点击=勾选。
    /// 最终显示状态交给 refreshBoxes() 统一校正。
    @objc private func toggled(_ sender: NSButton) {
        guard let idx = boxes.firstIndex(where: { $0.0 === sender }) else { return }
        let p = boxes[idx].1
        let target = tv(for: p)
        syncing = true
        var lines = target.string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let hasTagged = lines.contains { Self.taggedMatches($0, p) }

        if !hasTagged {
            if let gate = willEnable, !gate(p, sender) {
                syncing = false
                refreshBoxes()   // 权限未就绪：状态回弹为未勾
                return
            }
            let entry = "\(p.command)   \(Detect.mark)"
            if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == entry }) {
                while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
                lines.append(entry)
            }
        } else {
            // 只删带标记的行——用户手写的同名行原样保留
            lines.removeAll { Self.taggedMatches($0, p) }
        }
        target.string = lines.joined(separator: "\n")
        syncing = false
        refreshBoxes()
    }

    /// 该行是否为「程序添加的、属于此预设」的行。
    /// tagged 行是程序自己写的，按 hint 宽松匹配是安全的——
    /// 这让"命令可变"的预设（如换了声音的提示音）也能被正确识别和取消
    private static func taggedMatches(_ raw: String, _ p: PresetCmd) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasSuffix(Detect.mark) else { return false }
        let body = String(line.dropLast(Detect.mark.count)).trimmingCharacters(in: .whitespaces)
        return body == p.command || (!p.hint.isEmpty && body.contains(p.hint))
    }

    /// 预设的命令变了（如用户换了提示音）：更新注册表；若该预设当前已勾选
    /// （文本框里有它的 tagged 行），就地替换为新命令，保持勾选状态
    func updateCommand(for button: NSButton, to newCommand: String) {
        guard let idx = boxes.firstIndex(where: { $0.0 === button }) else { return }
        let old = boxes[idx].1
        boxes[idx].1.command = newCommand
        let p = boxes[idx].1
        let target = tv(for: p)
        var lines = target.string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var replaced = false
        for i in lines.indices where Self.taggedMatches(lines[i], old) {
            lines[i] = "\(newCommand)   \(Detect.mark)"
            replaced = true
        }
        if replaced {
            syncing = true
            target.string = lines.joined(separator: "\n")
            syncing = false
        }
        refreshBoxes()
    }

    /// 用户手动编辑文本 → 勾选框状态跟着变
    func textDidChange(_ notification: Notification) { refreshBoxes() }
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
        if !ok && cfg.targets.contains(where: { !$0.vid.isEmpty }) { d.problems.append(T(39)) }

        // 4 目标配置（逐对象）
        if cfg.targets.isEmpty || cfg.targets.contains(where: { $0.dev.isEmpty || ($0.vid.isEmpty && $0.service.isEmpty) }) {
            d.problems.append(T(40))
        }
        for t in cfg.targets {
            d.lines.append("\(T(34)): \(t.display) / \(t.methodText)")

            // 5 接口是否真实存在
            if Sys.run("ifconfig \(t.dev) >/dev/null 2>&1 && echo y") != "y" {
                d.problems.append(T(41, t.dev))
            }
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
                if msgType == kMsgWillSleep { Sys.log(T(118)) }   // 真正入睡才记，询问阶段不记
                IOAllowPowerChange(me.rootPort, Int(bitPattern: msgArg))
            case kMsgPoweredOn:
                // 唤醒即修，不做预检（详见 Healer 注释）。
                // 不加延迟：「断联时命令」要抢在拔插前跑（如打开网络面板看过程），
                // USB 就绪缓冲由 Healer 在拔插前自行等待
                DispatchQueue.global().async {
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
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSTextFieldDelegate {
    static var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    private let watcher = WakeWatcher()
    /// 在「唤醒后执行命令」对话框存活期间持有，防止其 target/delegate（弱引用）被提前释放
    private var postCmdEditor: PostCmdEditor?
    /// 提示音选择器（对话框存活期间有效）
    private weak var soundPopup: NSPopUpButton?
    private weak var soundCheckbox: NSButton?
    /// 预览播放器。必须持有——局部变量会在函数返回时释放，声音戛然而止
    private var previewPlayer: NSSound?
    /// Webhook 平台选择与地址输入（对话框存活期间有效）
    private weak var webhookCheckbox: NSButton?
    private weak var webhookPopup: NSPopUpButton?
    private weak var webhookField: NSTextField?
    /// 用户主动唤起时，在此时间点之前强制显示图标（便于调整设置）
    private var forceShowUntil: Date?
    private let forceShowSeconds: TimeInterval = 20

    static func main() {
        // 命令行拍照模式：LTEGuard --snap [标签]，拍完打印路径退出（不进 UI）
        if let i = CommandLine.arguments.firstIndex(of: "--snap") {
            let tag = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "manual"
            CameraSnap.runCLI(tag: tag)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // 不在 Dock 显示
        app.run()
    }

    /// 常驻 App 会被系统视为"前台"，前台通知默认静默——
    /// 必须实现此代理，横幅才会始终弹出
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])   // 10.15：.banner/.list 尚不存在
        }
    }

    /// 修复结果短暂显示在图标旁（✓8s / ⚠︎ / ✕），10 秒后复原。
    /// 零权限依赖的兜底反馈——即使通知被系统拦下，用户也能看到结果。
    private var flashUntil: Date?
    func flashResult(_ text: String) {
        DispatchQueue.main.async {
            self.flashUntil = Date().addingTimeInterval(10)
            self.statusItem?.button?.title = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) { self.refreshIcon() }
        }
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
            Sys.log(T(100))
            notify(T(60))
        case .problemOnly:
            forceShowUntil = Date().addingTimeInterval(forceShowSeconds)
            Sys.log(T(101, Int(forceShowSeconds)))
            notify(T(61, Int(forceShowSeconds)))
            // 窗口结束后自动回到「仅异常时显示」
            DispatchQueue.main.asyncAfter(deadline: .now() + forceShowSeconds + 0.5) {
                self.refreshIcon()
            }
        case .always:
            break
        }
        // 可见性交给 refreshIcon 经 setIconVisible 防抖通道统一处理，不再裸写
        refreshIcon()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Sys.migrateLegacyFiles()    // 先迁移旧路径文件，再写第一条日志
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Sys.log(T(117, ver))
        I18n.prepareUserLangDir()   // 启动即释放/刷新翻译模板（等效"安装时释放"，且升级后自动同步）
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestAuth()
        refreshIcon()
        watcher.start()
        // 双保险：IOKit 电源回调之外，再监听一路系统唤醒通知，
        // 任一先到即触发检测（Healer 串行队列 + 冷却期保证不会重复修复）
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
            DispatchQueue.global().async {
                Healer.shared.checkAndHeal(reason: "wake")
            }
        }
        LaunchAtLogin.upgradeIfNeeded()
        // 非后台自启（即用户主动打开）时，确保图标可见，避免隐藏后找不回来
        if !CommandLine.arguments.contains("--background") { unhideIfNeeded() }
        var cfg0 = Config.load()
        if cfg0.migrateV23() { cfg0.save() }
        HealthCache.shared.refresh(cfg0.targets.map(\.dev))
        if !FileManager.default.fileExists(atPath: Config.path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.firstRunGuide() }
        }
        // 补救"App 启动前就睡过"的空档：开机停在登录界面时睡眠→网卡假死→
        // 登录后 App 才启动，唤醒事件早已错过。启动后延迟检测一次，坏了才修、
        // 健康则静默。延迟 8 秒是给登录后网络栈初始化（DHCP 等）留时间，避免误判
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
            Healer.shared.checkAndHeal(reason: "launch")
        }
    }

    /// SF Symbols 仅 macOS 11+ 提供；10.15 返回 nil，调用方走文字/无图标回退
    static func symbolImage(_ name: String, description: String? = nil) -> NSImage? {
        guard #available(macOS 11.0, *) else { return nil }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: description)
        img?.isTemplate = true
        return img
    }

    /// 只在值变化时才写 isVisible——macOS 26 Tahoe 已知高频翻转会触发
    /// 与 ControlCenter 的 visibility 死循环（BetterDisplay/Stats 均中招）
    private func setIconVisible(_ v: Bool) {
        if statusItem.isVisible != v { statusItem.isVisible = v }
    }

    func refreshIcon() {
        guard let btn = statusItem.button else { return }
        let cfg = Config.load()
        let healthy = HealthCache.shared.value(for: cfg.targets.map(\.dev))
        let healing = Healer.shared.healing

        // 显示模式：修复中永远露面 > 强制显示窗口 > 隐藏 / 仅异常时显示
        if healing {
            setIconVisible(true)
        } else if let until = forceShowUntil, Date() < until {
            setIconVisible(true)
        } else {
            forceShowUntil = nil
            switch IconMode.current {
            case .hidden:      setIconVisible(false)
            case .problemOnly: setIconVisible(!healthy)
            case .always:      setIconVisible(true)
            }
        }
        let name = healing ? "arrow.triangle.2.circlepath"
                 : healthy ? "antenna.radiowaves.left.and.right"
                           : "antenna.radiowaves.left.and.right.slash"
        var img = AppDelegate.symbolImage(name, description: "LTE Guard")
        if img == nil {   // 旧系统缺该符号时回退
            img = AppDelegate.symbolImage(healthy ? "wifi" : "wifi.slash", description: "LTE Guard")
        }
        let flashing = flashUntil.map { Date() < $0 } ?? false
        if !flashing { flashUntil = nil }
        if let img = img { btn.image = img; if !flashing { btn.title = "" } }
        else { btn.image = nil; btn.title = flashing ? btn.title : healing ? "LTE…" : healthy ? "LTE" : "LTE!" }
        buildMenu()
    }

    private func item(_ title: String, _ sel: Selector?, state: NSControl.StateValue = .off,
                      symbol: String? = nil, enabled: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.state = state
        it.isEnabled = enabled
        if let s = symbol { it.image = AppDelegate.symbolImage(s) }
        return it
    }

    func buildMenu() {
        let cfg = Config.load()
        let m = NSMenu()
        m.userInterfaceLayoutDirection = I18n.shared.isRTL ? .rightToLeft : .leftToRight
        m.addItem(withTitle: T(1), action: nil, keyEquivalent: "").isEnabled = false

        _ = HealthCache.shared.value(for: cfg.targets.map(\.dev))   // 触发节流刷新
        for t in cfg.targets {
            let h = HealthCache.shared.healthy(t.dev)
            let row = item(T(2, t.display, h ? T(3) : T(4)), nil,
                           symbol: h ? "checkmark.circle" : "exclamationmark.triangle")
            row.toolTip = T(5, t.methodText)
            row.isEnabled = false
            m.addItem(row)
        }
        if cfg.targets.isEmpty {
            let row = item(T(7), nil, symbol: "questionmark.circle")
            row.isEnabled = false
            m.addItem(row)
        }
        m.addItem(.separator())
        m.addItem(item(T(10), #selector(pickTarget), symbol: "target"))
        m.addItem(item(T(11), #selector(healNow), symbol: "wrench.and.screwdriver"))
        m.addItem(item(T(12), #selector(openLog), symbol: "doc.text"))
        m.addItem(item(T(68), #selector(openConfigFolderGated), symbol: "folder"))
        m.addItem(item(T(30), #selector(toggleLaunch),
                       state: LaunchAtLogin.isEnabled ? .on : .off, symbol: "power.circle"))
        m.addItem(item(T(132), #selector(toggleAuthGuard),
                       state: Auth.guardEnabled ? .on : .off, symbol: "touchid"))
        m.addItem(item(T(29), #selector(showDiagnosis), symbol: "stethoscope"))
        m.addItem(item(T(53), #selector(editPostCmdGated), symbol: "terminal"))

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
        m.addItem(item(T(137), #selector(checkUpdate), symbol: "arrow.down.circle"))
        m.addItem(item(T(14), #selector(quitGated), symbol: "power"))
        statusItem.menu = m
    }

    // MARK: 动作

    /// 治愈对象：多选。每个勾选的网卡都被独立守护、独立修复。
    @objc func pickTarget() {
        let services = Sys.networkServices()
        guard !services.isEmpty else { notify(T(23)); return }

        var cfg = Config.load()
        let alert = NSAlert()
        alert.messageText = T(15)
        alert.informativeText = T(108)
        alert.alertStyle = .informational

        let rowH = 24
        let W = 340
        let contentH = services.count * rowH + 4
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: W, height: min(300, contentH)))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: W - 16, height: contentH))
        var boxes: [NSButton] = []
        var y = contentH - rowH
        for (svc, dev) in services {
            let usb = Sys.usbIDs(for: dev) != nil ? "  · USB" : ""
            let cb = NSButton(checkboxWithTitle: "\(svc)  [\(dev)]\(usb)", target: nil, action: nil)
            cb.state = cfg.targets.contains { $0.dev == dev } ? .on : .off
            cb.frame = NSRect(x: 4, y: y, width: W - 24, height: 20)
            doc.addSubview(cb)
            boxes.append(cb)
            y -= rowH
        }
        scroll.documentView = doc
        alert.accessoryView = scroll
        alert.addButton(withTitle: T(17))
        alert.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var picked: [Target] = []
        for (i, (svc, dev)) in services.enumerated() where boxes[i].state == .on {
            var t = Target(dev: dev, service: svc)
            if let (v, p) = Sys.usbIDs(for: dev) { t.vid = v; t.pid = p }
            picked.append(t)
        }
        cfg.targets = picked
        cfg.save()
        let names = picked.map(\.display).joined(separator: ", ")
        Sys.log(T(109, names))
        notify(T(109, names))
        refreshIcon()
    }

    @objc func switchLang(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        I18n.shared.load(preferred: code)
        Sys.log(T(116, code))
        notify(T(24))
        refreshIcon()
    }

    @objc func setIconMode(_ sender: NSMenuItem) {
        guard let mode = IconMode(rawValue: sender.tag) else { return }
        // 隐藏前先当面说清找回方法（事后通知易被错过）：再打开一次 App 图标即恢复
        if mode == .hidden {
            let a = NSAlert()
            a.messageText = T(51)
            a.informativeText = I18n.shared.paragraph(T(52))
            a.alertStyle = .informational
            a.addButton(withTitle: T(17))
            a.addButton(withTitle: T(18))
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        IconMode.current = mode
        refreshIcon()
    }

    /// 恢复后执行命令：GUI 编辑（默认空，未配置不会执行任何东西）
    /// 恢复后执行的命令。多行，每行一条，按顺序执行。
    /// 勾选项分「常用」与「检测到的」两组，后者依据当前环境动态生成。
    @objc func editPostCmd() {
        var cfg = Config.load()
        let a = NSAlert()
        a.messageText = T(53)
        a.informativeText = I18n.shared.paragraph(T(54))

        let W = 480
        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 430))

        func makeCmdBox(_ frame: NSRect, text: String) -> (NSScrollView, NSTextView) {
            let scroll = NSScrollView(frame: frame)
            let tv = NSTextView(frame: scroll.bounds)
            tv.string = text
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isRichText = false
            tv.alignment = .left
            tv.baseWritingDirection = .leftToRight
            tv.isEditable = true
            tv.isSelectable = true
            tv.allowsUndo = true
            tv.autoresizingMask = [.width]
            tv.isVerticallyResizable = true
            tv.textContainer?.widthTracksTextView = true
            scroll.documentView = tv
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            return (scroll, tv)
        }
        func sectionLabel(_ text: String, y: CGFloat) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.font = NSFont.boldSystemFont(ofSize: 11)
            lbl.textColor = .secondaryLabelColor
            lbl.frame = NSRect(x: 0, y: y, width: CGFloat(W), height: 16)
            return lbl
        }

        // ── 上：发现断联时执行（此刻网络不可用）──
        container.addSubview(sectionLabel(T(102), y: 412))
        let (preScroll, preTV) = makeCmdBox(NSRect(x: 0, y: 344, width: W, height: 64), text: cfg.preCmd)
        container.addSubview(preScroll)

        // ── 中：恢复后执行 ──
        container.addSubview(sectionLabel(T(103), y: 320))
        let (postScroll, postTV) = makeCmdBox(NSRect(x: 0, y: 226, width: W, height: 90), text: cfg.postCmd)
        container.addSubview(postScroll)

        let editor = PostCmdEditor(preTV: preTV, postTV: postTV)
        // 拍照预设的权限门：已授权放行；未询问过→系统弹窗，允许后自动补勾；
        // 曾被拒→提示并打开系统设置的摄像头页（系统不会二次弹窗）
        editor.willEnable = { [weak self] p, btn in
            guard p.hint.hasPrefix("--snap") else { return true }
            // 首次开启先签署《门卫室拍照功能使用协议》：展示全文→确认→
            // Touch ID/密码验证即签名→存档 agreement/。签过一次不再打扰
            if !Agreement.hasRecord(kind: "camera-enable") {
                let a = NSAlert()
                a.messageText = T(136)
                let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 240))
                let terms = NSTextView(frame: sv.bounds)
                terms.string = Agreement.cameraTerms
                terms.isEditable = false
                terms.font = NSFont.systemFont(ofSize: 11)
                terms.autoresizingMask = [.width]
                sv.documentView = terms
                sv.hasVerticalScroller = true
                sv.borderType = .bezelBorder
                a.accessoryView = sv
                a.addButton(withTitle: T(17))
                a.addButton(withTitle: T(18))
                guard a.runModal() == .alertFirstButtonReturn else { return false }
                Auth.sign { method in
                    Agreement.record(kind: "camera-enable",
                                     subject: p.pre ? "on-disconnect" : "after-recovery",
                                     terms: Agreement.cameraTerms, method: method)
                    btn.performClick(nil)   // 签署完成，补勾（重新走权限检查）
                }
                return false
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return true
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { ok in
                    if ok { Auth.onMain { btn.performClick(nil) } }
                }
                return false
            default:
                let a = NSAlert()
                a.messageText = T(125)
                a.informativeText = I18n.shared.paragraph(T(129))
                a.addButton(withTitle: T(17))
                a.runModal()
                if #available(macOS 13.0, *) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                } else {
                    Sys.run("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Camera' 2>/dev/null || open -b com.apple.systempreferences", wait: false)
                }
                _ = self
                return false
            }
        }
        self.postCmdEditor = editor   // 持有，否则 target/delegate（弱引用）会被立即释放，勾选与文本回调全部失效

        // ── 勾选区（可滚动）。顶部一条发丝线，让"手写命令区/勾选预设区"的
        //    结构一眼可辨——无形细节的堆叠决定了整体质感 ──
        let rule = NSBox(frame: NSRect(x: 0, y: 220, width: W, height: 1))
        rule.boxType = .separator
        container.addSubview(rule)
        let listScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: W, height: 218))
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .noBorder
        listScroll.drawsBackground = false

        var presets: [(String?, [PresetCmd])] = []

        // 常用（固定）。「打开网络设置」归断联时执行——第一时间打开面板观察修复过程；
        // 「提示恢复」「验证能否上网」已内建为原生通知，不再作为 shell 预设。

        // 系统提示音：动态枚举，初始选中沿用配置里已勾选的那个（没有则 Glass）
        let sounds = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
            .filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(".aiff".count)) }.sorted()
        var initialSound = "Glass"
        for line in cfg.postCmd.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasSuffix(Detect.mark), s.contains("afplay"),
               let r = s.range(of: "/Sounds/"), let dot = s.range(of: ".aiff") {
                initialSound = String(s[r.upperBound..<dot.lowerBound]); break
            }
        }
        if !sounds.contains(initialSound) { initialSound = sounds.first ?? "Glass" }
        func soundCmd(_ name: String) -> String { "afplay /System/Library/Sounds/\(name).aiff" }
        let whInit = AppDelegate.parseWebhook(from: cfg.postCmd)   // webhook 回显（平台，地址）

        let appExe = Bundle.main.bundlePath + "/Contents/MacOS/" +
            (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "LTEGuard")
        let common: [PresetCmd] = [
            PresetCmd(title: T(80),
                      command: Sys.openNetworkPaneCmd,
                      hint: "systempreferences", pre: true),
            PresetCmd(title: T(125),
                      command: "'\(appExe)' --snap wake",
                      hint: "--snap wake", pre: true),
            PresetCmd(title: T(126),
                      command: "'\(appExe)' --snap restored",
                      hint: "--snap restored"),
            PresetCmd(title: T(83), command: soundCmd(initialSound),
                      hint: "afplay"),
            PresetCmd(title: T(92),
                      command: Self.webhookCmd(platform: whInit.0, url: whInit.1),
                      hint: "curl -s"),
        ]
        presets.append((T(84), common))

        // 检测到的（动态）——覆盖所有治愈对象的接口
        var found: [PresetCmd] = []
        var seenAgents = Set<String>()
        for t in cfg.targets {
            for (label, dev) in Detect.agentsBound(to: t.dev) where seenAgents.insert(label).inserted {
                found.append(PresetCmd(
                    title: T(87, label, dev),
                    command: "launchctl kickstart -k gui/$(id -u)/\(label)",
                    hint: label,
                    tooltip: T(91)))
            }
        }
        for vol in Detect.networkVolumes() {
            let name = (vol as NSString).lastPathComponent
            found.append(PresetCmd(title: T(88, name),
                                   command: "open '\(vol)'", hint: vol, tooltip: T(91)))
        }
        for vpn in Detect.vpnProcesses() {
            if vpn == "Tailscale" {
                found.append(PresetCmd(title: T(89, vpn),
                    command: "/Applications/Tailscale.app/Contents/MacOS/Tailscale up 2>/dev/null || true",
                    hint: "Tailscale", tooltip: T(91)))
            }
        }
        for (name, bid) in Detect.networkApps() {
            found.append(PresetCmd(title: T(90, name),
                command: "osascript -e 'quit app id \"\(bid)\"' ; sleep 2 ; open -b \(bid)",
                hint: bid, tooltip: T(91)))
        }
        if !found.isEmpty { presets.append((T(85), found)) }

        // 布局
        var rows: [NSView] = []
        for (header, items) in presets {
            if let h = header {
                let lbl = NSTextField(labelWithString: h)
                lbl.font = NSFont.boldSystemFont(ofSize: 11)
                lbl.textColor = .secondaryLabelColor
                rows.append(lbl)
            }
            for p in items {
                let cb = NSButton(checkboxWithTitle: p.title, target: nil, action: nil)
                cb.toolTip = p.command
                editor.register(cb, p)

                // 提示音/Webhook 行：附加控件稍后直接放进列表视图——
                // 包在 18pt 高的行容器里时，24pt 高的控件会越界，
                // 显示正常但命中测试到不了（macOS 不裁剪显示、但按父边界命中）
                if p.hint == "afplay" { self.soundCheckbox = cb }
                rows.append(cb)
                if p.hint == "curl -s" {
                    self.webhookCheckbox = cb
                    rows.append(NSView())   // 占位一行，稍后放地址输入框
                }
            }
        }
        let rowH = 22
        let contentH = max(180, rows.count * rowH + 8)
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: W - 16, height: contentH))
        var y = contentH - rowH
        for v in rows {
            v.frame = NSRect(x: 4, y: y, width: W - 24, height: 18)
            doc.addSubview(v)
            y -= rowH
        }

        // 提示音行的下拉框与 ▶ 直接挂在列表视图上（与勾选框同一行的右侧）
        if let cb = self.soundCheckbox {
            let popW: CGFloat = 110, playW: CGFloat = 28
            cb.setFrameSize(NSSize(width: CGFloat(W) - 24 - popW - playW - 16, height: 18))
            let rowY = cb.frame.minY
            let pop = NSPopUpButton(frame: NSRect(x: CGFloat(W) - 20 - popW - playW - 6, y: rowY - 3,
                                                  width: popW, height: 24), pullsDown: false)
            pop.addItems(withTitles: sounds)
            pop.selectItem(withTitle: initialSound)
            pop.font = NSFont.systemFont(ofSize: 11)
            pop.target = self
            pop.action = #selector(soundChanged(_:))
            let play = NSButton(frame: NSRect(x: CGFloat(W) - 20 - playW, y: rowY - 3,
                                              width: playW, height: 24))
            play.bezelStyle = .rounded
            play.title = "▶"
            play.target = self
            play.action = #selector(previewSound(_:))
            doc.addSubview(pop)
            doc.addSubview(play)
            self.soundPopup = pop
        }

        // Webhook 行：平台下拉在勾选行右侧，地址输入占其下一行（缩进对齐）
        if let cb = self.webhookCheckbox {
            let popW: CGFloat = 200
            cb.setFrameSize(NSSize(width: CGFloat(W) - 24 - popW - 12, height: 18))
            let pop = NSPopUpButton(frame: NSRect(x: CGFloat(W) - 20 - popW, y: cb.frame.minY - 3,
                                                  width: popW, height: 24), pullsDown: false)
            pop.addItems(withTitles: AppDelegate.webhookPlatforms)
            pop.selectItem(at: whInit.0)
            pop.font = NSFont.systemFont(ofSize: 11)
            pop.target = self
            pop.action = #selector(webhookPlatformChanged(_:))
            let helpW: CGFloat = 26
            let field = NSTextField(frame: NSRect(x: 24, y: cb.frame.minY - CGFloat(rowH) + 1,
                                                  width: CGFloat(W) - 48 - helpW - 6, height: 20))
            field.placeholderString = T(123)
            field.stringValue = whInit.1
            field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            field.delegate = self
            // ? ：打开当前平台的官方申请文档，不让用户自己去搜
            let help = NSButton(frame: NSRect(x: CGFloat(W) - 20 - helpW, y: cb.frame.minY - CGFloat(rowH) - 1,
                                              width: helpW, height: 24))
            help.bezelStyle = .helpButton
            help.title = ""
            help.toolTip = T(124)
            help.target = self
            help.action = #selector(webhookHelp(_:))
            doc.addSubview(pop)
            doc.addSubview(field)
            doc.addSubview(help)
            self.webhookPopup = pop
            self.webhookField = field
        }
        listScroll.documentView = doc
        container.addSubview(listScroll)

        editor.refreshBoxes()

        a.accessoryView = container
        a.addButton(withTitle: T(17))
        a.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        // 文本即最终结果——勾选已实时写入，无需再合并
        func clean(_ s: String) -> String {
            s.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        cfg.preCmd = clean(editor.currentPre)
        cfg.postCmd = clean(editor.currentPost)
        cfg.save()
        notify(T(55))
    }

    // MARK: Webhook 多平台

    /// 平台顺序与 popup 一致；同格式平台已合并。
    /// 计算属性——切换界面语言后平台名跟着变
    static var webhookPlatforms: [String] { [
        T(120),                              // 企业微信 / 钉钉
        T(121),                              // 飞书 (Lark)
        "Slack / Teams / Google Chat",
        "Discord",
        "Telegram",
        "ntfy.sh",
        "IFTTT",
        T(122),                              // 自定义
    ] }

    static func webhookCmd(platform: Int, url: String) -> String {
        let u = url.isEmpty ? "PASTE_YOUR_WEBHOOK_URL" : url
        let msg = "LTE Guard: \(T(82))"
        switch platform {
        case 4:   // Telegram Bot API：地址需含 bot<token>/sendMessage?chat_id=…
            return "curl -s -G '\(u)' --data-urlencode 'text=\(msg)'"
        case 5:   // ntfy.sh：纯文本 POST 到 topic 地址
            return "curl -s -d '\(msg)' '\(u)'"
        default:
            let json: String
            switch platform {
            case 0: json = "{\"msgtype\":\"text\",\"text\":{\"content\":\"\(msg)\"}}"
            case 1: json = "{\"msg_type\":\"text\",\"content\":{\"text\":\"\(msg)\"}}"
            case 3: json = "{\"content\":\"\(msg)\"}"
            case 6: json = "{\"value1\":\"\(msg)\"}"
            default: json = "{\"text\":\"\(msg)\"}"   // Slack/Teams/GChat 与自定义
            }
            return "curl -s -X POST -H 'Content-Type: application/json' -d '\(json)' '\(u)'"
        }
    }

    /// 从配置里程序添加的 webhook 行回显（平台，地址）
    static func parseWebhook(from postCmd: String) -> (Int, String) {
        for raw in postCmd.split(separator: "\n") {
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard s.hasSuffix(Detect.mark), s.hasPrefix("curl -s") else { continue }
            let platform: Int
            if s.contains("msgtype")            { platform = 0 }
            else if s.contains("msg_type")      { platform = 1 }
            else if s.contains("--data-urlencode") { platform = 4 }
            else if s.contains("\"content\":")  { platform = 3 }
            else if s.contains("\"value1\":")   { platform = 6 }
            else if s.contains("\"text\":")     { platform = 2 }
            else                                 { platform = 5 }   // 纯文本 = ntfy
            var url = ""
            if let r = s.range(of: "'http", options: .backwards),
               let end = s.range(of: "'", range: r.upperBound..<s.endIndex) {
                url = String(s[s.index(after: r.lowerBound)..<end.lowerBound])
            }
            return (platform, url)
        }
        return (0, "")
    }

    /// 各平台「怎么申请 webhook 地址」的官方文档（官方优先；合并项每家一篇）
    static func webhookDocURLs(platform: Int) -> [String] {
        switch platform {
        case 0: return ["https://developer.work.weixin.qq.com/document/path/91770",
                        "https://open.dingtalk.com/document/robots/custom-robot-access"]
        case 1: return ["https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot"]
        case 2: return ["https://api.slack.com/messaging/webhooks",
                        "https://learn.microsoft.com/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook",
                        "https://developers.google.com/workspace/chat/quickstart/webhooks"]
        case 3: return ["https://support.discord.com/hc/articles/228383668"]
        case 4: return ["https://core.telegram.org/bots#how-do-i-create-a-bot"]
        case 5: return ["https://docs.ntfy.sh/"]
        case 6: return ["https://ifttt.com/maker_webhooks"]
        default: return ["https://github.com/oceantangqoit/Mac-lte-guard#readme"]
        }
    }

    /// ? 按钮：打开当前所选平台的官方申请文档
    @objc private func webhookHelp(_ sender: NSButton) {
        let platform = webhookPopup?.indexOfSelectedItem ?? 0
        for u in AppDelegate.webhookDocURLs(platform: platform) {
            if let url = URL(string: u) { NSWorkspace.shared.open(url) }
        }
    }

    /// 平台或地址变化 → 重新生成命令；若已勾选，文本框中的行就地替换
    private func webhookUpdate() {
        guard let cb = webhookCheckbox else { return }
        let platform = webhookPopup?.indexOfSelectedItem ?? 0
        let url = webhookField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let cmd = AppDelegate.webhookCmd(platform: platform, url: url)
        cb.toolTip = cmd
        postCmdEditor?.updateCommand(for: cb, to: cmd)
    }

    @objc private func webhookPlatformChanged(_ sender: NSPopUpButton) { webhookUpdate() }

    /// URL 输入实时联动（NSTextFieldDelegate）
    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === webhookField { webhookUpdate() }
    }

    /// 用户换了提示音：更新预设命令；若已勾选，文本框里的命令行就地替换
    @objc private func soundChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem, let cb = soundCheckbox else { return }
        let cmd = "afplay /System/Library/Sounds/\(name).aiff"
        cb.toolTip = cmd
        postCmdEditor?.updateCommand(for: cb, to: cmd)
    }

    /// 预览当前选中的提示音。用 NSSound 而非 afplay 子进程——
    /// 模态对话框期间照常工作，也不依赖 shell
    @objc private func previewSound(_ sender: NSButton) {
        guard let name = soundPopup?.titleOfSelectedItem else { Sys.log("preview: no popup"); return }
        previewPlayer?.stop()
        previewPlayer = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
        let ok = previewPlayer?.play() ?? false
        Sys.log("preview \(name): \(ok ? "playing" : "FAILED")")
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
        // 数据风险确认属签约：验证即签名，存档 agreement/ 后再执行
        Auth.sign { [weak self] method in
            Agreement.record(kind: "usb-reset", subject: "\(name) \(vid):\(pid)",
                             terms: T(77, name) + "\n\n" + T(78), method: method)
            DispatchQueue.global(qos: .userInitiated).async {
                Sys.log(T(99, name, "\(vid):\(pid)"))
                let out = Sys.run("'\(Sys.usbresetPath)' \(vid) \(pid) 2>&1")
                Sys.log(out.contains("OK") ? T(112, "\(vid):\(pid)") : T(113, out))
                Auth.onMain { self?.notify(T(79, name)) }
            }
        }
    }

    @objc func toggleLaunch() {
        if LaunchAtLogin.isEnabled {
            // 关闭自启会让守护在重启后失效——敏感方向，受门禁
            Auth.gate { [weak self] in
                LaunchAtLogin.set(false)
                self?.notify(T(44))
                self?.refreshIcon()
            }
        } else {
            LaunchAtLogin.set(true)
            notify(T(43))
            refreshIcon()
        }
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

        // 门卫室：首次引导就把摄像头权限配置好（用户拒绝也不影响其他功能，
        // 之后勾选拍照预设时会再引导）
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            let c = NSAlert()
            c.messageText = T(125)
            c.informativeText = I18n.shared.paragraph(T(128))
            c.addButton(withTitle: T(17))
            c.addButton(withTitle: T(18))
            if c.runModal() == .alertFirstButtonReturn {
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            }
        }
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
            // 责任移交属签约：验证即签名，存档 agreement/ 后再导出
            Auth.sign { [weak self] method in
                Agreement.record(kind: "language-handover", subject: code,
                                 terms: T(73) + "\n\n" + T(74), method: method)
                self?.exportLangFile(code: code)
            }
            return
        }
        // 已导出过：直接打开自己的副本
        if fm.fileExists(atPath: dst) {
            NSWorkspace.shared.open(URL(fileURLWithPath: dst))
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: I18n.userLangDir))
        }
    }

    /// 签署完成后的实际导出（署名替换 + 责任声明头）
    private func exportLangFile(code: String) {
        let fm = FileManager.default
        let dst = I18n.userLangDir + "/\(code).ini"
        guard let r = Bundle.main.resourcePath, !fm.fileExists(atPath: dst) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: I18n.userLangDir)); return
        }
        do {
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

    /// 一键打开配置文件夹：配置文件、日志与语言目录都真实存放于此
    @objc func openConfigFolder() {
        let fm = FileManager.default
        I18n.prepareUserLangDir()   // 顺带建好 lang/ 与模板
        for target in [Config.path, Sys.logPath] where !fm.fileExists(atPath: target) {
            try? "".write(toFile: target, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: I18n.appSupportDir))
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

    /// 检查新版：仅在用户点击时联网查询 GitHub 最新 Release（无任何后台检查，
    /// 守住"零后台联网"的承诺）。有新版→提示并跳转下载页；已最新/失败→通知
    @objc func checkUpdate() {
        notify(T(22))
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Sys.run("curl -s -m 10 https://api.github.com/repos/oceantangqoit/Mac-lte-guard/releases/latest")
            var latest = ""
            if let d = out.data(using: .utf8),
               let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
               let tag = j["tag_name"] as? String {
                latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            }
            let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            Auth.onMain { [weak self] in
                guard let self else { return }
                guard !latest.isEmpty else { self.notify(T(140)); return }
                if Self.versionNewer(latest, than: cur) {
                    let a = NSAlert()
                    a.messageText = T(138, latest, cur)
                    a.addButton(withTitle: T(17))
                    a.addButton(withTitle: T(18))
                    NSApp.activate(ignoringOtherApps: true)
                    if a.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "https://github.com/oceantangqoit/Mac-lte-guard/releases/latest")!)
                    }
                } else {
                    self.notify(T(139))
                }
            }
        }
    }

    static func versionNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // ── 敏感操作门禁（受「敏感操作需要验证」开关控制）──
    @objc func editPostCmdGated()    { Auth.gate { [weak self] in self?.editPostCmd() } }
    @objc func quitGated()           { Auth.gate { NSApp.terminate(nil) } }
    @objc func openConfigFolderGated() { Auth.gate { [weak self] in self?.openConfigFolder() } }

    /// 开关本身也要防绕过：开启随手，关闭需验证
    @objc func toggleAuthGuard() {
        if Auth.guardEnabled {
            Auth.require { [weak self] in
                Auth.guardEnabled = false
                self?.notify(T(134))
                self?.refreshIcon()
            }
        } else {
            Auth.guardEnabled = true
            notify(T(133))
            refreshIcon()
        }
    }

    private func notify(_ msg: String) {
        Notifier.post(msg)
    }
}
