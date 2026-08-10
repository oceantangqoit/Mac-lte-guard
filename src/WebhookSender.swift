import Cocoa
import CommonCrypto

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
    /// 统一落款：收信一方可能管着好几台 Mac，少了这一行就分不清谁在说话。
    /// 加在发送入口，一处生效——日后新增的消息也不会漏掉
    static func stamp(_ text: String) -> String {
        let who = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let host = Host.current().localizedName ?? ""
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return text + "\n" + T(233, "\(who)@\(host)", f.string(from: Date()))
    }

    /// stamped：文本是否已带落款。补发走这条路——队列里存的就是当初盖过戳的
    /// 原文，重盖会把补发时间冒充成事发时间。靠正文里有没有破折号去猜并不可靠
    static func send(_ raw: String, sync: Bool = false, queueOnFail: Bool = true,
                     stamped: Bool = false) {
        let text = stamped ? raw : stamp(raw)
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
    static func sendRich(_ rawText: String, images: [String]) {
        let text = stamp(rawText)
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
            // 队列里存的是当初盖过戳的原文，不能重盖——否则补发时间会
            // 冒充成事发时间，值守记录的可信度就没了
            send("[\(T(151, parts[0]))] \(parts[1])", sync: false,
                 queueOnFail: true, stamped: true)
        }
    }
}
