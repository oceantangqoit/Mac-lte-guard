import Foundation

// MARK: - 插件4：Cloudflare DDNS
// 轮询公网 IPv4，变化时调 Cloudflare API v4 更新（或创建）DNS A 记录。
// 用法：cf_ddns --token <API Token> --zone <Zone ID> --record <home.example.com>
//              [--interval 300] [--ttl 1] [--dir 输出目录]
// 输出目录里写两个文件：ddns-log.jsonl（每次动作一行）、ddns-state.json（面板读状态用）。
// Ctrl-C / SIGTERM 退出。Token 只走 Authorization 头，不写日志。

struct Args {
    var token = ""
    var zone = ""
    var record = ""
    var interval = 300   // 秒
    var ttl = 1          // 1 = Cloudflare 自动
    var dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/lte-guard-ddns").path

    static func parse() -> Args {
        var a = Args()
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            guard let v = it.next() else { break }
            switch k {
            case "--token": a.token = v
            case "--zone": a.zone = v
            case "--record": a.record = v
            case "--interval": a.interval = max(30, Int(v) ?? 300)
            case "--ttl": a.ttl = max(1, Int(v) ?? 1)
            case "--dir": a.dir = v
            default: break
            }
        }
        return a
    }
}

final class Log {
    private let lock = NSLock()
    private let logPath: String
    private let statePath: String

    init(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        logPath = dir + "/ddns-log.jsonl"
        statePath = dir + "/ddns-state.json"
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
    }

    static func ts() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    func write(_ d: [String: Any]) {
        var x = d; x["ts"] = Log.ts()
        guard let data = try? JSONSerialization.data(withJSONObject: x),
              let line = String(data: data, encoding: .utf8) else { return }
        lock.lock(); defer { lock.unlock() }
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); h.closeFile()
        }
    }

    /// 面板展示用：当前 IP、上次更新时间与结果
    func state(ip: String, result: String) {
        let d: [String: Any] = ["ip": ip, "last_update": Log.ts(), "last_result": result]
        guard let data = try? JSONSerialization.data(withJSONObject: d, options: .prettyPrinted) else { return }
        lock.lock(); defer { lock.unlock() }
        try? data.write(to: URL(fileURLWithPath: statePath))
    }
}

// MARK: - HTTP（同步封装，单次请求 ≤8 秒超时）

func http(_ method: String, _ url: String, token: String? = nil,
          body: [String: Any]? = nil) -> (Int, [String: Any]?) {
    guard let u = URL(string: url) else { return (0, nil) }
    var req = URLRequest(url: u, timeoutInterval: 8)
    req.httpMethod = method
    if let t = token {
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let b = body { req.httpBody = try? JSONSerialization.data(withJSONObject: b) }
    let sem = DispatchSemaphore(value: 0)
    var code = 0, json: [String: Any]?
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let data = data {
            json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 9)
    return (code, json)
}

/// 公网 IPv4：三个源轮询，拿到第一个合法地址即止
func publicIP() -> String? {
    for src in ["https://api.ipify.org", "https://ipv4.icanhazip.com", "https://ifconfig.me/ip"] {
        guard let u = URL(string: src) else { continue }
        let sem = DispatchSemaphore(value: 0)
        var out: String?
        URLSession.shared.dataTask(with: URLRequest(url: u, timeoutInterval: 6)) { data, _, _ in
            if let data = data { out = String(data: data, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 7)
        let ip = (out ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 粗校验：四段数字
        let parts = ip.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return ip }
    }
    return nil
}

// MARK: - Cloudflare DDNS 主逻辑

final class DDNS {
    let args: Args
    let log: Log
    /// 上次成功写进 Cloudflare 的 IP（内存态；状态文件只做展示，不做判断依据——
    /// 以 API 查到的记录内容为准，才不会漏掉外部改动）
    private var lastSynced = ""
    /// 每 24 个周期（默认 2 小时）强制核对一次记录内容
    private var cycles = 0

    init(_ a: Args) { args = a; log = Log(dir: a.dir) }

    func tick() {
        guard let ip = publicIP() else {
            log.write(["event": "error", "detail": "获取公网 IP 失败"])
            return
        }
        cycles += 1
        if ip == lastSynced, cycles % 24 != 0 {
            log.state(ip: ip, result: "skip")
            return   // IP 没变且未到强制核对点
        }
        let base = "https://api.cloudflare.com/client/v4/zones/\(args.zone)/dns_records"
        let (code, resp) = http("GET", "\(base)?type=A&name=\(args.record)", token: args.token)
        guard code == 200, let resp = resp, (resp["success"] as? Bool) == true else {
            let msg = Self.errMsg(resp) ?? "HTTP \(code)"
            log.write(["event": "error", "ip": ip, "detail": "查询记录失败：\(msg)"])
            log.state(ip: ip, result: "error: \(msg)")
            return
        }
        let results = resp["result"] as? [[String: Any]] ?? []
        let body: [String: Any] = ["type": "A", "name": args.record,
                                   "content": ip, "ttl": args.ttl, "proxied": false]
        if let rec = results.first, let rid = rec["id"] as? String {
            if (rec["content"] as? String) == ip {
                lastSynced = ip
                log.state(ip: ip, result: "skip")
                return   // 记录已是当前 IP
            }
            let (c2, r2) = http("PUT", "\(base)/\(rid)", token: args.token, body: body)
            finish(c2, r2, ip: ip, action: "update")
        } else {
            let (c2, r2) = http("POST", base, token: args.token, body: body)
            finish(c2, r2, ip: ip, action: "create")
        }
    }

    private func finish(_ code: Int, _ resp: [String: Any]?, ip: String, action: String) {
        if code == 200, (resp?["success"] as? Bool) == true {
            lastSynced = ip
            log.write(["event": action, "ip": ip, "record": args.record])
            log.state(ip: ip, result: action)
        } else {
            let msg = Self.errMsg(resp) ?? "HTTP \(code)"
            log.write(["event": "error", "ip": ip, "detail": "\(action) 失败：\(msg)"])
            log.state(ip: ip, result: "error: \(msg)")
        }
    }

    static func errMsg(_ resp: [String: Any]?) -> String? {
        let errs = resp?["errors"] as? [[String: Any]]
        return errs?.first?["message"] as? String
    }
}

// MARK: - 入口

let args = Args.parse()
guard !args.token.isEmpty, !args.zone.isEmpty, !args.record.isEmpty else {
    print("用法: cf_ddns --token <API Token> --zone <Zone ID> --record <域名> [--interval 秒] [--ttl N] [--dir 目录]")
    exit(2)
}
let ddns = DDNS(args)
ddns.log.write(["event": "start", "record": args.record, "interval": args.interval])
print("Cloudflare DDNS 启动：\(args.record)，每 \(args.interval) 秒轮询，Ctrl-C 停止")

let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
timer.schedule(deadline: .now() + 1, repeating: .seconds(args.interval))
timer.setEventHandler { ddns.tick() }
timer.resume()

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
for sig in [SIGINT, SIGTERM] {
    let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    s.setEventHandler { ddns.log.write(["event": "stop"]); exit(0) }
    s.resume()
}
dispatchMain()
