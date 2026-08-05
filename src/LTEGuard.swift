// LTE Guard — 菜单栏常驻 App
// 睡眠策略切换 + 治愈对象选择 + 状态查看 + 唤醒自愈守护
import Cocoa
import IOKit
import IOKit.pwr_mgt
import IOKit.usb
import UserNotifications
import LocalAuthentication
import CommonCrypto

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
    static func gate(_ op: String = "", then action: @escaping () -> Void) {
        let go = {
            if !op.isEmpty { OpsNotify.report(op) }
            action()
        }
        guardEnabled ? require(then: go) : go()
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

// MARK: - 内建 Webhook 发送器
// 睡眠通报、签约通报等场景来不及/不适合走 shell 预设，由程序直接发送。
// 每次发送记录成败；失败入待补队列（outbox），网络恢复后自动补发并注明原时间。
enum WebhookSender {
    static var outboxPath: String { I18n.appSupportDir + "/webhook-outbox.tsv" }

    /// 用户配置的 webhook（平台，地址）；未配置返回 nil
    static func configured() -> (Int, String)? {
        let c = Config.load()
        return c.whURL.isEmpty ? nil : (c.whPlatform, c.whURL)
    }

    private static func request(platform: Int, url: String, text: String) -> URLRequest? {
        let enc = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
        let isGET = platform == 4 || platform == 7   // Telegram / WhatsApp(CallMeBot)
        guard let u = URL(string: isGET
            ? url + (url.contains("?") ? "&" : "?") + "text=" + enc
            : url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 3)
        req.httpMethod = isGET ? "GET" : "POST"
        switch platform {
        case 4, 7: break                                  // GET，参数已在 URL
        case 5:  req.httpBody = text.data(using: .utf8)   // ntfy 纯文本
        case 9:  req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                 req.httpBody = "title=LTE%20Guard&desp=\(enc)".data(using: .utf8)   // Server酱
        case 11: req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                 req.httpBody = "message=\(enc)".data(using: .utf8)                  // Pushover
        default:
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any]
            switch platform {
            case 0:  body = ["msgtype": "text", "text": ["content": text]]
            case 1:  body = ["msg_type": "text", "content": ["text": text]]
            case 3:  body = ["content": text]
            case 6:  body = ["value1": text]
            case 8:  body = ["title": "LTE Guard", "body": text]                     // Bark
            case 10: body = ["title": "LTE Guard", "message": text, "priority": 5]   // Gotify
            case 12: body = ["msgtype": "m.text", "body": text]                      // Matrix
            default: body = ["text": text]
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    /// 发送文本。失败且 queueOnFail 时写入待补队列。sync=true 同步等待（≤timeout）
    static func send(_ text: String, sync: Bool = false, queueOnFail: Bool = true) {
        guard let (p, u) = configured(), let req = request(platform: p, url: u, text: text) else { return }
        let sem = sync ? DispatchSemaphore(value: 0) : nil
        URLSession.shared.dataTask(with: req) { _, resp, err in
            let ok = err == nil && (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
            if ok {
                Sys.log(T(152))
            } else {
                Sys.log(T(153, err?.localizedDescription ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"))
                if queueOnFail { enqueue(text) }
            }
            sem?.signal()
        }.resume()
        _ = sem?.wait(timeout: .now() + 3.5)
    }

    /// 待补队列的读写锁。补发与入队可能同时发生（唤醒那一刻尤其如此），
    /// 两路各写各的会把行写串
    private static let outboxLock = NSLock()

    /// 写入待补队列（时间\t消息），供网络恢复后补发
    static func enqueue(_ text: String) {
        outboxLock.lock(); defer { outboxLock.unlock() }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date()))\t\(text.replacingOccurrences(of: "\n", with: " "))\n"
        if let h = FileHandle(forWritingAtPath: outboxPath) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            try? line.write(toFile: outboxPath, atomically: true, encoding: .utf8)
        }
    }

    /// 发送文本＋照片。照片为空或平台不支持图文时退化为纯文本。
    /// 全程 URLSession，不经 shell——成败可判、可补发。
    static func sendRich(_ text: String, images: [String]) {
        guard let (p, u) = configured() else { return }
        let imgs = images.filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
        guard !imgs.isEmpty, AppDelegate.webhookRichCapable.contains(p) else { send(text); return }
        switch p {
        case 0:   // 企业微信：文本一条 + 每张 base64 图片一条（协议不支持真混排）
            send(text)
            for f in imgs {
                guard let d = FileManager.default.contents(atPath: f) else { continue }
                postJSON(u, ["msgtype": "image",
                             "image": ["base64": d.base64EncodedString(), "md5": md5Hex(d)]])
            }
        case 3:   // Discord：文字与全部附件同一条（真混排）
            postMultipart(u, fields: ["payload_json": "{\"content\":\"\(esc(text))\"}"],
                          files: imgs, prefix: "file")
        case 4:   // Telegram：单张 sendPhoto 带 caption；多张走相册
            if imgs.count == 1 {
                postMultipart(u.replacingOccurrences(of: "sendMessage", with: "sendPhoto"),
                              fields: ["caption": text], files: imgs, prefix: "photo", single: true)
            } else {
                var media: [[String: Any]] = []
                for i in imgs.indices {
                    var m: [String: Any] = ["type": "photo", "media": "attach://p\(i)"]
                    if i == 0 { m["caption"] = text }
                    media.append(m)
                }
                let js = (try? JSONSerialization.data(withJSONObject: media))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                postMultipart(u.replacingOccurrences(of: "sendMessage", with: "sendMediaGroup"),
                              fields: ["media": js], files: imgs, prefix: "p", zeroBased: true)
            }
        default:  // ntfy：图片 PUT 时把文字放进 X-Message，一条通知即图文
            for (i, f) in imgs.enumerated() {
                guard let d = FileManager.default.contents(atPath: f),
                      let url = URL(string: u) else { continue }
                var req = URLRequest(url: url, timeoutInterval: 20)
                req.httpMethod = "PUT"
                req.setValue("LTE Guard", forHTTPHeaderField: "X-Title")
                if i == 0 { req.setValue(text, forHTTPHeaderField: "X-Message") }
                req.httpBody = d
                fire(req)
            }
        }
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 企业微信图片消息要求附 md5（仅作协议校验用）
    private static func md5Hex(_ d: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        d.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(d.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func postJSON(_ u: String, _ body: [String: Any]) {
        guard let url = URL(string: u) else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        fire(req)
    }

    private static func postMultipart(_ u: String, fields: [String: String], files: [String],
                                      prefix: String, zeroBased: Bool = false, single: Bool = false) {
        guard let url = URL(string: u) else { return }
        let boundary = "LTEGuard" + UUID().uuidString
        var body = Data()
        func put(_ t: String) { body.append(t.data(using: .utf8)!) }
        for (k, v) in fields {
            put("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        for (i, f) in files.enumerated() {
            guard let d = FileManager.default.contents(atPath: f) else { continue }
            let name = single ? prefix : "\(prefix)\(zeroBased ? i : i + 1)"
            put("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\((f as NSString).lastPathComponent)\"\r\nContent-Type: image/jpeg\r\n\r\n")
            body.append(d)
            put("\r\n")
        }
        put("--\(boundary)--\r\n")
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        fire(req)
    }

    private static func fire(_ req: URLRequest) {
        URLSession.shared.dataTask(with: req) { _, resp, err in
            let ok = err == nil && (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
            Sys.log(ok ? T(152) : T(153, err?.localizedDescription ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"))
        }.resume()
    }

    /// 网络恢复后补发队列中的消息，逐条注明原发送时间；仍失败的保留待下次
    static func flushOutbox() {
        // 先原子改名，再读那个改好名的。若照旧「读全文→删文件」，
        // 这中间新入队的消息会被一并删掉——补发反倒成了丢消息。
        // 改名之后，新消息进的是新文件，两边互不相干
        let stash = outboxPath + ".flushing"
        outboxLock.lock()
        let fm = FileManager.default
        guard fm.fileExists(atPath: outboxPath) else { outboxLock.unlock(); return }
        try? fm.removeItem(atPath: stash)
        try? fm.moveItem(atPath: outboxPath, toPath: stash)
        outboxLock.unlock()
        defer { try? fm.removeItem(atPath: stash) }
        guard let text = try? String(contentsOfFile: stash, encoding: .utf8),
              !text.isEmpty else { return }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            send("[\(T(151, parts[0]))] \(parts[1])", sync: false, queueOnFail: true)
        }
    }
}

// MARK: - 敏感操作通报
// 用户在「Mac 唤醒后执行命令…」里勾选哪些操作要通报，操作发生时（验证通过后）
// 立即发 webhook。人在异地也能第一时间知道有人动了守护设置。
enum OpsNotify {
    /// 操作代号 → 界面名称（复用既有菜单文案键，无需新翻译）
    static var catalog: [(String, String)] {
        [("editcmd", T(53)), ("notify", T(184)), ("target", T(10)), ("heal", T(11)), ("log", T(12)),
         ("config", T(68)), ("launch", T(30)), ("usb", T(75)),
         ("update", T(190)), ("quit", T(14))]
    }

    static func name(_ op: String) -> String {
        catalog.first { $0.0 == op }?.1 ?? op
    }

    /// 已勾选才发；带操作名、机器名、使用者与时间
    /// detail 是「改成了什么」。通报一个动作而不说结果，收到的人还得自己去查，
    /// 值守消息就该一眼看明白
    static func report(_ op: String, _ detail: String = "") {
        guard Config.load().notifyOps.contains(op) else { return }
        let who = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let host = Host.current().localizedName ?? ""
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let subject = detail.isEmpty ? name(op) : name(op) + "：" + detail
        let text = T(177, subject, "\(who)@\(host) · \(f.string(from: Date()))")
        Sys.log(text)
        WebhookSender.send(text)
    }
}

// MARK: - 更新器
// 下载落在配置目录 updates/ 子目录，用户可随时查看/删除。
// GitHub 直连不通时自动走加速镜像；每日静默预下载，装不装由用户点头。
enum Updater {
    static var dir: String { I18n.appSupportDir + "/updates" }
    static let repo = "oceantangqoit/Mac-lte-guard"

    /// 加速镜像前缀（直连失败后依次尝试）——国内常见的 GitHub 代理
    static let mirrors = ["https://ghfast.top/", "https://gh-proxy.com/", "https://ghproxy.net/"]

    static var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdate") }
    }
    private static var lastCheck: Date {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }
    /// 已下载待安装的版本（菜单据此显示「安装更新 x.y.z」）
    static var readyVersion: String? {
        guard let fs = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return fs.compactMap { f -> String? in
            guard f.hasPrefix("LTEGuard-"), f.hasSuffix(".dmg") || f.hasSuffix(".pkg") else { return nil }
            let v = String(f.dropFirst("LTEGuard-".count).dropLast(4))
            return AppDelegate.versionNewer(v, than: cur) ? v : nil
        }.sorted { AppDelegate.versionNewer($0, than: $1) }.first
    }

    /// 查询最新版（直连 → 镜像）。返回 (版本, dmg 地址, pkg 地址)
    /// 官方公布的 pkg 校验和（sha256），仅当 API 是直连拿到时才算数。
    /// 大文件可以走镜像加速，但校验和必须来自官方——拿镜像给的哈希去校验
    /// 镜像给的包，等于让嫌疑人自己作证
    private(set) static var officialDigest = ""

    static func fetchLatest() -> (String, String, String)? {
        var urls = ["https://api.github.com/repos/\(repo)/releases/latest"]
        urls += mirrors.map { $0 + "https://api.github.com/repos/\(repo)/releases/latest" }
        for (idx, u) in urls.enumerated() {
            let out = Sys.run("curl -sL -m 12 '\(u)'")
            guard let d = out.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let tag = j["tag_name"] as? String else { continue }
            var dmg = "", pkg = "", digest = ""
            for a in (j["assets"] as? [[String: Any]]) ?? [] {
                guard let n = a["name"] as? String,
                      let du = a["browser_download_url"] as? String else { continue }
                if n.hasSuffix(".dmg") { dmg = du }
                else if n.hasSuffix(".pkg"), !n.hasPrefix("LTEGuard.pkg") {
                    pkg = du
                    // 只认直连（idx == 0）拿回来的哈希
                    if idx == 0, let dg = a["digest"] as? String, dg.hasPrefix("sha256:") {
                        digest = String(dg.dropFirst("sha256:".count))
                    }
                }
            }
            officialDigest = digest
            return (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, dmg, pkg)
        }
        return nil
    }

    /// 包与官方校验和是否相符。相符则来路不重要——镜像也好、代理也好，
    /// 内容既然与官方发布的一字不差，就不是它们能改的了
    static func digestMatches(_ path: String) -> Bool {
        guard !officialDigest.isEmpty else { return false }
        let out = Sys.run("shasum -a 256 '\(path)' 2>/dev/null | awk '{print $1}'")
        let got = out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !got.isEmpty && got == officialDigest.lowercased()
    }

    /// 把各版本的更新概要写进 updates/commits.txt（倒序，最新在最上）——
    /// 内容取自各 Release 的说明（CI 自动汇总的中文 commit 标题）
    static func writeChangelog() {
        var urls = ["https://api.github.com/repos/\(repo)/releases?per_page=30"]
        urls += mirrors.map { $0 + "https://api.github.com/repos/\(repo)/releases?per_page=30" }
        for u in urls {
            let out = Sys.run("curl -sL -m 15 '\(u)'")
            guard let d = out.data(using: .utf8),
                  let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]],
                  !arr.isEmpty else { continue }
            var text = "LTE Guard — \(T(172))\n\(String(repeating: "=", count: 60))\n\n"
            for r in arr {
                let tag = r["tag_name"] as? String ?? "?"
                let date = String((r["published_at"] as? String ?? "").prefix(10))
                var body = (r["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // 去掉自动生成的空壳（只有 compare 链接的说明），换成如实告知
                let stripped = body
                    .replacingOccurrences(of: "**Full Changelog**:", with: "")
                    .replacingOccurrences(of: "Full changelog:", with: "")
                    .split(separator: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("http")
                           && !$0.trimmingCharacters(in: .whitespaces).isEmpty
                           && $0.trimmingCharacters(in: .whitespaces) != "---" }
                if stripped.isEmpty { body = T(183) }
                text += "── \(tag)  \(date) \(String(repeating: "─", count: max(0, 40 - tag.count)))\n"
                text += body + "\n\n"
            }
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? text.write(toFile: dir + "/commits.txt", atomically: true, encoding: .utf8)
            return
        }
    }

    /// 上一份下载是否来自镜像。镜像是第三方代理，能返回任意内容；
    /// 包又未签名未公证，装之前没有任何东西能证明它是我们发的。
    /// 官方直连至少有 GitHub 的 TLS 与账号体系兜着，镜像什么都没有
    private(set) static var lastSourceWasMirror = false

    /// 同一时刻只许一路下载。30 秒的节拍遇上慢速网络，上一轮还没下完
    /// 下一轮就来了，两个 curl 写同一个 .part，写出来的是内容交错的坏包。
    /// 拿到闸才干活，拿不到就让路——让路不算失败，下一轮自然会来
    private static let gate = NSLock()
    private static var busy = false
    static func tryEnter() -> Bool {
        gate.lock(); defer { gate.unlock() }
        if busy { return false }
        busy = true; return true
    }
    static func leave() { gate.lock(); busy = false; gate.unlock() }

    /// 下载到 updates/（直连 → 镜像）。成功返回本地路径
    @discardableResult
    static func download(_ url: String, name: String) -> String? {
        guard !url.isEmpty else { return nil }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dest = dir + "/" + name
        if FileManager.default.fileExists(atPath: dest) { return dest }   // 已下过就不重下
        for (idx, u) in ([url] + mirrors.map({ $0 + url })).enumerated() {
            let tmp = dest + ".\(getpid()).part"
            let out = Sys.run("curl -sL -m 600 -o '\(tmp)' '\(u)' && echo __OK__")
            let size = (try? FileManager.default.attributesOfItem(atPath: tmp))?[.size] as? Int ?? 0
            if out.contains("__OK__"), size > 200_000 {   // 安装包至少 200KB，防止把错误页当成包
                try? FileManager.default.moveItem(atPath: tmp, toPath: dest)
                // 记下这一份是从哪儿来的。镜像是第三方代理，能返回任意内容，
                // 而我们没有签名可校验——来路必须留痕，且不能无人过目就装
                lastSourceWasMirror = idx > 0
                Sys.log(T(160, name))
                writeChangelog()   // 顺手更新各版本概要
                return dest
            }
            try? FileManager.default.removeItem(atPath: tmp)
        }
        Sys.log(T(162, name))
        return nil
    }

    /// 前台：下载并安装（用户点了「立即下载并更新」）
    static func downloadAndInstall(version: String, dmg: String, pkg: String) {
        Notifier.post(T(160, version))
        guard tryEnter() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            defer { leave() }
            // 一律取 pkg。install() 只认 pkg（靠 pkgutil 自解包才免提权），
            // 这里若还下 dmg，拿到手也只能失败回退——2.43 改过静默那条路，
            // 这条「用户手动点下载」的路当时漏了
            _ = dmg
            let path = download(pkg, name: "LTEGuard-\(version).pkg")
            Auth.onMain {
                guard let path = path else { Notifier.post(T(162, version)); return }
                install(path: path, version: version)
            }
        }
    }

    /// 安装已下载的包：dmg 直接替换并重启；pkg 交系统安装器（会要密码）
    /// silent = true 时不弹任何框，直接装。静默更新走的就是这条路。
    ///
    /// 一律用 pkg，不再走 dmg。要 pkg 无人值守，关键是别去调 `installer`
    /// ——要管理员密码的是那个命令，不是 pkg 这个格式。pkgutil 能以普通
    /// 用户身份把 pkg 解开，App 属主既已是当前用户，自己换掉自己即可。
    static func install(path: String, version: String, silent: Bool = false) {
        // 程序即将被替换、进程随后重启——值守工具该在此刻留痕。
        // 此时刚下载完，网络必通；同步发送，确保消息先于重启送达。
        if Config.load().notifyOps.contains("update") {
            let who = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
            let host = Host.current().localizedName ?? ""
            let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            WebhookSender.send(T(191, cur, version, "\(who)@\(host)"), sync: true)
        }

        Sys.log(T(166, version))

        // 没勾「自动安装」，就交给系统安装器一步一步来：它自带引导，
        // 也让人看清在装什么。勾了才走下面的自解包，一声不吭直接换掉
        guard silent else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }

        // 记下这次要装的版本：下次启动若版本没变，说明这轮没装成，
        // 由启动处计数、连败两次即拉黑，免得每 30 秒杀自己一次的死循环。
        // **只有静默路径才记**——交给系统安装器时，用户在安装器里点取消
        // 是他的自由，不是失败，更不该因此把这个版本拉黑
        UserDefaults.standard.set(version, forKey: "installAttempt")
        UserDefaults.standard.synchronize()

        let app = Bundle.main.bundlePath
        let uid = String(getuid())
        let script = """
        set -u
        APP='\(app)'
        PKG='\(path)'
        LABEL=com.oceantang.lteguard
        PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
        EXP=$(mktemp -d)

        cleanup() {
            rm -rf "$EXP" 2>/dev/null
            # 无论成败都把服务挂回去，否则守护就断了
            [ -f "$PLIST" ] && launchctl bootstrap "gui/\(uid)" "$PLIST" 2>/dev/null
        }
        # 装不成时，退回让系统安装器接手——那条路要密码，但至少装得上
        fallback() { cleanup; open '\(path)' 2>/dev/null; exit 1; }

        # 先解包再动手。解不出来就什么都不碰，用户的 App 一直好端端的
        pkgutil --expand-full "$PKG" "$EXP/x" >/dev/null 2>&1 || fallback
        NEW=$(find "$EXP/x" -maxdepth 5 -name LTEGuard.app -type d | head -1)
        [ -n "$NEW" ] && [ -d "$NEW/Contents/MacOS" ] || fallback

        # 服务先卸下来，否则 pkill 之后 launchd 立刻把旧版拉起来，
        # 正撞上替换过程——上一版的死循环就有它一份
        launchctl bootout "gui/\(uid)/$LABEL" 2>/dev/null
        # 开了「永不退出」时 KeepAlive 是无条件的：服务没卸干净就 pkill，
        # launchd 会立刻把旧版拉起来，正撞上替换过程。所以必须确认真卸掉了；
        # 卸不掉就别硬来，退给系统安装器——它自己会处理运行中的实例
        for i in 1 2 3 4 5 6 7 8; do
            launchctl print "gui/\(uid)/$LABEL" >/dev/null 2>&1 || break
            sleep 0.4
        done
        if launchctl print "gui/\(uid)/$LABEL" >/dev/null 2>&1; then fallback; fi
        for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x LTEGuard >/dev/null || break; sleep 0.5; done
        pkill -x LTEGuard 2>/dev/null
        sleep 1
        # 杀完再确认一次没被拉起来——这是 KeepAlive 唯一可能钻空子的地方
        pgrep -x LTEGuard >/dev/null && fallback

        # 原子替换：旧的先挪开，新的到位后才删旧的。
        # 「先删后拷」中途出错，用户就没有 App 了——这一步不许有这种可能
        rm -rf "$APP.old" 2>/dev/null
        if mv "$APP" "$APP.old" 2>/dev/null; then
            if mv "$NEW" "$APP" 2>/dev/null; then
                rm -rf "$APP.old" 2>/dev/null
            else
                mv "$APP.old" "$APP" 2>/dev/null   # 换不上就原样退回
                fallback
            fi
        else
            fallback
        fi

        cleanup
        sleep 1
        # 上面 cleanup 里的 launchctl bootstrap 带 RunAtLoad，新版已经被拉起来了。
        # 这里再 open 一次就是同时点两把火——两个菜单栏图标正是这么来的。
        # 只有在压根没有 LaunchAgent 的情况下（没用 pkg 装过）才需要自己开
        [ -f "$PLIST" ] || open -a "$APP" 2>/dev/null &
        """
        // 脚本走临时文件，不经 sh -c 的引号：套一层双引号的话，脚本里的
        // $EXP、$(mktemp -d) 会被外层 shell 抢先展开——上一版正是栽在这里，
        // 变量成了空串，命令必败，而进程已经被 pkill 掉了
        let sf = NSTemporaryDirectory() + "lteguard-update-\(version).sh"
        guard (try? script.write(toFile: sf, atomically: true, encoding: .utf8)) != nil else {
            Sys.log(T(162, sf)); return
        }
        Sys.run("nohup sh '\(sf)' >/dev/null 2>&1 &", wait: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
    }

    /// 安装 updates/ 里已下好的最新一版（历史安装包一律保留，不清理）
    static func installReady() {
        guard let v = readyVersion else { return }
        for ext in ["dmg", "pkg"] {
            let p = dir + "/LTEGuard-\(v).\(ext)"
            if FileManager.default.fileExists(atPath: p) { install(path: p, version: v); return }
        }
    }

    /// 静默更新：按用户设定的间隔查询，查到新版本直接装好，不弹任何框。
    /// 「无感」不等于「无痕」——装完写日志、按需发 webhook，事后查得到。
    static func silentCheckIfDue() {
        let cfg = Config.load()
        guard cfg.updateInterval > 0 else { return }        // 0 = 从不
        // 留 2 秒容差：定时器在第 30.0 秒触发时，这里算出来往往是 29.99x，
        // 严格比大小会让这一轮白白跳过——设定的 30 秒于是变成了 60 秒
        guard Date().timeIntervalSince(lastSilentCheck)
                > Double(cfg.updateInterval) - 2 else { return }
        guard tryEnter() else { return }        // 上一轮还在跑，让路
        lastSilentCheck = Date()
        DispatchQueue.global(qos: .background).async {
            defer { leave() }
            guard let (latest, dmg, pkg) = fetchLatest() else { return }   // 连不上就静默作罢
            writeChangelog()
            let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard AppDelegate.versionNewer(latest, than: cur) else { return }
            guard !isBlacklisted(latest) else { return }   // 连败两次的版本不再自动重试
            _ = dmg   // 更新只认 pkg：自解包即可无人值守，不必再走磁盘映像
            guard let file = download(pkg, name: "LTEGuard-\(latest).pkg") else { return }
            // 记下这次是从哪个版本升上来的，供升级后的权限提示说明来龙去脉
            UserDefaults.standard.set(cur, forKey: "lastUpgradeFrom")
            guard cfg.silentInstall else {
                // 只下不装：留一条「已就绪」，由用户自己决定何时装
                Sys.log(T(167, latest))
                Notifier.post(T(167, latest))
                Auth.onMain { AppDelegate.shared?.refreshIcon() }
                return
            }
            // 日志写在真装之前会撒谎：装没装成还两说。这里只说「开始装」，
            // 「装成了」由新版本启动时自己那条启动日志作证
            // 准入条件：要么与官方校验和相符（来路就不重要了——内容既然与
            // 官方发布的一字不差，就不是代理能改的），要么本来就是直连拿的。
            // 两样都没有时不无人值守安装：那等于「下载什么就执行什么，
            // 无人过目」，这个信任给不出去
            guard !(lastSourceWasMirror && !digestMatches(file)) else {
                Sys.log(T(229, latest))
                Notifier.post(T(229, latest))
                Auth.onMain { AppDelegate.shared?.refreshIcon() }
                return
            }
            Sys.log(T(208, cur, latest))
            OpsNotify.report("update")
            install(path: file, version: latest, silent: true)   // 一声不吭装好，装完自重启
        }
    }

    /// 间隔档位：秒数与对应文案键。0 为「从不」，排在首位
    static let intervalChoices: [(Int, Int)] = [
        (0, 199), (30, 200), (300, 201), (1_800, 202), (3_600, 203),
        (21_600, 204), (86_400, 205), (604_800, 206), (2_592_000, 207),
    ]

    /// 装失败的版本：连败两次即拉黑，不再自动重试。
    /// 上一版的教训——安装失败却每 30 秒重来一次，等于每 30 秒杀自己一次
    /// 清掉隔夜的半截下载。下载中断会留下 .part，而下一轮用的是新名字，
    /// 旧的再无人问津，只是白占地方——两天前的就该扫走
    static func sweepStaleParts() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        let cutoff = Date().addingTimeInterval(-2 * 86_400)
        for n in names where n.hasSuffix(".part") {
            let p = dir + "/" + n
            let mtime = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date
            if let m = mtime, m < cutoff { try? fm.removeItem(atPath: p) }
        }
    }

    static func markInstallOutcome() {
        let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        // 眼下跑着的这个版本，无论是自动装上的还是用户手动装的，
        // 从前的失败记录都作废了——拉黑不该是终身的
        UserDefaults.standard.removeObject(forKey: "installFail-\(cur)")
        guard let attempted = UserDefaults.standard.string(forKey: "installAttempt") else { return }
        UserDefaults.standard.removeObject(forKey: "installAttempt")
        guard attempted != cur else { return }   // 版本换过来了，这一轮是成的
        let n = UserDefaults.standard.integer(forKey: "installFail-\(attempted)") + 1
        UserDefaults.standard.set(n, forKey: "installFail-\(attempted)")
        Sys.log(T(223, attempted, "\(n)"))
        if n >= 2 {
            Notifier.post(T(224, attempted))   // 拉黑了就得说一声，别让用户干等
            Auth.onMain { AppDelegate.shared?.refreshIcon() }
        }
    }

    static func isBlacklisted(_ version: String) -> Bool {
        UserDefaults.standard.integer(forKey: "installFail-\(version)") >= 2
    }

    private static var lastSilentCheck: Date {
        get { UserDefaults.standard.object(forKey: "lastSilentCheck") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "lastSilentCheck") }
    }

    /// 后台：每天最多查一次，发现新版静默下好，只发一条「已就绪」通知
    static func dailyCheckIfDue() {
        guard autoCheck, Date().timeIntervalSince(lastCheck) > 86_400 else { return }
        guard tryEnter() else { return }
        DispatchQueue.global(qos: .background).async {
            defer { leave() }
            guard let (latest, dmg, pkg) = fetchLatest() else { return }   // 连不上就静默作罢，明天再来
            lastCheck = Date()
            writeChangelog()
            let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard AppDelegate.versionNewer(latest, than: cur) else { return }
            _ = dmg
            let ok = download(pkg, name: "LTEGuard-\(latest).pkg")
            if ok != nil {
                Notifier.post(T(167, latest))
                Auth.onMain { AppDelegate.shared?.refreshIcon() }   // 菜单出现「安装更新」
            }
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
        // 签约现场：留影入门卫室（已授权时）+ webhook 通报，证据链闭环
        if CameraSnap.authorized {
            DispatchQueue.main.async { CameraSnap.take(tag: "agreement") { _ in } }
        }
        WebhookSender.send(T(148, "\(kind) · \(subject)"))
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
    /// 屏幕锁定中？（锁屏时系统挂起后台相机管线，硬拍只会无声失败）
    static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// 锁屏期间欠下的拍照（解锁瞬间统一补拍一张 unlock）
    static var pendingUnlockSnap = false

    /// 本次修复周期实际拍到的照片（tag → 路径）。webhook 图文只认这里的路径，
    /// 拍不到就发纯文本——绝不退而求其次去找"最近的旧照"
    /// 本轮拍到的照片。写入发生在 AVFoundation 的回调队列，读取与清空
    /// 发生在 Healer 的队列——Swift 字典不是线程安全的，并发读写会崩，
    /// 而且只在唤醒那一刻偶发，最难查。用锁圈起来，别图省事
    private static let shotsLock = NSLock()
    private static var _lastShots: [String: String] = [:]
    static var lastShots: [String: String] {
        get { shotsLock.lock(); defer { shotsLock.unlock() }; return _lastShots }
    }
    static func recordShot(_ tag: String, _ path: String) {
        shotsLock.lock(); _lastShots[tag] = path; shotsLock.unlock()
    }
    static func clearShots() {
        shotsLock.lock(); _lastShots.removeAll(); shotsLock.unlock()
    }

    /// 该有照片却没拍到时提醒用户（多为升级后未重新授权）；每小时最多一次，不刷屏
    private static var lastWarn = Date.distantPast
    static func warnNoPhoto() {
        guard Date().timeIntervalSince(lastWarn) > 3600 else { return }
        lastWarn = Date()
        Sys.log(T(159))
        Notifier.post(T(159))
    }

    static func take(tag: String, completion: @escaping (String?) -> Void) {
        // 授权把关：这里【不】弹授权窗——拍照多发生在唤醒/锁屏等用户不在场
        // 的时刻，弹窗无人应答只会白白错过时机。授权在「新版首次运行」与
        // 「勾选拍照时」这两个用户在场的时机办妥（见 AppDelegate）。
        // 此处只如实记录并提醒，绝不静默失败。
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            Sys.log(T(129))
            warnNoPhoto()
            completion(nil)
            return
        }
        // 锁屏中拍不了（系统隐私保护）：登记欠账，解锁瞬间补拍——
        // 拍到的正是解锁操作者，门卫室语义更准
        if screenLocked && tag != "unlock" {
            pendingUnlockSnap = true
            Sys.log(T(154))
            completion(nil)
            return
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let session = AVCaptureSession()
        session.sessionPreset = .photo
        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else { Sys.log(T(155, tag)); warnNoPhoto(); completion(nil); return }
        session.addInput(input)
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else { completion(nil); return }
        session.addOutput(output)

        // 亮度探针：看真实画面，而不是只信相机的状态标志
        let probe = LumaProbe()
        let vout = AVCaptureVideoDataOutput()
        vout.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        vout.alwaysDiscardsLateVideoFrames = true
        vout.setSampleBufferDelegate(probe, queue: DispatchQueue(label: "luma"))
        if session.canAddOutput(vout) { session.addOutput(vout) }
        session.startRunning()

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let path = "\(dir)/\(f.string(from: Date()))_\(tag).jpg"

        // 唤醒/解锁瞬间摄像头刚上电。此时 isAdjustingExposure 往往还是 false
        // ——自动曝光尚未「开始」，不是已经「结束」；只等这个标志会立刻放行，
        // 拍出来必是黑图。故改为盯住实际画面亮度，等它自己稳下来。
        DispatchQueue.global().async {
            let waited = probe.waitUntilSettled(cam: cam)
            Sys.log(T(194, String(format: "%.1f", waited), String(format: "%.0f", probe.luma * 100)))
            let delegate = SnapDelegate { data in
                session.stopRunning()
                if let d = data, (try? d.write(to: URL(fileURLWithPath: path))) != nil {
                    Sys.log(T(127, path))
                    completion(path)
                } else {
                    Sys.log(T(155, tag))   // 失败不再静默——没有照片必须有解释
                    warnNoPhoto()
                    completion(nil)
                }
            }
            keepSnapDelegate(delegate)      // 持有到回调完成
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

/// 画面亮度探针：逐帧算 Y 平面均值，用真实画面判断曝光是否收敛。
/// 相机的 isAdjustingExposure 在刚上电时是 false（还没开始调整），
/// 单看它会误判为「已就绪」，所以以实测亮度为准，标志位只作辅助。
private final class LumaProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private var recent: [Double] = []        // 最近若干帧亮度，判稳用
    private(set) var luma: Double = 0        // 最新一帧亮度 0…1
    private(set) var frames = 0
    private let t0 = Date()
    /// 采样全程记录（探测模式用）：距开机秒数、亮度、是否仍在调整。
    /// ISO 与快门时长是 iOS 专有属性，macOS 的 AVCaptureDevice 不提供，
    /// 好在判断「什么时候该按快门」只看亮度曲线就够。
    private(set) var trace: [(t: Double, luma: Double, adj: Bool)] = []
    var recording = false
    weak var device: AVCaptureDevice?

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer,
                       from c: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pb) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pb, 0)
        let h = CVPixelBufferGetHeightOfPlane(pb, 0)
        let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let p = base.assumingMemoryBound(to: UInt8.self)
        // 每 8 像素取一点即可判断整体明暗，省 CPU（唤醒瞬间要让路给网卡自愈）
        var sum = 0, n = 0, y = 0
        while y < h {
            var x = 0
            while x < w { sum += Int(p[y * bpr + x]); n += 1; x += 8 }
            y += 8
        }
        guard n > 0 else { return }
        // VideoRange 的 Y 是 16…235，换算回 0…1
        let v = max(0, min(1, (Double(sum) / Double(n) - 16) / 219))
        lock.lock()
        luma = v; frames += 1
        recent.append(v); if recent.count > 5 { recent.removeFirst() }
        if recording, let d = device {
            trace.append((Date().timeIntervalSince(t0), v, d.isAdjustingExposure))
        }
        lock.unlock()
    }

    /// 是否已稳定：最近 5 帧亮度极差小于 1.5%，且画面不是全黑
    private var settled: Bool {
        lock.lock(); defer { lock.unlock() }
        guard recent.count >= 5, let lo = recent.min(), let hi = recent.max() else { return false }
        return hi - lo < 0.015 && hi > 0.02
    }

    /// 等到曝光收敛。返回实际等待秒数。
    /// 下限 0.8 秒——自动曝光需要时间「开始」；上限 6 秒——再久也得给张图。
    @discardableResult
    func waitUntilSettled(cam: AVCaptureDevice) -> Double {
        let start = Date()
        let floorT = 0.8, ceilT = 6.0
        while Date().timeIntervalSince(start) < ceilT {
            Thread.sleep(forTimeInterval: 0.05)
            let el = Date().timeIntervalSince(start)
            if el < floorT { continue }
            if settled && !cam.isAdjustingExposure && !cam.isAdjustingWhiteBalance { break }
        }
        return Date().timeIntervalSince(start)
    }
}

extension CameraSnap {
    /// 探测模式：连续采样 8 秒，打印亮度/ISO/快门随时间的变化，用于定标最佳快门时机。
    /// 走 App 自身的二进制，因而沿用已授予的摄像头权限，不必重新授权。
    static func probeExposure() -> Never {
        // 结果写文件而不是 stdout：这个模式要靠 LaunchServices 启动
        // （open -a …），App 才是自己的责任进程、才用得上自己的摄像头授权；
        // 从终端直接执行二进制时 TCC 会把责任算到终端头上，一律拒绝
        let out = I18n.appSupportDir + "/exposure-probe.tsv"
        func dump(_ s: String) {
            try? s.write(toFile: out, atomically: true, encoding: .utf8)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            dump("摄像头未授权，无法探测\n"); exit(1)
        }
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else { dump("打不开摄像头\n"); exit(1) }
        session.addInput(input)
        let probe = LumaProbe()
        probe.device = cam
        probe.recording = true
        let vout = AVCaptureVideoDataOutput()
        vout.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        vout.setSampleBufferDelegate(probe, queue: DispatchQueue(label: "luma"))
        guard session.canAddOutput(vout) else { dump("加不上视频输出\n"); exit(1) }
        session.addOutput(vout)
        session.startRunning()
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 8)
            session.stopRunning()
            var text = "秒数\t亮度%\t调整中\n"
            for s in probe.trace {
                text += String(format: "%.2f\t%.1f\t%@\n", s.t, s.luma * 100, s.adj ? "是" : "否")
            }
            dump(text)
            exit(0)
        }
        RunLoop.main.run()
        exit(1)
    }
}

/// 拍照代理要活到回调完成。唤醒补拍与解锁补拍可能前后脚撞上，
/// 单个变量会被后来者覆盖，前一个代理提前释放，那张照片就丢了
private let snapKeeperLock = NSLock()
private var snapDelegateKeepers: [ObjectIdentifier: AnyObject] = [:]
private func keepSnapDelegate(_ d: AnyObject) {
    snapKeeperLock.lock(); snapDelegateKeepers[ObjectIdentifier(d)] = d; snapKeeperLock.unlock()
}
private func releaseSnapDelegate(_ d: AnyObject) {
    snapKeeperLock.lock(); snapDelegateKeepers[ObjectIdentifier(d)] = nil; snapKeeperLock.unlock()
}

private final class SnapDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let done: (Data?) -> Void
    init(_ done: @escaping (Data?) -> Void) { self.done = done }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        done(error == nil ? photo.fileDataRepresentation() : nil)
        releaseSnapDelegate(self)
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
                || key == "SILENT_UPDATE" || key == "UPDATE_INTERVAL" {
                let v = Config.parseQuoted(raw) ?? raw.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                switch key {
                case "WEBHOOK_PLATFORM": c.whPlatform = Int(v) ?? 0
                case "WEBHOOK_RICH":     c.whRich = (v == "1")
                case "SILENT_UPDATE":    c.silentInstall = (v == "1")
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
    @discardableResult
    static func runUserCmds(_ text: String, wait: Bool, prefix: String = "") -> String {
        var shellLines: [String] = []
        var snapTags: [String] = []
        for raw in resolveUserCmds(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("--snap") && !t.contains("$(") {
                snapTags.append(t.contains("restored") ? "restored" : (t.contains("wake") ? "wake" : "snap"))
            } else if !t.isEmpty {
                shellLines.append(line)
            }
        }
        for tag in snapTags {
            if wait {
                // 等照片真正落盘再跑 shell，并记住本次的实际路径——
                // 图文 webhook 只用这些路径，绝不去"找最新文件"（那会捞到旧照）
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    CameraSnap.take(tag: tag) { p in
                        if let p = p { CameraSnap.recordShot(tag, p) }
                        sem.signal()
                    }
                }
                _ = sem.wait(timeout: .now() + 8)   // 含曝光收敛等待
            } else {
                // 断联阶段：拍照与打开网络面板并行，互不拖累
                DispatchQueue.main.async {
                    CameraSnap.take(tag: tag) { p in if let p = p { CameraSnap.recordShot(tag, p) } }
                }
            }
        }
        guard !shellLines.isEmpty else { return "" }
        // 本次拍到什么就给什么；没拍到则为空，命令里会自动退化为纯文本
        let imgs = "LTE_IMG1='\(CameraSnap.lastShots["wake"] ?? "")'; "
                 + "LTE_IMG2='\(CameraSnap.lastShots["restored"] ?? "")'; "
        return run(prefix + imgs + shellLines.joined(separator: "\n"), wait: wait)
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
    /// USB 设备的用途分类。分类决定了「能不能自动拔插」这件事：
    /// 存储与影像设备正在读写时被拔插会丢数据，只该手工重置；
    /// 网络与调制解调器正是本工具要守护的对象。
    enum USBKind: Int {
        case network = 0   // 网络、调制解调器——自动守护的正主
        case other   = 1   // 键鼠、音视频、打印机等
        case data    = 2   // 存储、相机——数据类，自动拔插有丢数据之虞
        case hub     = 3   // 集线器——复位它等于把下游全部复位一遍

        /// 排序权重即列表次序：正主在前，有风险的垫后
        var rank: Int { rawValue }
        /// 是否该在界面上标红劝阻。集线器与数据类风险不同，但都不宜自动守护：
        /// 数据类是自身在读写，集线器是替下游背了这个风险
        var risky: Bool { self == .data || self == .hub }
        /// 劝阻的缘由。标题只能短，缘由长，挂在悬停提示里——要看才看
        var why: Int? { self == .data ? 221 : self == .hub ? 222 : nil }
    }

    /// 由 USB 类代码判定用途。设备类为 0（按接口定）或 0xEF（复合设备）时，
    /// 必须往下看接口类才作数——LTE 模块多是复合设备，只看设备类会漏判。
    private static func kind(ofClass dc: Int, interfaces ic: [Int]) -> USBKind {
        // 集线器先认出来：它下面可以挂任何东西——移动硬盘、读卡器、采集卡。
        // 复位集线器等于把下游全部拔插一遍，风险不由它自己决定，
        // 而由用户往上插了什么决定，所以一律不建议自动守护
        if dc == 0x09 || ic.contains(0x09) { return .hub }
        let all = (dc == 0x00 || dc == 0xEF) ? ic : [dc] + ic
        // 一台设备可能兼具多种接口（如带读卡器的模块）：只要沾了存储/影像，
        // 就按数据类对待——宁可少守护一个，不可丢一份数据
        if all.contains(0x08) || all.contains(0x06) { return .data }
        if all.contains(0x02) || all.contains(0x0A) { return .network }
        return .other
    }

    static func usbDevices() -> [(String, String, String, USBKind)] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(Sys.ioDefaultPort,
                IOServiceMatching(kIOUSBDeviceClassName), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var out: [(String, String, String, USBKind)] = []
        while case let dev = IOIteratorNext(iter), dev != 0 {
            defer { IOObjectRelease(dev) }
            func prop(_ k: String) -> Any? {
                IORegistryEntryCreateCFProperty(dev, k as CFString, nil, 0)?.takeRetainedValue()
            }
            guard let v = prop("idVendor") as? Int, let p = prop("idProduct") as? Int else { continue }
            let name = (prop("USB Product Name") as? String)
                ?? (prop("USB Vendor Name") as? String)
                ?? String(format: "%04x:%04x", v, p)
            let dc = prop("bDeviceClass") as? Int ?? 0
            out.append((String(format: "%04x", v), String(format: "%04x", p), name,
                        kind(ofClass: dc, interfaces: interfaceClasses(of: dev))))
        }
        // 先按用途，再按名字：网络类在最前，数据类沉到最后
        return out.sorted {
            $0.3.rank != $1.3.rank ? $0.3.rank < $1.3.rank
                                   : $0.2.localizedStandardCompare($1.2) == .orderedAscending
        }
    }

    /// 递归取该设备下所有接口的 bInterfaceClass。接口挂在设备的子节点上，
    /// 中间可能隔着若干层驱动节点，故子树要走一遍——但**遇到下游 USB 设备
    /// 必须止步**：集线器的子树里挂着所有下游设备，穿过去就会把下游的接口
    /// 算到集线器头上，把集线器误判成网卡。
    private static func interfaceClasses(of dev: io_object_t) -> [Int] {
        var kids: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(dev, kIOServicePlane, &kids) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(kids) }
        var out: [Int] = []
        while case let k = IOIteratorNext(kids), k != 0 {
            defer { IOObjectRelease(k) }
            // 另一台设备的地界，到此为止
            if IOObjectConformsTo(k, "IOUSBHostDevice") != 0
                || IOObjectConformsTo(k, "IOUSBDevice") != 0 { continue }
            if let c = IORegistryEntryCreateCFProperty(k, "bInterfaceClass" as CFString, nil, 0)?
                .takeRetainedValue() as? Int { out.append(c) }
            // 最硬的证据：设备真的在系统里挂出了 enX 网络接口。
            // 描述符里的类代码是厂商「声称」的，enX 是系统「认下」的——
            // 认下的比声称的可信，凡挂得出 enX 的一律按网络类算
            if IOObjectConformsTo(k, "IONetworkInterface") != 0,
               let bsd = IORegistryEntryCreateCFProperty(k, "BSD Name" as CFString, nil, 0)?
                   .takeRetainedValue() as? String,
               bsd.hasPrefix("en"), bsd.dropFirst(2).allSatisfy(\.isNumber) {
                out.append(0x02)
            }
            // 存储设备会在子树里挂出 IOMedia——这是「有数据在上面」的铁证
            if IOObjectConformsTo(k, "IOMedia") != 0 { out.append(0x08) }
            out += interfaceClasses(of: k)
        }
        return out
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

    /// 接口是否还在系统里。USB 网卡假死时接口整个消失，这是硬故障的标志，
    /// 与「接口在、只是还没拿到 IP」（DHCP 未完成）截然不同，不该混为一谈。
    static func interfaceExists(_ dev: String) -> Bool {
        run("ifconfig \(dev) >/dev/null 2>&1 && echo y") == "y"
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
            // 文言紧随简繁体之后：它是汉语的书面源头，不属地域方言
            "zh-Hans", "zh-Hant", "zh-Hant-HK", "lzh",
            "yue", "cmn-sichuan", "cmn-dongbei", "cmn-henan",
            "cmn-shaanxi", "hsn", "cmn-xinjiang", "nan", "nan-chaoshan", "hak", "wuu", "wuu-shanghai",
            // 中国少数民族语言
            "bo", "ug", "mn-Mong", "kk", "za", "ko-CN",
            // 邻近与友好国家
            "ja", "ko", "ko-KP", "vi", "th", "km", "my", "ms", "id", "fil",
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
    var isRTL: Bool { I18n.isRTL(code) }

    /// 某语言是否自右向左书写（按语言代码判断，与当前界面语言无关）
    /// lzh（文言）依传统竖排右起之制，取右起排布：菜单右起、子菜单向左而开。
    /// 汉字为强左向字符，行内仍左起——此为 Unicode 双向算法所定，不作反转。
    static func isRTL(_ code: String) -> Bool {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return ["ar", "he", "fa", "ur", "ug", "ps", "ckb", "yi", "dv", "lzh"].contains(base)
    }

    // Unicode 双向算法隔离符（W3C i18n 推荐做法）
    static let FSI = "\u{2068}"   // First Strong Isolate
    static let PDI = "\u{2069}"   // Pop Directional Isolate
    static let RLM = "\u{200F}"           // Right-to-Left Mark

    /// 语言包定做模式：每条文案前挂上它的序号。改语言包的人最费神的
    /// 不是翻译，而是「界面上这句话是第几号」——把号码直接显示出来，
    /// 对着改即可，不必回头在 ini 里逐条比对
    static var showKeys: Bool {
        get { UserDefaults.standard.bool(forKey: "showLangKeys") }
        set { UserDefaults.standard.set(newValue, forKey: "showLangKeys") }
    }

    /// 是否逐字倒排显示。仅文言（lzh）如此：汉字是强左向字符，Unicode
    /// 双向算法不会把它们右起排布，故由程序显式倒序。
    /// 阿拉伯语、希伯来语等真正的 RTL 文字自有双向算法处理，绝不走这条路径。
    var isGlyphReversed: Bool { code == "lzh" }

    /// 按显示宽度折行，再逐行倒排。**行序不动**——右起读的是每一行，
    /// 不是整段：整段倒置会把末句顶到最前，读序全反，那是错的。
    /// width 为可用像素宽，font 用于实测每个字的宽度。
    static func reverseWrapped(_ s: String, width: CGFloat, font: NSFont) -> String {
        guard width > 20 else { return reverseGlyphs(s) }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return s.split(separator: "\n", omittingEmptySubsequences: false).map { para -> String in
            var lines: [String] = []
            var cur: [String] = []
            var used: CGFloat = 0
            for tok in tokens(of: String(para)) {
                let w = (tok as NSString).size(withAttributes: attrs).width
                // 行首的空格不占位置，否则倒排后行末会多出悬空的空白
                if used + w > width, !cur.isEmpty {
                    lines.append(cur.reversed().joined())
                    cur = []; used = 0
                    if tok == " " { continue }
                }
                cur.append(tok); used += w
            }
            if !cur.isEmpty { lines.append(cur.reversed().joined()) }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// 逐字倒排：汉字一字一序自右而左，拉丁词、数字、占位符整体保序
    /// （"USB" 倒成 "BSU" 便不可读），成对括号引号左右互易。
    /// 只倒每行之内，行序不动。短文本（菜单项、通知）用这个就够。
    static func reverseGlyphs(_ s: String) -> String {
        return s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            tokens(of: String(line)).reversed().joined()
        }.joined(separator: "\n")
    }

    /// 切分成倒排的最小单位：汉字与标点各自成粒（标点顺带左右互易），
    /// 拉丁字母、数字及其粘连符号聚成一词——"USB"、"LTE Guard"、"{0}"
    /// 都得整块搬，拆开就不可读了
    private static func tokens(of line: String) -> [String] {
        let mirror: [Character: Character] = [
            "「": "」", "」": "「", "『": "』", "』": "『", "（": "）", "）": "（",
            "(": ")", ")": "(", "《": "》", "》": "《", "〈": "〉", "〉": "〈",
            "【": "】", "】": "【", "[": "]", "]": "[", "〔": "〕", "〕": "〔",
        ]
        func joinable(_ c: Character) -> Bool {
            (c.isASCII && (c.isLetter || c.isNumber)) || "{}._:/@-+#".contains(c)
        }
        let cs = Array(line)
        var toks: [String] = []
        var buf = ""
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if joinable(c) {
                buf.append(c)
            } else if c == " " && !buf.isEmpty && i + 1 < cs.count && joinable(cs[i + 1]) {
                buf.append(c)          // "LTE Guard" 词组中间的空格不拆
            } else {
                if !buf.isEmpty { toks.append(buf); buf = "" }
                toks.append(String(mirror[c] ?? c))
            }
            i += 1
        }
        if !buf.isEmpty { toks.append(buf) }
        return toks
    }

    /// 取文案：t(21, "Wi-Fi", "USB") -> "已守护 Wi-Fi，方式：USB"
    /// RTL 语言下，插入值用 FSI/PDI 包裹，避免接口名、VID:PID 等拉丁片段
    /// 被 BiDi 算法重排后标点跑到错误一侧。
    func t(_ id: Int, _ args: CVarArg...) -> String {
        var s = table[id] ?? "#\(id)"
        // ini 是单行格式，文案里的换行写作字面 \n——在这里统一还原，
        // 否则对话框会把 "\n\n" 原样显示出来
        s = s.replacingOccurrences(of: "\\n", with: "\n")
        // 文言自行倒排，不用 BiDi 隔离符（隔离符会成为倒排中的杂质）
        let iso = isRTL && !isGlyphReversed
        for (i, a) in args.enumerated() {
            let v = iso ? I18n.FSI + "\(a)" + I18n.PDI : "\(a)"
            s = s.replacingOccurrences(of: "{\(i)}", with: v)
        }
        let body = isGlyphReversed ? I18n.reverseGlyphs(s) : s
        // 号码不参与倒排：它是给编辑者的标记，不是正文的一部分
        return I18n.showKeys ? "\(id)·\(body)" : body
    }

    /// 段落级方向标记：让整段在 RTL 语言下右对齐显示。
    /// 文言已逐字倒排成形，再加 RLM 会让双向算法二次重排，故不加；
    /// 但要按对话框正文的实际宽度重新折行——t() 只倒了字序，
    /// 段落若整块交给系统折行，倒排的行就与视觉的行对不上。
    /// width 取 NSAlert 正文的常见可用宽度，略留余量以免系统二次折行。
    /// width 默认取窄值：不带 accessoryView 的 NSAlert 正文只有 260pt 上下，
    /// 按宽了折，系统会把我折出的行再折一次——视觉的行与倒排的行错开，
    /// 读起来就是乱的。宁可折窄些多占一行，也不能让系统二次折行。
    /// 带 accessoryView 的窗体正文跟着它加宽，那些地方显式传实际宽度。
    func paragraph(_ s: String, width: CGFloat = 248) -> String {
        guard isRTL else { return s }
        guard isGlyphReversed else { return I18n.RLM + s }
        // 语言包定做模式下不再折行重排：序号是给编辑者的标记，一旦卷进
        // 倒排就会被挪到行尾去，反倒认不出哪句是哪句。此时形制让位于对号入座
        guard !I18n.showKeys else { return s }
        // t() 已把字序倒过来了，这里先还原成正序，再按宽度折行重倒一次
        let upright = I18n.reverseGlyphs(s)
        return I18n.reverseWrapped(upright, width: width,
                                   font: .systemFont(ofSize: NSFont.systemFontSize))
    }
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
    private var map: [String: Bool] = [:]   // 接口 → 健康（只在主线程读写，由 refresh 保证）
    private var lastCheck = Date.distantPast

    /// 单接口状态（菜单逐对象显示用）
    func healthy(_ dev: String) -> Bool { map[dev] ?? true }

    /// 全部对象都健康才算健康（图标用）；超过 20 秒自动后台刷新
    func value(for devs: [String]) -> Bool {
        if Date().timeIntervalSince(lastCheck) > 20 { refresh(devs) }
        return devs.allSatisfy { healthy($0) }
    }

    func refresh(_ devs: [String]) {
        // 入口统一切到主线程。map 与 lastCheck 都只在主线程读写，
        // 这个约定原本只写在注释里——而 launchCheck、heal 都在后台调它。
        // 让入口自己保证，调用者就不必各自小心，也不会有人再破例
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.refresh(devs) }
            return
        }
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
    /// 本轮各对象的修复详情（q 上读写），拼成 LTE_INFO 注入「恢复后命令」
    private var infoParts: [String] = []

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
    /// 启动即检。接口不见了就是硬故障（USB 假死的典型表现），立刻修，
    /// 与唤醒后同速；只有「接口在、还没拿到 IP」才可能是 DHCP 没跑完，
    /// 那种情况才需要宽限——不必让所有情形都陪着一起等。
    func launchCheck() {
        q.async {
            let targets = Config.load().targets.filter { !$0.dev.isEmpty }
            guard !targets.isEmpty else { return }
            if targets.contains(where: { !Sys.interfaceExists($0.dev) }) {
                DispatchQueue.global().async { self.checkAndHeal(reason: "launch") }
                return
            }
            DispatchQueue.global().async {
                let deadline = Date().addingTimeInterval(8)
                while Date() < deadline {
                    if targets.allSatisfy({ Sys.interfaceHealthy($0.dev) }) {
                        HealthCache.shared.refresh(targets.map(\.dev))
                        return                      // DHCP 自己跑完了，无须动手
                    }
                    Thread.sleep(forTimeInterval: 1)
                }
                self.checkAndHeal(reason: "launch")
            }
        }
    }

    /// 对勾选守护的 USB 设备逐个软件拔插。放在网卡自愈之前跑：
    /// 若被守护的正是网卡所在的那只 USB 设备，先复位反而省了后面一遍
    private func resetGuardedUSB() {
        let guards = Config.load().usbGuards
        guard !guards.isEmpty else { return }
        var done: [String] = []
        for g in guards {
            let out = Sys.run("'\(Sys.usbresetPath)' \(g.vid) \(g.pid) 2>&1")
            let ok = out.contains("OK")
            Sys.log(ok ? T(214, g.name) : T(113, out))
            if ok { done.append(g.name) }
        }
        // 一次唤醒汇总成一条，逐台发会把通报刷成噪音
        if !done.isEmpty { OpsNotify.report("usb", done.joined(separator: "、")) }
    }

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
                    WebhookSender.flushOutbox()   // 网络在线：顺带补发滞留消息
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

            CameraSnap.clearShots()            // 本轮从零开始，杜绝沿用上次的照片

            // 被守护的 USB 设备：唤醒后无条件复位一次。它们没有通断可验，
            // 只能这么办——所以勾选时才要当面把读写中断的风险讲清并留档
            if reason != "manual" { self.resetGuardedUSB() }

            // ── 「断联时命令」第一时间抢跑（如打开网络面板——它冷启动要 2-4 秒，
            //    必须赶在拔插前开跑，用户才能看到从断联到恢复的全过程）──
            if !cfg.preCmd.isEmpty { Sys.runUserCmds(cfg.preCmd, wait: false) }
            // USB 子系统上电就绪缓冲（原唤醒延迟挪到这里，不再拖累 preCmd）
            Thread.sleep(forTimeInterval: 1)

            // 各对象并行修复；全部结束且至少一个成功后，执行一次「恢复后命令」
            self.infoParts.removeAll()
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
                if anyOK {
                    // 注入 LTE_INFO：webhook 等命令引用它获得详尽内容
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let info = (self.infoParts + [f.string(from: Date())])
                        .joined(separator: " ‖ ")
                        .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: "`", with: "")
                    if !cfg.postCmd.isEmpty {
                        let out = Sys.runUserCmds(cfg.postCmd, wait: true, prefix: "LTE_INFO=\"\(info)\"; ")
                        // shell webhook 的成败也进日志；失败把详尽文本入待补队列
                        if out.contains("__WH_FAIL__") {
                            Sys.log(T(153, "HTTP"))
                            WebhookSender.enqueue("LTE Guard: \(info)")
                        } else if out.contains("__WH_OK__") {
                            Sys.log(T(152))
                        }
                    }
                    // 恢复通报由程序内建发送；勾了图文就带上本次现场照
                    let shots = cfg.whRich
                        ? [CameraSnap.lastShots["wake"] ?? "", CameraSnap.lastShots["restored"] ?? ""]
                        : []
                    WebhookSender.sendRich("LTE Guard: \(info)", images: shots)
                    WebhookSender.flushOutbox()   // 网络已恢复：补发滞留消息
                }
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

        guard !t.vid.isEmpty || !t.service.isEmpty else {
            Sys.log(T(95, rTxt, t.dev))
            AppDelegate.shared?.flashResult("✕")
            return false
        }

        // 最多两次尝试：长时间深睡后设备假死更彻底，一次重枚举可能只让设备
        // 重新出现、蜂窝会话却没活过来——第二次拔插做彻底复位往往就好了
        //（实测：5 小时深睡后首次拔插 30 秒不恢复，再拔一次 2 秒恢复）。
        // 每次尝试轮询 15 秒（正常恢复 2-8 秒，15 秒不恢复基本无望，转重试）
        for attempt in 1...2 {
            if !t.vid.isEmpty {
                Sys.log(T(93, rTxt, t.dev, "\(t.vid):\(t.pid)"))
                let out = Sys.run("'\(Sys.usbresetPath)' \(t.vid) \(t.pid) 2>&1")
                // usbreset 是英文输出的 C 工具：成功时记本地化文案，失败才保留原始输出便于排查
                Sys.log(out.contains("OK") ? T(112, "\(t.vid):\(t.pid)") : T(113, out))
            } else {
                Sys.log(T(94, rTxt, t.dev, t.service))
                Sys.run("networksetup -setnetworkserviceenabled '\(t.service)' off; sleep 3; networksetup -setnetworkserviceenabled '\(t.service)' on")
            }

            // 1 秒粒度轮询。确认标准是 interfaceHealthy（有 IP 且网关 ping 通）——
            // 不能只看 ifconfig 的 inet：拔插后头几秒僵尸 IP 仍残留，会误判"3 秒恢复"
            for _ in 1...15 {
                Thread.sleep(forTimeInterval: 1)
                if Sys.interfaceHealthy(t.dev) {
                    let secs = Int(Date().timeIntervalSince(t0).rounded())
                    Sys.log(T(96, t.dev, secs))
                    HealthCache.shared.refresh([t.dev])   // 立刻把图标/菜单状态刷成最新

                    // ── 内建联网验证：绑定该接口直测外网，结果进通知+图标 ──
                    let online = Sys.run("curl -s -m 5 --interface \(t.dev) -o /dev/null -w '%{http_code}' http://captive.apple.com")
                    let part = T(149, t.display, secs, rTxt, online == "200" ? T(35) : T(36))
                    self.q.async { self.infoParts.append(part) }
                    if online == "200" {
                        Notifier.post(T(105, t.display, secs))
                        AppDelegate.shared?.flashResult("✓\(secs)s")
                    } else {
                        AppDelegate.shared?.flashResult("⚠︎")
                    }
                    return true
                }
            }
            if attempt == 1 { Sys.log(T(141, t.dev)) }
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
    /// 文本或勾选发生任何变化后的回调（如刷新「图文」可用性）
    var onChange: (() -> Void)?

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
        onChange?()
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
    func textDidChange(_ notification: Notification) { refreshBoxes(); onChange?() }
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

    /// 永不退出：值守工具关掉就等于没在守。开了它，连用户自己点退出
    /// 也会被立刻拉起来——这是有意的，所以必须是用户自己勾的，
    /// 且勾的时候要当面把话说清
    static var alwaysOn: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysOn") }
        set {
            UserDefaults.standard.set(newValue, forKey: "alwaysOn")
            UserDefaults.standard.synchronize()   // 立刻落盘：下一步可能就把自己重启了
            if isEnabled { set(true) }
        }
    }

    static var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistPath),
              let t = try? String(contentsOfFile: plistPath, encoding: .utf8) else { return false }
        return t.contains(Bundle.main.bundlePath)   // 指向当前这份 App 才算已启用
    }

    /// 旧版本写入的 plist 需要升级时补写一次：
    /// · 缺 --background 标记（早期版本）
    /// · KeepAlive 为无条件 true（会把用户的主动退出立刻拉活，导致"退出要退两次"）
    static func upgradeIfNeeded() {
        guard isEnabled,
              let t = try? String(contentsOfFile: plistPath, encoding: .utf8),
              !t.contains("--background")
                || (t.contains("<key>KeepAlive</key><true/>") && !alwaysOn)
        else { return }
        set(true)
    }

    /// 写 plist 并重载服务。
    ///
    /// 要紧的一点：`launchctl bootout` 会连带杀掉当前进程——App 正是这个
    /// 服务拉起来的。所以卸载绝不能写在这里，否则它之后的每一行（写 plist、
    /// bootstrap）都执行不到，改动等于没发生。卸载与重挂交给一个独立的
    /// 小脚本，自己被杀之后它还在，能把服务按新 plist 挂回来。
    static func set(_ on: Bool) {
        let uid = getuid()
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard on else {
            // 关闭：先删文件再卸服务，顺序反了会被 KeepAlive 拉回来
            try? FileManager.default.removeItem(atPath: plistPath)
            Sys.run("launchctl bootout gui/\(uid)/\(label) 2>/dev/null")
            return
        }
        let exe = Bundle.main.bundlePath + "/Contents/MacOS/" +
            (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "LTEGuard")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(label)</string>
        <key>ProgramArguments</key><array><string>\(exe)</string><string>--background</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key>\(alwaysOn ? "<true/>" : "<dict><key>SuccessfulExit</key><false/></dict>")
        </dict></plist>
        """
        try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        // 重载由独立进程完成：bootout 会杀掉我们自己，之后的话得有人替我们说
        let sh = "sleep 1; launchctl bootout gui/\(uid)/\(label) 2>/dev/null; "
               + "launchctl bootstrap gui/\(uid) '\(plistPath)' 2>/dev/null"
        Sys.run("nohup sh -c '\(sh)' >/dev/null 2>&1 &", wait: false)
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

        // 3b 摄像头授权（配置了拍照才检查——没配就与本机无关）
        if (cfg.preCmd + cfg.postCmd).contains("--snap") {
            let st = AVCaptureDevice.authorizationStatus(for: .video)
            let txt = st == .authorized ? T(35) : (st == .notDetermined ? T(158) : T(36))
            d.lines.append("\(T(156)): \(txt)")
            if st != .authorized { d.problems.append(T(159)) }
        }

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

/// 合盖状态变化消息（IOPMPrivate.h 的 kIOPMMessageClamshellStateChange：
/// sys_iokit | sub_iokit_powermanagement | 0x100；messageArgument bit0 = 已合盖）
private let kMsgClamshellChange: UInt32 = 0xE001_8100

final class WakeWatcher {
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notifyPort: IONotificationPortRef?
    private var clamshellNote: io_object_t = 0
    private var clamshellPort: IONotificationPortRef?
    private var lastClamshell: Bool?   // 消息可能重复投递，只记状态变化

    func start() {
        let cb: IOServiceInterestCallback = { refcon, _, msgType, msgArg in
            guard let refcon = refcon else { return }
            let me = Unmanaged<WakeWatcher>.fromOpaque(refcon).takeUnretainedValue()
            switch msgType {
            case kMsgCanSleep, kMsgWillSleep:
                if msgType == kMsgWillSleep {
                    Sys.log(T(118))   // 真正入睡才记，询问阶段不记
                    // 睡眠通报：此刻网络还活着，同步抢发（≤3.5s，配置了 webhook 才发；
                    // 失败会入待补队列，唤醒恢复后自动补发并注明原时间）
                    if WebhookSender.configured() != nil {
                        let lid = me.lastClamshell == true ? T(142) : T(150)
                        WebhookSender.send(T(147, lid), sync: true)
                    }
                }
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

        // ── 合盖/开盖时刻：监听 IOPMrootDomain 的 clamshell 状态变化，
        //    与「系统进入休眠」对照即可看出合盖→入睡的间隔 ──
        let pmRoot = IOServiceGetMatchingService(Sys.ioDefaultPort,
                                                 IOServiceMatching("IOPMrootDomain"))
        guard pmRoot != 0 else { return }
        let ccb: IOServiceInterestCallback = { refcon, _, msgType, msgArg in
            guard msgType == kMsgClamshellChange, let refcon = refcon else { return }
            let me = Unmanaged<WakeWatcher>.fromOpaque(refcon).takeUnretainedValue()
            let closed = (UInt(bitPattern: msgArg) & 1) == 1
            guard closed != me.lastClamshell else { return }
            me.lastClamshell = closed
            Sys.log(closed ? T(142) : T(143))
        }
        clamshellPort = IONotificationPortCreate(Sys.ioDefaultPort)
        if let cp = clamshellPort {
            IOServiceAddInterestNotification(cp, pmRoot, kIOGeneralInterest,
                                             ccb, ref, &clamshellNote)
            CFRunLoopAddSource(CFRunLoopGetCurrent(),
                               IONotificationPortGetRunLoopSource(cp).takeUnretainedValue(),
                               .commonModes)
        }
        IOObjectRelease(pmRoot)
    }
}

// MARK: - App

// MARK: - 自测
// 只测纯函数：给定输入必得确定输出，不依赖网络、摄像头或用户点击。
// 这类错误最阴——不崩溃、不报错，只是结果悄悄是错的。
func runSelfTest() -> Never {
    var pass = 0, fail = 0
    func check(_ name: String, _ got: String, _ want: String) {
        if got == want { pass += 1 }
        else { fail += 1; print("✗ \(name)\n   得到: \(got)\n   应为: \(want)") }
    }
    func checkTrue(_ name: String, _ cond: Bool) {
        if cond { pass += 1 } else { fail += 1; print("✗ \(name)") }
    }

    // 配置转义：命令里带引号、反斜杠、换行是常态，存取必须原样往返
    for raw in ["echo 'it\\'s'", "curl -d '{\"k\":\"v\"}' url",
                "a=1; b=$(date); echo $b", "第一行\n第二行", "结尾反斜杠\\",
                "混合 '单' \"双\" \\ 与\n换行"] {
        check("配置往返: \(raw.prefix(16))", Config.unescape(Config.escape(raw)), raw)
    }

    // 文言逐字倒排：倒两次必回原样，否则次序会越滚越乱
    for raw in ["連斷之時，所擇之器自復。", "Mac 醒後，此程察器而自修之",
                "重啟「en0」（此服綁 LTE Guard 也）", "已守 Wi-Fi，法：USB (05c6:9091)"] {
        check("倒排自反: \(raw.prefix(12))", I18n.reverseGlyphs(I18n.reverseGlyphs(raw)), raw)
    }
    // 拉丁词与占位符不许被拆开
    checkTrue("倒排保词序", I18n.reverseGlyphs("甲 LTE Guard 乙").contains("LTE Guard"))
    checkTrue("倒排保占位符", I18n.reverseGlyphs("已用 {0} 秒").contains("{0}"))

    // 版本比较：错一次就可能让人永远收不到更新，或反复装旧版
    let vers: [(String, String, Bool)] = [
        ("2.10.0", "2.9.0", true), ("2.9.0", "2.10.0", false),
        ("2.53.0", "2.53.0", false), ("3.0.0", "2.99.99", true),
        ("2.0.1", "2.0", true), ("2.0", "2.0.1", false),
    ]
    for (a, b, want) in vers {
        checkTrue("版本 \(a) > \(b) = \(want)", AppDelegate.versionNewer(a, than: b) == want)
    }

    // 提示折行：不折的话会横着顶出屏幕，越要紧的话越看不全
    let long = String(repeating: "这是一句很长的说明文字。", count: 4)
    checkTrue("提示折行生效", UI.tip(long).contains("\n"))
    checkTrue("短提示不动它", !UI.tip("很短").contains("\n"))

    // 语言包的完整性不在这里测：那要碰 I18n 的私有表，为测试破封装不划算。
    // 它由仓库里的校验脚本覆盖（72 语言 × 全部在用键，含占位符比对）

    print("\n自测：通过 \(pass)，失败 \(fail)")
    exit(fail == 0 ? 0 : 1)
}

// MARK: - 窗体排版
// 六处对话框原先各写各的宽度与字号，同一个 App 里像出自不同人之手。
// 这里定一套尺寸与字级：一致本身就是可预测性——同样的东西长得一样、
// 在同样的位置，用户第二次就不必重新辨认。
// 间距取 8pt 的整数倍（macOS 的惯用节奏），字级只留三档，够用且不乱。
enum UI {
    /// 内容宽度。定 480：容得下命令编辑框里的等宽命令，
    /// 又不超出对话框正文的可读行宽——再宽，眼睛回行就开始费劲
    static let W: CGFloat = 480
    static let gap: CGFloat = 8          // 相邻控件
    static let group: CGFloat = 24       // 分组之间：留白就是分组，胜过画线
    static let ctrlH: CGFloat = 26       // 下拉、按钮
    static let fieldH: CGFloat = 24      // 输入框
    static let rowH: CGFloat = 24        // 勾选行
    static let labelH: CGFloat = 16

    /// 分组标题：加粗小字、次级色。靠字重而非字号拉开层次，省空间
    static func section(_ s: String, y: CGFloat, width: CGFloat = W) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 0, y: y, width: width, height: labelH)
        return l
    }

    /// 正文标签：与控件同一档字号，并排时基线才齐
    static func body(_ s: String, y: CGFloat, width: CGFloat = W) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.frame = NSRect(x: 0, y: y, width: width, height: labelH)
        return l
    }

    /// 附注：更小、更淡、可折行。说明性文字不该与正文抢注意力
    static func note(_ s: String, y: CGFloat, width: CGFloat = W, height: CGFloat = 52) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: 10)
        l.textColor = .tertiaryLabelColor
        l.frame = NSRect(x: 0, y: y, width: width, height: height)
        return l
    }

    /// 悬停提示折行。一句话不折，toolTip 会铺成一长条顶出屏幕，
    /// 越是要紧的说明越看不全。按显示宽度折——汉字算两格，拉丁算一格
    static func tip(_ s: String, cols: Int = 30) -> String {
        var out = "", line = 0
        for ch in s {
            if ch == "\n" { out.append(ch); line = 0; continue }
            let w = ch.isASCII ? 1 : 2
            if line + w > cols, ch != "，", ch != "。", ch != "、" {
                out.append("\n"); line = 0
            }
            out.append(ch); line += w
        }
        return out
    }

    /// 带边框的滚动列表：勾选项多时统一这一种容器
    static func list(height: CGFloat, width: CGFloat = W) -> NSScrollView {
        let s = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        s.hasVerticalScroller = true
        s.borderType = .bezelBorder
        s.autohidesScrollers = true
        return s
    }
}

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
    private weak var webhookRichPop: NSPopUpButton?
    /// 「通知与通报」窗口控件
    private weak var nfPlatform: NSPopUpButton?
    private weak var nfRich: NSPopUpButton?
    private weak var nfField: NSTextField?
    /// 静默更新的查询节拍。用 DispatchSourceTimer 而非 NSTimer：
    /// 后者挂在 RunLoop 上，菜单打开时会切模式，App Nap 也会把它拖慢
    private var silentTimer: DispatchSourceTimer?
    /// App Nap 会把后台 App 的定时器拖慢甚至挂起。值守工具的心跳不能被
    /// 这样打折——声明一个后台活动，让系统知道我们确实在按点干活
    private var napBlocker: NSObjectProtocol?
    private var dailyTimer: DispatchSourceTimer?
    /// 用户主动唤起时，在此时间点之前强制显示图标（便于调整设置）
    private var forceShowUntil: Date?
    private let forceShowSeconds: TimeInterval = 20

    static func main() {
        // 命令行拍照模式：LTEGuard --snap [标签]，拍完打印路径退出（不进 UI，
        // 短命进程，不参与下面的单实例判定）
        // 曝光探测：诊断用，输出亮度随时间的变化曲线
        if CommandLine.arguments.contains("--exposure-probe") { CameraSnap.probeExposure() }
        // 文言折行自检：整段倒置与逐行倒排肉眼难分，必须能打出来看
        if CommandLine.arguments.contains("--lzh-demo") {
            I18n.shared.load(preferred: "lzh")
            print("── 关于（窄窗体，默认宽度）──")
            print(I18n.shared.paragraph("\(T(57))\n\n\(T(64))\n\(T(66))\n\n\(T(70))"))
            print("\n── 更新说明（宽窗体）──")
            print(I18n.shared.paragraph(T(195), width: UI.W - 16))
            exit(0)
        }
        // 自测：把纯函数逐条跑一遍。这些函数出错都不会崩，只会悄悄给出
        // 错的结果——配置读串行、文言排反、版本比错，全是这一类
        if CommandLine.arguments.contains("--selftest") { runSelfTest() }
        // USB 归类自检：归错类的后果是让人丢数据，必须能当场验
        if CommandLine.arguments.contains("--usb-list") {
            for d in Sys.usbDevices() {
                let tag = ["网络", "其他", "数据⚠️", "集线器⚠️"][d.3.rawValue]
                print("\(tag)\t\(d.0):\(d.1)\t\(d.2)")
            }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snap") {
            let tag = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "manual"
            CameraSnap.runCLI(tag: tag)
        }

        // 单实例保护：更新装完那一刻，LaunchAgent 的保活与安装脚本可能各拉起
        // 一个进程，菜单栏就出现两个图标。
        //
        // 这里用文件锁把关，而不是查 NSRunningApplication——后者依赖
        // LaunchServices 注册，两个进程同时起步时，后者可能压根还看不见前者，
        // 于是双双通过检查。文件锁是内核层的原子操作，没有这个窗口。
        // 锁不显式释放：进程一退出，内核自动收回。
        try? FileManager.default.createDirectory(atPath: I18n.appSupportDir,
                                                 withIntermediateDirectories: true)
        let lockPath = I18n.appSupportDir + "/.instance.lock"
        let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
        if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            // 锁在别人手里，说明已有一个在跑。但用户双击图标是想「看到」它，
            // 不是想再开一个——直接退会显得「点了没反应，App 打不开」。
            // 先转告在跑的那个把图标亮出来，再退。
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.oceantang.lteguard.reopen"), object: nil, deliverImmediately: true)
            exit(0)
        }
        // 锁不上（磁盘异常等）就退回旧办法，至少还有一道
        if lockFD < 0 {
            let bid = Bundle.main.bundleIdentifier ?? "com.oceantang.lteguard"
            let own = ProcessInfo.processInfo.processIdentifier
            if NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .contains(where: { $0.processIdentifier != own
                                   && $0.processIdentifier < own && !$0.isTerminated }) {
                exit(0)
            }
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
    func unhideIfNeeded() {
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
        Updater.markInstallOutcome()   // 结算上一轮安装：成了就清账，败了就记一笔
        DispatchQueue.global(qos: .background).async { Updater.sweepStaleParts() }
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
        // 解锁瞬间补拍：锁屏期间欠下的照片在这里补（拍到的就是解锁者），
        // 若配置了图文 webhook，再把这张单独补推出去
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            guard CameraSnap.pendingUnlockSnap else { return }
            CameraSnap.pendingUnlockSnap = false
            // 解锁瞬间屏幕刚亮、人还在落座，稍等再拍，画面更亮也更完整
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            CameraSnap.take(tag: "unlock") { path in
                guard let path = path else { return }
                let (p, u, rich) = AppDelegate.parseWebhook(from: Config.load().postCmd)
                guard rich, !u.isEmpty else { return }
                DispatchQueue.global().async {
                    let out = Sys.run(AppDelegate.webhookImagePush(platform: p, url: u, img: path))
                    Sys.log(out.contains("__WH_FAIL__") ? T(153, "unlock") : T(152))
                }
            }
            }
        }
        // 第二个进程被文件锁挡下时会发来这条：用户点了图标，想看到我
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.oceantang.lteguard.reopen"), object: nil, queue: .main) { [weak self] _ in
            self?.unhideIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
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
        // 登录后 App 才启动，唤醒事件早已错过。启动就查，接口没了立刻修，
        // 只有还没拿到 IP 才给 DHCP 宽限——见 launchCheck()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            Healer.shared.launchCheck()
        }
        // 每日更新检查（默认开，菜单可关）：启动后 30 秒错开开机高峰，
        // 之后每 6 小时看一次「是否已满 24 小时」，连不上就静默作罢
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { Updater.dailyCheckIfDue() }
        // 先声明后台活动，再起节拍——否则第一拍就可能被 App Nap 吞掉
        napBlocker = ProcessInfo.processInfo.beginActivity(
            options: [.background, .suddenTerminationDisabled],
            reason: "LTE Guard: 定时检查网卡与更新")
        restartSilentTimer()   // 静默更新按用户设定的间隔自己走
        let daily = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        daily.schedule(deadline: .now() + 21_600, repeating: 21_600, leeway: .seconds(300))
        daily.setEventHandler { Updater.dailyCheckIfDue() }
        daily.resume()
        dailyTimer = daily

        // Webhook 迁移与去重：地址搬进「通知与通报」的独立配置，命令里程序添加的
        // 发送行一律清除——现在由程序内建发送，命令里再留一份就会重复发两条。
        // 每次启动都清（不只首次），因为旧版写入的行有多种形态。
        do {
            let (p0, u0, r0) = AppDelegate.parseWebhook(from: cfg0.postCmd)
            let hasSendLine = cfg0.postCmd.split(separator: "\n").contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.hasSuffix(Detect.mark) && t.contains("curl ")
            }
            if !u0.isEmpty || hasSendLine {
                var c = cfg0
                if c.whURL.isEmpty, !u0.isEmpty {   // 首次迁移才接管地址，之后以窗口里的为准
                    c.whPlatform = p0; c.whURL = u0; c.whRich = r0
                }
                c.postCmd = c.postCmd.split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { line in
                        let t = line.trimmingCharacters(in: .whitespaces)
                        // 程序添加的、含 curl 的行＝旧的 webhook 发送行，一律清除；
                        // 用户手写的（无标记）永不触碰
                        return !(t.hasSuffix(Detect.mark) && t.contains("curl "))
                    }
                    .joined(separator: "\n")
                if c.postCmd != cfg0.postCmd || c.whURL != cfg0.whURL {
                    c.save(); cfg0 = c
                    Sys.log(T(188))
                }
            }
        }

        // 新版本首次运行：此刻用户刚装完、人就在电脑前，是办妥摄像头授权的
        // 唯一好时机——重装会让旧授权失配，而唤醒/锁屏时弹窗根本没人点。
        // 拒绝态先重置授权记录，这样能直接弹系统窗，不必让用户翻系统设置。
        let lastRun = UserDefaults.standard.string(forKey: "lastRunVersion") ?? ""
        if lastRun != ver {
            UserDefaults.standard.set(ver, forKey: "lastRunVersion")
            let st = AVCaptureDevice.authorizationStatus(for: .video)
            if (cfg0.preCmd + cfg0.postCmd).contains("--snap"), st != .authorized {
                Sys.log(T(173, ver))
                // 说清这次是从哪个版本升到哪个版本——用户才知道这次弹窗因何而来。
                // 静默更新装的包也记了来源版本，同样能说明白
                let from = UserDefaults.standard.string(forKey: "lastUpgradeFrom") ?? lastRun
                let trace = from.isEmpty ? "" : T(196, from, ver) + "\n\n"
                UserDefaults.standard.removeObject(forKey: "lastUpgradeFrom")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let a = NSAlert()
                    a.messageText = T(125)
                    a.informativeText = I18n.shared.paragraph(trace + T(174))
                    a.alertStyle = .informational
                    a.addButton(withTitle: T(17))
                    a.addButton(withTitle: T(18))
                    NSApp.activate(ignoringOtherApps: true)
                    guard a.runModal() == .alertFirstButtonReturn else { return }
                    if st != .notDetermined {
                        Sys.run("tccutil reset Camera com.oceantang.lteguard >/dev/null 2>&1")
                    }
                    AVCaptureDevice.requestAccess(for: .video) { ok in
                        Sys.log(ok ? T(175) : T(129))
                        if !ok {
                            Auth.onMain {
                                Sys.run("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Camera'", wait: false)
                            }
                        }
                    }
                }
            }
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

        // ── 常用动作（一级，最多三项）──
        m.addItem(item(T(11), #selector(healNow), symbol: "wrench.and.screwdriver"))
        m.addItem(item(T(10), #selector(pickTarget), symbol: "target"))
        m.addItem(usbResetItem())     // 手动救任意 USB 设备，与上面两项同属「对设备动手」
        m.addItem(.separator())
        m.addItem(item(T(53), #selector(editPostCmdGated), symbol: "terminal"))
        m.addItem(.separator())

        // ── 设置 ▸（改变行为的开关）──
        let setItem = item(T(178), nil, symbol: "gearshape")
        let setMenu = sub()
        setMenu.addItem(item(T(30), #selector(toggleLaunch),
                             state: LaunchAtLogin.isEnabled ? .on : .off, symbol: "power.circle"))
        setMenu.addItem(item(T(225), #selector(toggleAlwaysOn),
                             state: LaunchAtLogin.alwaysOn ? .on : .off, symbol: "lock.rotation"))
        setMenu.addItem(item(T(132), #selector(toggleAuthGuard),
                             state: Auth.guardEnabled ? .on : .off, symbol: "touchid"))
        // 菜单栏图标显示方式
        let iconItem = item(T(48), nil, symbol: "menubar.rectangle")
        let iconMenu = sub()
        for (mode, title) in [(IconMode.always, T(49)), (.problemOnly, T(50)), (.hidden, T(51))] {
            let mi = NSMenuItem(title: title, action: #selector(setIconMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = mode.rawValue
            mi.state = (IconMode.current == mode) ? .on : .off
            iconMenu.addItem(mi)
        }
        iconItem.submenu = iconMenu
        setMenu.addItem(iconItem)
        setMenu.addItem(item(T(184), #selector(editNotifyGated), symbol: "bell.badge"))
        setMenu.addItem(languageItem())
        setItem.submenu = setMenu
        m.addItem(setItem)

        // ── 工具 ▸（查看与排查）──
        let toolItem = item(T(179), nil, symbol: "hammer")
        let toolMenu = sub()
        toolMenu.addItem(item(T(12), #selector(openLogGated), symbol: "doc.text"))
        toolMenu.addItem(item(T(68), #selector(openConfigFolderGated), symbol: "folder"))
        toolMenu.addItem(item(T(29), #selector(showDiagnosis), symbol: "stethoscope"))
        toolItem.submenu = toolMenu
        m.addItem(toolItem)

        // ── 更新 ▸（就绪时把一键安装提到一级，其余收进子菜单）──
        if let ready = Updater.readyVersion {
            m.addItem(item(T(168, ready), #selector(installUpdate), symbol: "arrow.down.app"))
        }
        // 更新集中到一个界面：查询、静默更新间隔、安装包目录、版本概要都在里面
        m.addItem(item(T(180) + "…", #selector(showUpdatePanel), symbol: "arrow.down.circle"))

        m.addItem(.separator())
        m.addItem(item(T(56), #selector(showAbout), symbol: "info.circle"))
        m.addItem(item(T(14), #selector(quitGated), symbol: "power"))
        statusItem.menu = m
    }

    /// 「重置 USB 设备」子菜单：列出当前所有 USB 设备，选一个做软件拔插
    private func usbResetItem() -> NSMenuItem {
        let usbItem = item(T(75), nil, symbol: "cable.connector")
        let usbMenu = sub()
        // 先给「持续守护」，再给「这一次复位一下」——前者是设置，后者是动作
        usbMenu.addItem(item(T(210), #selector(pickUSBGuardsGated), symbol: "checklist"))
        let guarded = Config.load().usbGuards
        if !guarded.isEmpty {
            let g = NSMenuItem(title: "　" + guarded.map(\.name).joined(separator: "、"),
                               action: nil, keyEquivalent: "")
            g.isEnabled = false
            usbMenu.addItem(g)
        }
        usbMenu.addItem(.separator())
        let hint = NSMenuItem(title: T(76), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        usbMenu.addItem(hint)
        usbMenu.addItem(.separator())
        // 这里的次序与「自动守护」界面相反：数据类与集线器只该手工重置，
        // 所以在手工菜单里把它们提到最前，最顺手的位置留给最该用它的设备。
        // 分组只用符号与分隔线，不加文字标题——菜单宽度由最长的一项决定，
        // 一句解释就能把整个菜单撑得老宽。缘由挂在悬停提示里，要看才看
        let byKind = Dictionary(grouping: Sys.usbDevices(), by: { $0.3 })
        var first = true
        for kind in [Sys.USBKind.data, .hub, .network, .other] {
            guard let list = byKind[kind], !list.isEmpty else { continue }
            if !first { usbMenu.addItem(.separator()) }
            first = false
            for (vid, pid, name, _) in list {
                let mark = kind.risky ? "⚠️ " : ""
                let di = NSMenuItem(title: "\(mark)\(name)  (\(vid):\(pid))",
                                    action: #selector(resetUSBDevice(_:)), keyEquivalent: "")
                di.target = self
                di.representedObject = "\(vid) \(pid) \(name)"
                di.toolTip = kind.why.map { UI.tip(T($0)) }
                usbMenu.addItem(di)
            }
        }
        usbItem.submenu = usbMenu
        return usbItem
    }

    /// 统一的子菜单构造（RTL 语言下菜单方向也要跟着翻转）
    private func sub() -> NSMenu {
        let mm = NSMenu()
        mm.userInterfaceLayoutDirection = I18n.shared.isRTL ? .rightToLeft : .leftToRight
        return mm
    }

    /// 语言菜单：中文及方言、中国少数民族语言各收进子目录，其余平铺
    private func languageItem() -> NSMenuItem {
        let zhCodes: Set<String> = ["zh-Hans", "zh-Hant", "zh-Hant-HK", "lzh", "yue",
            "cmn-sichuan", "cmn-dongbei", "cmn-henan", "cmn-shaanxi", "hsn",
            "cmn-xinjiang", "nan", "nan-chaoshan", "hak", "wuu", "wuu-shanghai"]
        let minorityCodes: Set<String> = ["bo", "ug", "mn-Mong", "kk", "za", "ko-CN"]

        func langRow(_ code: String, _ name: String) -> NSMenuItem {
            // 语言名是「当地文字（中文名）」混排；RTL 文字与中文相邻时括号会被
            // 双向算法带偏，用 FSI…PDI 隔离成独立方向段，各按各的读序显示
            let li = NSMenuItem(title: I18n.FSI + name + I18n.PDI, action: #selector(switchLang(_:)), keyEquivalent: "")
            // 自右向左书写的语言：该条目本身也按 RTL 排版（右对齐、文字右起），
            // 与当前界面语言无关——阿拉伯语一行就该有阿拉伯语的样子
            if I18n.isRTL(code) {
                let ps = NSMutableParagraphStyle()
                ps.baseWritingDirection = .rightToLeft
                ps.alignment = .right
                // 文言逐字倒排后已成右起之形，不再加 RLM 交由双向算法重排
                let shown = code == "lzh" ? I18n.reverseGlyphs(name) : I18n.RLM + name
                li.attributedTitle = NSAttributedString(
                    string: shown,
                    attributes: [.paragraphStyle: ps,
                                 .font: NSFont.menuFont(ofSize: 0)])
            }
            li.target = self
            li.representedObject = code
            li.state = (code == I18n.shared.code) ? .on : .off
            return li
        }

        let langItem = item(T(13), nil, symbol: "globe")
        let langMenu = sub()
        // RTL 语言分组的子菜单自身也按右起排布，与条目排版一致
        func rtlMenu() -> NSMenu {
            let mm = NSMenu()
            mm.userInterfaceLayoutDirection = .rightToLeft
            return mm
        }
        let disc = NSMenuItem(title: T(69), action: nil, keyEquivalent: "")
        disc.isEnabled = false
        langMenu.addItem(disc)
        langMenu.addItem(.separator())

        let all = I18n.shared.available
        let zhItem = NSMenuItem(title: T(181), action: nil, keyEquivalent: "")
        let zhMenu = sub()
        for (c, n) in all where zhCodes.contains(c) { zhMenu.addItem(langRow(c, n)) }
        zhItem.submenu = zhMenu
        langMenu.addItem(zhItem)

        let minItem = NSMenuItem(title: T(182), action: nil, keyEquivalent: "")
        let minMenu = sub()
        for (c, n) in all where minorityCodes.contains(c) { minMenu.addItem(langRow(c, n)) }
        minItem.submenu = minMenu
        if minMenu.items.count > 0 { langMenu.addItem(minItem) }

        langMenu.addItem(.separator())
        // 自右向左书写的语言收进一组，子菜单整体右起——与它们的行文方向一致
        let rtlList = all.filter { !zhCodes.contains($0.0) && !minorityCodes.contains($0.0) && I18n.isRTL($0.0) }
        if !rtlList.isEmpty {
            let rtlItem = NSMenuItem(title: T(189), action: nil, keyEquivalent: "")
            let rm = rtlMenu()
            for (c, n) in rtlList { rm.addItem(langRow(c, n)) }
            rtlItem.submenu = rm
            langMenu.addItem(rtlItem)
        }
        for (c, n) in all where !zhCodes.contains(c) && !minorityCodes.contains(c) && !I18n.isRTL(c) {
            langMenu.addItem(langRow(c, n))
        }

        // 语言包定做：一个开关，对当前语言生效——哪种语言都可能有人要改
        langMenu.addItem(.separator())
        let devItem = NSMenuItem(title: T(219), action: #selector(toggleShowKeys),
                                 keyEquivalent: "")
        devItem.target = self
        devItem.state = I18n.showKeys ? .on : .off
        langMenu.addItem(devItem)

        langMenu.addItem(.separator())
        let editCur = NSMenuItem(title: T(71), action: #selector(editCurrentLang), keyEquivalent: "")
        editCur.target = self
        langMenu.addItem(editCur)
        let openDir = NSMenuItem(title: T(67), action: #selector(openLangFolder), keyEquivalent: "")
        openDir.target = self
        langMenu.addItem(openDir)
        langItem.submenu = langMenu
        return langItem
    }

    // MARK: 动作

    /// 治愈对象：多选。每个勾选的网卡都被独立守护、独立修复。
    @objc func pickTarget() {
        let services = Sys.networkServices()
        guard !services.isEmpty else { notify(T(23)); return }

        var cfg = Config.load()
        let alert = NSAlert()
        alert.messageText = T(15)
        alert.informativeText = I18n.shared.paragraph(T(108), width: UI.W - 16)
        alert.alertStyle = .informational

        let rowH = Int(UI.rowH)
        let W = Int(UI.W)
        let contentH = services.count * rowH + 4
        let scroll = UI.list(height: CGFloat(min(300, contentH)))
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(W) - 16, height: CGFloat(contentH)))
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
        OpsNotify.report("target", names.isEmpty ? "—" : names)
        Sys.log(T(109, names))
        notify(T(109, names))
        refreshIcon()
    }

    @objc func switchLang(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        let wasRTL = UserDefaults.standard.bool(forKey: "NSForceRightToLeftWritingDirection")
        let nowRTL = I18n.isRTL(code)
        I18n.shared.load(preferred: code)
        Sys.log(T(116, code))
        refreshIcon()

        // 菜单的展开方向、箭头朝向由「应用级」书写方向决定，单个菜单的
        // layoutDirection 只管内容对齐。切到 RTL 语言时打开系统的应用级
        // RTL 开关，重启后子菜单才会真正向左展开、箭头指左。
        guard nowRTL != wasRTL else { notify(T(24)); return }
        UserDefaults.standard.set(nowRTL, forKey: "NSForceRightToLeftWritingDirection")
        UserDefaults.standard.set(nowRTL, forKey: "AppleTextDirection")
        UserDefaults.standard.synchronize()

        // 重启是实现书写方向切换的手段，不是用户要做的决定：直接重启，
        // 不弹确认。App 常驻菜单栏、无未保存状态，重启对用户是无感的。
        //
        // 开着「永不退出」时不能自己再点一把火：那时 KeepAlive 是无条件的，
        // launchd 会在我们退出的瞬间就拉起新的。两把火同时点着，两个进程
        // 去抢同一把文件锁——活下来的那个是对的，但纯属运气，不该这么写
        if !LaunchAtLogin.alwaysOn {
            let exe = Bundle.main.bundlePath + "/Contents/MacOS/" +
                (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? "LTEGuard")
            Sys.run("(sleep 1; '\(exe)' --background &) >/dev/null 2>&1 &", wait: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    /// 语言包定做模式开关：每条文案前挂上它的序号，改语言包时对号入座
    @objc func toggleShowKeys() {
        I18n.showKeys.toggle()
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

        let W = Int(UI.W)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(W), height: 430))

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
        editor.onChange = { [weak self] in self?.webhookRichRefresh() }
        editor.willEnable = { [weak self] p, btn in
            // 相机门：拍照预设与「图文」webhook（命令里都含 --snap）都要过
            guard p.command.contains("--snap") else { return true }
            // 首次开启先签署《门卫室拍照功能使用协议》：展示全文→确认→
            // Touch ID/密码验证即签名→存档 agreement/。签过一次不再打扰
            if !Agreement.hasRecord(kind: "camera-enable") {
                let a = NSAlert()
                a.messageText = T(136)
                let sv = UI.list(height: 240)
                let terms = NSTextView(frame: sv.bounds)
                terms.string = Agreement.cameraTerms
                terms.isEditable = false
                terms.font = .systemFont(ofSize: 11)
                terms.textContainerInset = NSSize(width: UI.gap, height: UI.gap)  // 条款正文别贴边
                terms.autoresizingMask = [.width]
                sv.documentView = terms
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
                rows.append(UI.section(h, y: 0))   // y 由下面的布局统一安排
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
        let oldPre = cfg.preCmd, oldPost = cfg.postCmd
        cfg.preCmd = clean(editor.currentPre)
        cfg.postCmd = clean(editor.currentPost)
        cfg.save()
        // 改了才通报。命令正文不入通报——那是可执行内容，
        // 发出去等于把「唤醒后会跑什么」原样告诉收信一方
        if cfg.preCmd != oldPre || cfg.postCmd != oldPost {
            let n = (cfg.preCmd + "\n" + cfg.postCmd)
                .split(separator: "\n").filter { !$0.isEmpty }.count
            OpsNotify.report("editcmd", T(230, "\(n)"))
        }
        notify(T(55))
    }

    // MARK: Webhook 多平台

    /// 平台顺序与 popup 一致；同格式平台已合并。
    /// 计算属性——切换界面语言后平台名跟着变
    static var webhookPlatforms: [String] { [
        T(120),                              // 0 企业微信 / 钉钉
        T(121),                              // 1 飞书 (Lark)
        "Slack / Teams / Google Chat",       // 2 （Mattermost/Rocket.Chat 同格式）
        "Discord",                           // 3
        "Telegram",                          // 4
        "ntfy.sh",                           // 5
        "IFTTT",                             // 6
        "WhatsApp (CallMeBot)",              // 7
        "Bark",                              // 8
        "Server酱",                          // 9
        "Gotify",                            // 10
        "Pushover",                          // 11
        "Matrix",                            // 12
        T(122),                              // 13 自定义
    ] }

    /// 支持「图文」的平台：企业微信(base64) / Discord(附件) / Telegram(sendPhoto) / ntfy(PUT)
    static let webhookRichCapable: Set<Int> = [0, 3, 4, 5]

    /// 恢复消息正文：Healer 执行「恢复后命令」前会注入 shell 变量 LTE_INFO
    ///（设备/用时/触发原因/联网结果/时间），命令里引用它使内容详尽；
    /// 单独在终端跑时回退为简单文案。shell 双引号内展开。
    private static var msgVar: String { "LTE Guard: ${LTE_INFO:-\(T(82))}" }

    /// 生成的命令整组带成败标记：程序解析输出记日志，失败自动入待补队列
    static func webhookCmd(platform: Int, url: String, rich: Bool = false) -> String {
        "( " + webhookCmdRaw(platform: platform, url: url, rich: rich) + " ) >/dev/null 2>&1 && echo __WH_OK__ || echo __WH_FAIL__"
    }

    private static func webhookCmdRaw(platform: Int, url: String, rich: Bool) -> String {
        let u = url.isEmpty ? "PASTE_YOUR_WEBHOOK_URL" : url
        let m = msgVar

        // 图文＝复用本次唤醒已拍的两张现场照（断联时 wake / 恢复后 restored），
        // 不再额外拍。尺寸远低于各平台上限（企微 base64≤2MB、TG≤10MB、
        // Discord≤8MB、ntfy≤15MB；实拍 40-190KB）。照片缺失时仅发文本。
        let gh = CameraSnap.dir
        // 只认 10 分钟内的照片（文件名含时间戳，sort 即时间序）——
        // 宁可只发文本，绝不误发上一次的旧照
        let pick = "IMG1=\"${LTE_IMG1:-}\"; IMG2=\"${LTE_IMG2:-}\"; "

        if rich && Self.webhookRichCapable.contains(platform) {
            switch platform {
            case 0:   // 企业微信：详尽文本一条 + 两张 base64 图片
                let text = "curl -sf -X POST -H 'Content-Type: application/json' -d \"{\\\"msgtype\\\":\\\"text\\\",\\\"text\\\":{\\\"content\\\":\\\"\(m)\\\"}}\" '\(u)'"
                let imgFn = "snd(){ [ -f \"$1\" ] || return; B64=$(base64 -i \"$1\"); MD5=$(md5 -q \"$1\"); curl -sf -X POST -H 'Content-Type: application/json' -d \"{\\\"msgtype\\\":\\\"image\\\",\\\"image\\\":{\\\"base64\\\":\\\"$B64\\\",\\\"md5\\\":\\\"$MD5\\\"}}\" '\(u)'; }; snd \"$IMG1\"; snd \"$IMG2\""
                return pick + text + "; " + imgFn
            case 3:   // Discord：两张附件 + 详尽文字（缺图时字段为空并不影响文本）
                return pick + "curl -sf -F \"payload_json={\\\"content\\\":\\\"\(m)\\\"}\" ${IMG1:+-F \"file1=@$IMG1\"} ${IMG2:+-F \"file2=@$IMG2\"} '\(u)'"
            case 4:   // Telegram：两张合成相册（sendMediaGroup），一条消息图文混排
                let photoURL = u.replacingOccurrences(of: "sendMessage", with: "sendPhoto")
                let groupURL = u.replacingOccurrences(of: "sendMessage", with: "sendMediaGroup")
                return pick + """
                if [ -f "$IMG1" ] && [ -f "$IMG2" ]; then \
                  curl -sf -F 'media=[{"type":"photo","media":"attach://p1","caption":"\(m)"},{"type":"photo","media":"attach://p2"}]' -F "p1=@$IMG1" -F "p2=@$IMG2" '\(groupURL)'; \
                elif [ -f "$IMG1" ]; then curl -sf -F "photo=@$IMG1" -F "caption=\(m)" '\(photoURL)'; \
                else curl -sf -G '\(u)' --data-urlencode "text=\(m)"; fi
                """
            default:  // ntfy：图片 PUT 时带 X-Message，一条通知即图文混排；无图则纯文本
                return pick + "snd(){ [ -f \"$1\" ] || return 1; curl -sf -T \"$1\" -H 'X-Title: LTE Guard' -H \"X-Message: \(m)\" '\(u)'; }; snd \"$IMG1\" || curl -sf -d \"\(m)\" '\(u)'; snd \"$IMG2\""
            }
        }

        switch platform {
        case 4:   // Telegram Bot API：地址需含 bot<token>/sendMessage?chat_id=…
            return "curl -sf -G '\(u)' --data-urlencode \"text=\(m)\""
        case 5:   // ntfy.sh：纯文本 POST 到 topic 地址
            return "curl -sf -d \"\(m)\" '\(u)'"
        case 7:   // WhatsApp（CallMeBot：地址含 phone 与 apikey）
            return "curl -sf -G '\(u)' --data-urlencode \"text=\(m)\""
        case 9:   // Server酱（sctapi.ftqq.com/KEY.send）
            return "curl -sf -d 'title=LTE Guard' --data-urlencode \"desp=\(m)\" '\(u)'"
        case 11:  // Pushover（地址 query 携带 token 与 user）
            return "curl -sf --data-urlencode \"message=\(m)\" '\(u)'"
        default:
            let json: String
            switch platform {
            case 0:  json = "{\\\"msgtype\\\":\\\"text\\\",\\\"text\\\":{\\\"content\\\":\\\"\(m)\\\"}}"
            case 1:  json = "{\\\"msg_type\\\":\\\"text\\\",\\\"content\\\":{\\\"text\\\":\\\"\(m)\\\"}}"
            case 3:  json = "{\\\"content\\\":\\\"\(m)\\\"}"
            case 6:  json = "{\\\"value1\\\":\\\"\(m)\\\"}"
            case 8:  json = "{\\\"title\\\":\\\"LTE Guard\\\",\\\"body\\\":\\\"\(m)\\\"}"          // Bark
            case 10: json = "{\\\"title\\\":\\\"LTE Guard\\\",\\\"message\\\":\\\"\(m)\\\",\\\"priority\\\":5}"  // Gotify
            case 12: json = "{\\\"msgtype\\\":\\\"m.text\\\",\\\"body\\\":\\\"\(m)\\\"}"           // Matrix
            default: json = "{\\\"text\\\":\\\"\(m)\\\"}"   // Slack/Teams/GChat/Mattermost 与自定义
            }
            return "curl -sf -X POST -H 'Content-Type: application/json' -d \"\(json)\" '\(u)'"
        }
    }

    /// 单张图片补推命令（解锁补拍场景）：按平台生成，带成败标记
    static func webhookImagePush(platform: Int, url: String, img: String) -> String {
        let cmd: String
        switch platform {
        case 0:
            cmd = "B64=$(base64 -i \"\(img)\"); MD5=$(md5 -q \"\(img)\"); curl -sf -X POST -H 'Content-Type: application/json' -d \"{\\\"msgtype\\\":\\\"image\\\",\\\"image\\\":{\\\"base64\\\":\\\"$B64\\\",\\\"md5\\\":\\\"$MD5\\\"}}\" '\(url)'"
        case 3:
            cmd = "curl -sf -F 'payload_json={\"content\":\"LTE Guard (unlock)\"}' -F \"file1=@\(img)\" '\(url)'"
        case 4:
            cmd = "curl -sf -F \"photo=@\(img)\" -F 'caption=LTE Guard (unlock)' '\(url.replacingOccurrences(of: "sendMessage", with: "sendPhoto"))'"
        default:
            cmd = "curl -sf -T \"\(img)\" -H 'X-Title: LTE Guard (unlock)' '\(url)'"
        }
        return "( \(cmd) ) >/dev/null 2>&1 && echo __WH_OK__ || echo __WH_FAIL__"
    }

    /// 从配置里程序添加的 webhook 行回显（平台，地址，是否图文）
    static func parseWebhook(from postCmd: String) -> (Int, String, Bool) {
        for raw in postCmd.split(separator: "\n") {
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard s.hasSuffix(Detect.mark),
                  s.hasPrefix("curl -s") || s.hasPrefix("GH=") || s.hasPrefix("( ")
                  || s.contains("__WH_OK__") || s.contains("--snap webhook") else { continue }
            let rich = s.contains("_wake.jpg") || s.contains("--snap webhook")
            let platform: Int
            if s.contains("callmebot") || s.contains("whatsapp") { platform = 7 }
            else if s.contains("\"desp=") || s.contains("ftqq")  { platform = 9 }
            else if s.contains("\"message=")                     { platform = 11 }  // Pushover
            else if s.contains("m.text")                         { platform = 12 }  // Matrix
            else if s.contains("\\\"body\\\"")                   { platform = 8 }   // Bark
            else if s.contains("\\\"priority\\\"")               { platform = 10 }  // Gotify
            else if s.contains("msgtype")                        { platform = 0 }
            else if s.contains("msg_type")                       { platform = 1 }
            else if s.contains("sendPhoto") || s.contains("--data-urlencode \"text=") || s.contains("--data-urlencode 'text=") { platform = 4 }
            else if s.contains("payload_json") || s.contains("\\\"content\\\"") || s.contains("\"content\":") { platform = 3 }
            else if s.contains("value1")                         { platform = 6 }
            else if s.contains("\\\"text\\\"") || s.contains("\"text\":") { platform = 2 }
            else                                                  { platform = 5 }   // 纯文本/PUT = ntfy
            var url = ""
            if let r = s.range(of: "'http", options: .backwards),
               let end = s.range(of: "'", range: r.upperBound..<s.endIndex) {
                url = String(s[s.index(after: r.lowerBound)..<end.lowerBound])
                    .replacingOccurrences(of: "sendPhoto", with: "sendMessage")
            }
            return (platform, url, rich)
        }
        return (0, "", false)
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
        case 7: return ["https://www.callmebot.com/blog/free-api-whatsapp-messages/"]
        case 8: return ["https://bark.day.app/"]
        case 9: return ["https://sct.ftqq.com/"]
        case 10: return ["https://gotify.net/docs/pushmsg"]
        case 11: return ["https://pushover.net/api"]
        case 12: return ["https://spec.matrix.org/latest/client-server-api/#events"]
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

    /// 图文可用性 = 平台支持 且 拍照功能已勾选（图文复用现场照，没拍照就没图可推）
    private var webhookRichAllowed: Bool {
        let platform = webhookPopup?.indexOfSelectedItem ?? 0
        let snapOn = (postCmdEditor?.currentPre.contains("--snap") ?? false)
                  || (postCmdEditor?.currentPost.contains("--snap") ?? false)
        return AppDelegate.webhookRichCapable.contains(platform) && snapOn
    }

    /// 拍照勾选/文本变化后刷新「图文」可用性；不可用时自动回落文本
    func webhookRichRefresh() {
        guard let rp = webhookRichPop else { return }
        let ok = webhookRichAllowed
        rp.item(at: 1)?.isEnabled = ok
        if !ok, rp.indexOfSelectedItem == 1 {
            rp.selectItem(at: 0)
            webhookUpdate()
        }
    }

    /// 平台/地址/类别变化 → 重新生成命令；若已勾选，文本框中的行就地替换。
    /// 图文不可用时禁用该项并自动回落到文本
    private func webhookUpdate() {
        guard let cb = webhookCheckbox else { return }
        let platform = webhookPopup?.indexOfSelectedItem ?? 0
        let ok = webhookRichAllowed
        webhookRichPop?.item(at: 1)?.isEnabled = ok
        if !ok, webhookRichPop?.indexOfSelectedItem == 1 { webhookRichPop?.selectItem(at: 0) }
        let rich = webhookRichPop?.indexOfSelectedItem == 1
        let url = webhookField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let cmd = AppDelegate.webhookCmd(platform: platform, url: url, rich: rich)
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
    // 打开界面本身不通报——通报留给「确实改了」那一刻，见 pickUSBGuards
    @objc func pickUSBGuardsGated() { Auth.gate { self.pickUSBGuards() } }

    /// 「选择要守护的 USB 设备」：勾选后每次唤醒自动做一次软件拔插。
    /// 与网卡守护分设两处，正因为判据不同——网卡能验通断，普通 USB 设备
    /// 验不了，只能无条件复位，而复位会打断正在进行的读写。这个代价必须
    /// 当面讲清，并按签约留档，不能靠一行小字带过。
    @objc func pickUSBGuards() {
        var cfg = Config.load()
        let devs = Sys.usbDevices()
        let a = NSAlert()
        a.messageText = T(210)
        a.informativeText = I18n.shared.paragraph(T(211), width: UI.W - 16)
        a.alertStyle = .warning

        let W = UI.W, rh = UI.rowH
        let scroll = UI.list(height: 230)
        // 分组标题也占位，高度要算进去
        let groups: [(Sys.USBKind, Int)] = [(.network, 215), (.other, 216), (.data, 217), (.hub, 218)]
        let shown = groups.map { g in (g, devs.filter { $0.3 == g.0 }) }.filter { !$0.1.isEmpty }
        let rows = devs.count + shown.count
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: W - 16,
                                       height: max(230, CGFloat(rows) * rh + 10)))
        var boxes: [(NSButton, (String, String, String))] = []
        var y = doc.frame.height - rh
        for ((kind, titleKey), list) in shown {
            let hdr = UI.section(T(titleKey), y: y + 2, width: W - 32)
            // 有风险的那两组是这个界面里唯一会让人丢东西的，标红，不与其他组同色
            if kind.risky { hdr.textColor = .systemRed }
            hdr.frame.origin.x = 6
            doc.addSubview(hdr)
            y -= rh
            for d in list {
                let cb = NSButton(checkboxWithTitle: "\(d.2)　(\(d.0):\(d.1))", target: nil, action: nil)
                cb.state = cfg.usbGuards.contains { $0.vid == d.0 && $0.pid == d.1 } ? .on : .off
                cb.frame = NSRect(x: 18, y: y, width: W - 44, height: 20)
                if kind.risky { cb.contentTintColor = .systemRed }
                cb.toolTip = kind.why.map { UI.tip(T($0)) }
                doc.addSubview(cb)
                boxes.append((cb, (d.0, d.1, d.2)))
                y -= rh
            }
        }
        scroll.documentView = doc
        // 风险组的缘由在窗体里完整摆出来——这是要人当场看懂的事，
        // 不该藏在悬停提示后面等人去发现
        let risky = shown.map(\.0.0).filter(\.risky).compactMap(\.why)
        if risky.isEmpty {
            a.accessoryView = scroll
        } else {
            let text = risky.map { T($0) }.joined(separator: "\n")
            let note = UI.note(I18n.shared.paragraph(text, width: UI.W - 8),
                               y: 0, height: CGFloat(risky.count) * 30 + 8)
            let box = NSView(frame: NSRect(x: 0, y: 0, width: UI.W,
                                           height: scroll.frame.height + note.frame.height + UI.gap))
            scroll.frame.origin.y = note.frame.height + UI.gap
            box.addSubview(scroll)
            box.addSubview(note)
            a.accessoryView = box
        }
        a.addButton(withTitle: T(17))
        a.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let picked = boxes.filter { $0.0.state == .on }
            .map { (vid: $0.1.0, pid: $0.1.1, name: $0.1.2) }
        let before = Set(cfg.usbGuards.map { "\($0.vid):\($0.pid)" })
        let after = Set(picked.map { "\($0.vid):\($0.pid)" })
        guard before != after else { return }

        func commit(_ method: String) {
            cfg.usbGuards = picked
            cfg.save()
            let names = picked.isEmpty ? "—" : picked.map(\.name).joined(separator: "、")
            OpsNotify.report("usb", names)
            Sys.log(T(212, names))
            self.notify(T(212, names))
            self.refreshIcon()
            _ = method
        }
        // 新勾选了设备才需要签约——取消勾选是解除风险，不必再签一次
        if after.subtracting(before).isEmpty {
            commit("")
        } else {
            Auth.sign { method in
                Agreement.record(kind: "usb-guard",
                                 subject: picked.map { "\($0.name) \($0.vid):\($0.pid)" }
                                     .joined(separator: " / "),
                                 terms: T(210) + "\n\n" + T(211), method: method)
                Auth.onMain { commit(method) }
            }
        }
    }

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
                let ok = out.contains("OK")
                Sys.log(ok ? T(112, "\(vid):\(pid)") : T(113, out))
                // 走的是签约路径而非 Auth.gate，通报得自己补——
                // 真拔插了却不吭声，比看一眼就通报要糟得多
                if ok { OpsNotify.report("usb", "\(name) (\(vid):\(pid))") }
                Auth.onMain { self?.notify(T(79, name)) }
            }
        }
    }

    @objc func toggleLaunch() {
        if LaunchAtLogin.isEnabled {
            // 关闭自启会让守护在重启后失效——敏感方向，受门禁
            Auth.gate("launch") { [weak self] in
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
        // 结论放在标题下，一眼可见；明细进列表——诊断项里有安装路径这类长串，
        // 塞进 informativeText 会把窗体撑得忽宽忽窄，与其他窗体对不齐
        a.informativeText = (d.problems.isEmpty ? "✅ " : "⚠️ ") + T(d.problems.isEmpty ? 45 : 46)
        a.alertStyle = d.problems.isEmpty ? .informational : .warning

        let sv = UI.list(height: 240)
        let tv = NSTextView(frame: sv.bounds)
        tv.isEditable = false
        tv.isSelectable = true            // 诊断信息常要拷出去问人，得能选
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: UI.gap, height: UI.gap)
        tv.autoresizingMask = [.width]

        let body = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        let bad: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemRed]
        let w = UI.W - 16 - UI.gap * 2
        for line in d.lines {
            body.append(NSAttributedString(string: I18n.shared.paragraph(line, width: w) + "\n",
                                           attributes: base))
        }
        if !d.problems.isEmpty {
            body.append(NSAttributedString(string: "\n", attributes: base))
            for p in d.problems {
                body.append(NSAttributedString(
                    string: "• " + I18n.shared.paragraph(p, width: w - 12) + "\n", attributes: bad))
            }
        }
        tv.textStorage?.setAttributedString(body)
        sv.documentView = tv
        a.accessoryView = sv
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
        OpsNotify.report("heal")
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
        a.informativeText = T(57)           // 开源免费 · MIT 协议
        a.alertStyle = .informational

        // 「关于」原本是纯 NSAlert，宽度由系统定，比别的窗体窄一截。
        // 给它同样的容器，全家就一般宽了；顺带把作者信息与那段
        // AI 翻译声明分开字级——前者是事实，后者是提醒，本就不该同重
        let W = UI.W
        let note = UI.note(I18n.shared.paragraph(T(70), width: W - 8), y: 30, height: 64)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 158))
        box.addSubview(UI.body(T(64), y: 138))      // 作者
        box.addSubview(UI.body(T(66), y: 118))      // 所在地
        box.addSubview(UI.body(T(65), y: 98))       // 邮箱
        box.addSubview(note)
        box.addSubview(UI.body(T(59), y: 4))        // 请我喝咖啡
        a.accessoryView = box

        a.addButton(withTitle: T(58))       // 项目主页
        a.addButton(withTitle: T(17))       // 确定
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://github.com/oceantangqoit/Mac-lte-guard") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 通知与通报（webhook 与操作通报的唯一配置处）

    /// 图文可用性＝平台支持 且 已勾选拍照（图文复用现场照，没拍照就没图可发）
    private func nfRefreshRich() {
        guard let rp = nfRich else { return }
        let cfg = Config.load()
        let ok = AppDelegate.webhookRichCapable.contains(nfPlatform?.indexOfSelectedItem ?? 0)
              && (cfg.preCmd + cfg.postCmd).contains("--snap")
        rp.item(at: 1)?.isEnabled = ok
        if !ok, rp.indexOfSelectedItem == 1 { rp.selectItem(at: 0) }
    }

    @objc private func nfPlatformChanged(_ sender: NSPopUpButton) { nfRefreshRich() }

    @objc private func nfHelp(_ sender: NSButton) {
        for u in AppDelegate.webhookDocURLs(platform: nfPlatform?.indexOfSelectedItem ?? 0) {
            if let url = URL(string: u) { NSWorkspace.shared.open(url) }
        }
    }

    /// 当场试发一条：先存下当前填的平台与地址，再走内建发送器
    @objc private func nfTest(_ sender: NSButton) {
        var c = Config.load()
        c.whPlatform = nfPlatform?.indexOfSelectedItem ?? 0
        c.whURL = nfField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        guard !c.whURL.isEmpty else { notify(T(123)); return }
        c.save()
        WebhookSender.send(T(187))
        notify(T(187))
    }

    /// 「更新」界面：查询、静默更新、安装包去向、各版本概要，一处看全。
    /// 静默更新选了间隔就等于开启——「从不」这一档即是关闭，不必再多一个开关。
    @objc func showUpdatePanel() {
        var cfg = Config.load()
        let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let a = NSAlert()
        a.messageText = T(180)
        a.informativeText = I18n.shared.paragraph(T(195), width: UI.W - 16)

        let W = UI.W
        let box = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 156))
        // 当前版本 / 已就绪的更新
        var head = "LTE Guard \(cur)"
        if let ready = Updater.readyVersion { head += "　·　" + T(167, ready) }
        box.addSubview(UI.section(head, y: 136))

        // 「自动安装」是个明确的勾选：勾了才装，不勾就只下好并提示一声
        let auto = NSButton(checkboxWithTitle: T(197), target: nil, action: nil)
        auto.state = cfg.silentInstall ? .on : .off
        auto.frame = NSRect(x: 0, y: 100, width: W, height: 20)
        box.addSubview(auto)

        // 间隔是「自动安装」的从属条件，缩进一格，从属关系一眼可见
        box.addSubview(UI.body(T(198), y: 72, width: 72))
        let pop = NSPopUpButton(frame: NSRect(x: 76, y: 68, width: 160, height: UI.ctrlH), pullsDown: false)
        for (_, key) in Updater.intervalChoices { pop.addItem(withTitle: T(key)) }
        let idx = Updater.intervalChoices.firstIndex { $0.0 == cfg.updateInterval } ?? 0
        pop.selectItem(at: idx)
        box.addSubview(pop)

        let daily = NSButton(checkboxWithTitle: T(169), target: nil, action: nil)
        daily.state = Updater.autoCheck ? .on : .off
        daily.frame = NSRect(x: 250, y: 70, width: W - 250, height: 20)
        box.addSubview(daily)

        // 安装包去向说明——静默更新会不声不响地装，更要讲清包放在哪
        box.addSubview(UI.note(I18n.shared.paragraph(T(164), width: W - 8), y: 0, height: 56))

        // 各版本概要是「去看看」，不是对设置的表态，放进界面里做按钮
        let logBtn = NSButton(frame: NSRect(x: W - 150, y: 130, width: 150, height: UI.fieldH))
        logBtn.bezelStyle = .rounded
        logBtn.title = T(172)
        logBtn.target = self; logBtn.action = #selector(openChangelog)
        box.addSubview(logBtn)

        a.accessoryView = box
        a.addButton(withTitle: T(17))     // 确定
        a.addButton(withTitle: T(137))    // 立即检查
        a.addButton(withTitle: T(18))     // 取消
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal()

        // 取消就是取消——界面上的改动一概不落地
        guard r != .alertThirdButtonReturn else { return }

        let sel = max(0, pop.indexOfSelectedItem)
        let picked = Updater.intervalChoices[sel].0
        if picked != cfg.updateInterval {
            cfg.updateInterval = picked
            Sys.log(T(209, T(Updater.intervalChoices[sel].1)))
        }
        cfg.silentInstall = auto.state == .on
        cfg.save()
        restartSilentTimer()
        if (daily.state == .on) != Updater.autoCheck { Updater.autoCheck = daily.state == .on }
        refreshIcon()

        if r == .alertSecondButtonReturn { checkUpdate() }
    }

    /// 打开各版本更新概要（先刷新一次，保证看到的是最新的）
    @objc func openChangelog() {
        DispatchQueue.global().async {
            Updater.writeChangelog()
            let f = Updater.dir + "/commits.txt"
            Auth.onMain {
                if FileManager.default.fileExists(atPath: f) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: f))
                } else {
                    self.notify(T(183))
                }
            }
        }
    }

    /// 间隔改了就换新节奏，不必等下一次触发
    func restartSilentTimer() {
        silentTimer?.cancel()
        silentTimer = nil
        let sec = Config.load().updateInterval
        guard sec > 0 else { return }
        // 查询周期按设定值走，但至少每 30 秒才轮一次，避免空转
        let tick = Double(max(30, min(sec, 1_800)))
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + tick, repeating: tick, leeway: .seconds(2))
        t.setEventHandler { Updater.silentCheckIfDue() }
        t.resume()
        silentTimer = t
    }

    /// 「通知与通报」：Webhook 地址与敏感操作通报集中在此，改一处即处处生效
    @objc func editNotify() {
        var cfg = Config.load()
        let a = NSAlert()
        a.messageText = T(184)
        a.informativeText = I18n.shared.paragraph(T(185), width: UI.W - 16)

        let W = UI.W
        let box = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 318))
        func label(_ t: String, _ y: CGFloat) -> NSTextField { UI.section(t, y: y, width: W) }
        box.addSubview(label(T(92), 296))

        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 264, width: 210, height: 26), pullsDown: false)
        pop.addItems(withTitles: AppDelegate.webhookPlatforms)
        pop.selectItem(at: min(cfg.whPlatform, AppDelegate.webhookPlatforms.count - 1))
        pop.target = self; pop.action = #selector(nfPlatformChanged(_:))
        box.addSubview(pop)

        let rich = NSPopUpButton(frame: NSRect(x: 218, y: 264, width: 116, height: 26), pullsDown: false)
        rich.addItems(withTitles: [T(145), T(146)])
        rich.autoenablesItems = false
        box.addSubview(rich)

        let help = NSButton(frame: NSRect(x: W - 28, y: 264, width: 26, height: 26))
        help.bezelStyle = .helpButton; help.title = ""
        help.toolTip = T(124); help.target = self; help.action = #selector(nfHelp(_:))
        box.addSubview(help)

        let field = NSTextField(frame: NSRect(x: 0, y: 232, width: W, height: 24))
        field.placeholderString = T(123)
        field.stringValue = cfg.whURL
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        box.addSubview(field)

        let test = NSButton(frame: NSRect(x: 0, y: 200, width: 130, height: 26))
        test.bezelStyle = .rounded; test.title = T(186)
        test.target = self; test.action = #selector(nfTest(_:))
        box.addSubview(test)

        nfPlatform = pop; nfRich = rich; nfField = field
        rich.selectItem(at: cfg.whRich ? 1 : 0)
        nfRefreshRich()

        box.addSubview(label(T(176), 174))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: W, height: 168))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let cat = OpsNotify.catalog
        let rh: CGFloat = 22
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: W - 16,
                                       height: max(168, CGFloat(cat.count) * rh + 8)))
        var boxes: [(NSButton, String)] = []
        var y = doc.frame.height - rh
        for (code, title) in cat {
            let cb = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            cb.state = cfg.notifyOps.contains(code) ? .on : .off
            cb.frame = NSRect(x: 6, y: y, width: W - 32, height: 18)
            doc.addSubview(cb)
            boxes.append((cb, code))
            y -= rh
        }
        scroll.documentView = doc
        box.addSubview(scroll)

        a.accessoryView = box
        a.addButton(withTitle: T(17))
        a.addButton(withTitle: T(18))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let oldURL = cfg.whURL, oldOps = cfg.notifyOps
        cfg.whPlatform = pop.indexOfSelectedItem
        cfg.whURL = field.stringValue.trimmingCharacters(in: .whitespaces)
        cfg.whRich = (rich.indexOfSelectedItem == 1)
        cfg.notifyOps = Set(boxes.filter { $0.0.state == .on }.map { $0.1 })
        cfg.save()
        // 改了才通报，且说明改的是什么。地址本身绝不入通报——
        // 那是凭据，发出去等于把钥匙一并寄了
        if cfg.whURL != oldURL || cfg.notifyOps != oldOps {
            var what: [String] = []
            if cfg.whURL != oldURL { what.append(T(229)) }
            if cfg.notifyOps != oldOps { what.append(T(230, "\(cfg.notifyOps.count)")) }
            OpsNotify.report("notify", what.joined(separator: "、"))
        }
        notify(T(55))
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
            var latest = "", dmg = "", pkg = ""
            if let d = out.data(using: .utf8),
               let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
               let tag = j["tag_name"] as? String {
                latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                for a in (j["assets"] as? [[String: Any]]) ?? [] {
                    guard let n = a["name"] as? String,
                          let u = a["browser_download_url"] as? String else { continue }
                    if n.hasSuffix(".dmg") { dmg = u } else if n.hasSuffix(".pkg") { pkg = u }
                }
            }
            let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            Auth.onMain { [weak self] in
                guard let self else { return }
                guard !latest.isEmpty else { self.notify(T(140)); return }
                guard Self.versionNewer(latest, than: cur) else { self.notify(T(139)); return }

                let a = NSAlert()
                a.messageText = T(138, latest, cur)
                a.informativeText = I18n.shared.paragraph(T(164))
                a.addButton(withTitle: T(163))   // 立即下载并更新
                a.addButton(withTitle: T(58))    // 项目主页（自己下）
                a.addButton(withTitle: T(18))
                NSApp.activate(ignoringOtherApps: true)
                switch a.runModal() {
                case .alertFirstButtonReturn:
                    Updater.downloadAndInstall(version: latest, dmg: dmg, pkg: pkg)
                case .alertSecondButtonReturn:
                    NSWorkspace.shared.open(URL(string: "https://github.com/oceantangqoit/Mac-lte-guard/releases/latest")!)
                default: break
                }
            }
        }
    }

    @objc func installUpdate() { Updater.installReady() }

    @objc func toggleAutoUpdate() {
        Updater.autoCheck.toggle()
        notify(Updater.autoCheck ? T(170) : T(171))
        refreshIcon()
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
    @objc func quitGated() {
        // 开着「永不退出」时点退出，程序会消失一下又被拉回来。
        // 那是设定如此，但不当面说一声，看着就像退不掉的故障
        if LaunchAtLogin.alwaysOn {
            let a = NSAlert()
            a.messageText = T(225)
            a.informativeText = I18n.shared.paragraph(T(226))
            a.alertStyle = .informational
            a.addButton(withTitle: T(17))
            a.addButton(withTitle: T(18))
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        Auth.gate("quit") {
            // 退出守护前留一张（拍照功能开启时）：谁关的门卫，门卫先拍谁
            let cfg = Config.load()
            if CameraSnap.authorized, (cfg.preCmd + cfg.postCmd).contains("--snap") {
                let sem = DispatchSemaphore(value: 0)
                CameraSnap.take(tag: "quit") { _ in sem.signal() }
                DispatchQueue.global().async {
                    _ = sem.wait(timeout: .now() + 2.5)
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                }
            } else {
                NSApp.terminate(nil)
            }
        }
    }
    @objc func openConfigFolderGated() { Auth.gate("config") { [weak self] in self?.openConfigFolder() } }
    @objc func openLogGated()        { Auth.gate("log") { [weak self] in self?.openLog() } }
    @objc func editNotifyGated()     { Auth.gate { [weak self] in self?.editNotify() } }

    /// 开关本身也要防绕过：开启随手，关闭需验证
    /// 永不退出：开着它，连用户自己点退出也会被立刻拉起来。
    /// 这是有意的行为，但必须当面讲清楚，否则用户会以为「退不掉」是故障
    @objc func toggleAlwaysOn() {
        let turningOn = !LaunchAtLogin.alwaysOn
        if turningOn {
            let a = NSAlert()
            a.messageText = T(225)
            a.informativeText = I18n.shared.paragraph(T(226))
            a.alertStyle = .informational
            a.addButton(withTitle: T(17))
            a.addButton(withTitle: T(18))
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
            // 保活的前提是有 LaunchAgent，没开机自启就一并开了
            if !LaunchAtLogin.isEnabled { LaunchAtLogin.set(true) }
        }
        LaunchAtLogin.alwaysOn = turningOn
        // 开与关各用各的句子。先前拿 133/134 当通用的「已开启/已关闭」，
        // 那两条是敏感操作验证的专用文案，套到这里就成了驴唇不对马嘴
        Sys.log(T(turningOn ? 227 : 228))
        notify(T(turningOn ? 227 : 228))
        refreshIcon()
    }

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
