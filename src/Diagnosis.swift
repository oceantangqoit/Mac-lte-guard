import Cocoa
import AVFoundation

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
