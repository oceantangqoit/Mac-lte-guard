import Cocoa

// MARK: - 开机自启

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
            set(true)   // 无论 LaunchAgent 之前是否已存在，切换时一律重写 plist 并重载
        }
    }

    /// 勾选「永不退出」后第一次退出是否已弹过提示。
    /// 勾选时弹 + 第一次退出弹，之后静默——KeepAlive 会无声拉起，不需要每次都确认。
    static var firstExitReminded: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysOnFirstExitReminded") }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysOnFirstExitReminded") }
    }

    static var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistPath),
              let t = try? String(contentsOfFile: plistPath, encoding: .utf8) else { return false }
        return t.contains(Bundle.main.bundlePath)   // 指向当前这份 App 才算已启用
    }

    /// plist 与 UserDefaults 不一致时自动纠正（启动时运行一次）。
    /// 覆盖三种情况：
    /// · 缺 --background 标记（早期版本）
    /// · KeepAlive 为无条件 true 但「永不退出」未开——退出要退两次
    /// · KeepAlive 为 SuccessfulExit 但「永不退出」已开——退出后回不来
    static func reconcilePlistIfNeeded() {
        guard isEnabled,
              let t = try? String(contentsOfFile: plistPath, encoding: .utf8),
              !t.contains("--background")
                || (t.contains("<key>KeepAlive</key><true/>") != alwaysOn)
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
