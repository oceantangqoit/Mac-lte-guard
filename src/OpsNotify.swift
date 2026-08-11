import Cocoa

// MARK: - 敏感操作通报
// 用户在「Mac 唤醒后执行命令…」里勾选哪些操作要通报，操作发生时（验证通过后）
// 立即发 webhook。人在异地也能第一时间知道有人动了守护设置。
enum OpsNotify {
    /// 操作代号 → 界面名称（复用既有菜单文案键，无需新翻译）
    static var catalog: [(String, String)] {
        [("editcmd", T(53)), ("notify", T(184)), ("target", T(10)), ("heal", T(11)), ("log", T(12)),
         ("config", T(68)), ("launch", T(30)), ("usb", T(75)),
         ("update", T(190)), ("quit", T(14)), ("autoheal", T(234)), ("settings", T(238))]
    }

    static func name(_ op: String) -> String {
        catalog.first { $0.0 == op }?.1 ?? op
    }

    /// 已勾选才发；带操作名、机器名、使用者与时间
    /// detail 是「改成了什么」。通报一个动作而不说结果，收到的人还得自己去查，
    /// 值守消息就该一眼看明白
    static func report(_ op: String, _ detail: String = "", alsoLog: Bool = true) {
        guard Config.load().notifyOps.contains(op) else { return }
        let who = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let host = Host.current().localizedName ?? ""
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let subject = detail.isEmpty ? name(op) : name(op) + "\u{FF1A}" + detail
        var text = T(231, subject)
        // 活动感知（插件性质，默认 off）
        let act = ActivitySense.shared.summary()
        if !act.isEmpty { text += "\n" + T(247, act) }
        if alsoLog { Sys.log(T(177, subject, "\(who)@\(host) \u{00B7} \(f.string(from: Date()))")) }
        WebhookSender.send(text)
    }
}
