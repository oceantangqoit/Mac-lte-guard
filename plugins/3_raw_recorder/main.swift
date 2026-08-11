import Cocoa
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

// MARK: - 插件3：原始数据采集器（什么都记）
// 用法：raw_recorder [输出文件.jsonl]   （默认 ~/Documents/activity-raw-<日期>.jsonl）
// 每 5 秒采样一行 JSONL；系统睡眠/唤醒也记一条 event。Ctrl-C 退出。

final class Recorder {
    private let lock = NSLock()
    private var handle: FileHandle?

    init(path: String) {
        // 路径是目录则拼默认文件名
        var p = path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
            p = p + "/activity-raw-\(Date().timeIntervalSince1970).jsonl"
        }
        if !FileManager.default.fileExists(atPath: p) {
            FileManager.default.createFile(atPath: p, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: p)
        print("记录到: \(p)")
    }

    func write(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        guard let h = handle else { return }
        h.seekToEndOfFile()
        h.write((line + "\n").data(using: .utf8) ?? Data())
    }

    func event(_ name: String, extra: [String: Any] = [:]) {
        var d = extra
        d["event"] = name
        d["ts"] = Sensors.now()
        write((try? JSONSerialization.data(withJSONObject: d))!
            .withUnsafeBytes { String(decoding: $0, as: UTF8.self) })
    }

    func sample() {
        var s = Sensors.sample()
        s.ts = Sensors.now()
        write(s.jsonLine)
    }
}

// MARK: - 系统睡眠/唤醒监听（IOKit，零权限；消息常量按 IOMessage.h 硬编码）

private let kMsgWillSleep: UInt32 = 0xE000_0280   // kIOMessageSystemWillSleep
private let kMsgPoweredOn: UInt32 = 0xE000_0300   // kIOMessageSystemHasPoweredOn

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
                switch msgType {
                case kMsgWillSleep: me.onEvent?("sleep")
                case kMsgPoweredOn: me.onEvent?("wake")
                default: break
                }
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

// MARK: - 入口

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path
let rec = Recorder(path: path)

rec.event("start", extra: ["host": Host.current().localizedName ?? ""])

let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
timer.schedule(deadline: .now() + 1, repeating: 5)
timer.setEventHandler { rec.sample() }
timer.resume()

PowerWatcher().start { ev in rec.event(ev) }

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sig.setEventHandler { rec.event("stop"); exit(0) }
sig.resume()
let sigT = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigT.setEventHandler { rec.event("stop"); exit(0) }
sigT.resume()

print("开始记录（每 5 秒一行，Ctrl-C 停止）...")
dispatchMain()
