import Cocoa
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
