// LTE Guard — 菜单栏常驻 App
// AppDelegate: 菜单栏、菜单构建、用户交互、生命周期
import Cocoa
import IOKit
import UserNotifications
import AVFoundation


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
        // 取某个语言的某几条文案。排查「用户自己的语言文件缺了新键」
        // 这类问题时用得上：分层加载是否真的补上了，一看便知
        if let i = CommandLine.arguments.firstIndex(of: "--key") {
            let rest = CommandLine.arguments.dropFirst(i + 1)
            let lang = rest.first ?? "en"
            I18n.shared.load(preferred: lang)
            for a in rest.dropFirst() {
                guard let k = Int(a) else { continue }
                print("\(k)= \(T(k))")
            }
            exit(0)
        }
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
        DispatchQueue.global(qos: .background).async { Updater.writeChangelog() }  // 启动即拉更新说明，不等用户点
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
        LaunchAtLogin.reconcilePlistIfNeeded()
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
        // 「唤醒后自动修复」此前一直在发详尽推送，只是不受勾选控制。
        // 把它加进通报清单是为了给用户开关，不是为了悄悄关掉——
        // 老配置一律补上这一项，行为保持原样
        if !UserDefaults.standard.bool(forKey: "autohealOptMigrated") {
            UserDefaults.standard.set(true, forKey: "autohealOptMigrated")
            var c = Config.load()
            if !c.whURL.isEmpty, !c.notifyOps.contains("autoheal") {
                c.notifyOps.insert("autoheal"); c.save()
            }
        }
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

        // 活动感知：若用户之前已开启，启动定时采样写 CSV
        ActivitySense.shared.startCSVRecording()
        // 外置插件：上次在跑的自动拉起，不用每次手工开
        PluginCenter.restoreAll()
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

        // ── 插件 ▸（三个插件各一个子菜单，独立于「设置」）──
        m.addItem(pluginItem())

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

    /// 活动感知子菜单：模式三选一 + CSV 文件路径
    private func activitySenseItem() -> NSMenuItem {
        let cfg = Config.load()
        let ai = item(T(253), nil, symbol: "waveform")
        let am = sub()
        for (mode, title) in [(0, T(254)), (1, T(255)), (2, T(256))] {
            let mi = NSMenuItem(title: title, action: #selector(setActivitySense(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = mode
            mi.state = (cfg.activitySense == mode) ? .on : .off
            am.addItem(mi)
        }
        am.addItem(.separator())
        let csvItem = NSMenuItem(title: T(257), action: #selector(pickActivityCSV), keyEquivalent: "")
        csvItem.target = self
        if !cfg.activityCSV.isEmpty {
            csvItem.toolTip = cfg.activityCSV
            csvItem.title = T(258) + " " + (cfg.activityCSV as NSString).lastPathComponent
        }
        am.addItem(csvItem)
        // 清除记录文件
        if !cfg.activityCSV.isEmpty {
            let clr = NSMenuItem(title: T(259), action: #selector(clearActivityCSV), keyEquivalent: "")
            clr.target = self
            am.addItem(clr)
        }
        ai.submenu = am
        return ai
    }

    /// 插件 ▸ 顶层菜单：设置面板 + 插件1 活动感知（内建）＋ 插件2/3/4（外置程序启动控制）
    private func pluginItem() -> NSMenuItem {
        let pi = item(T(260), nil, symbol: "square.grid.2x2")
        let pm = sub()
        // 插件设置面板：输出文件夹、DDNS 参数、运行状态总览
        pm.addItem(item(T(273), #selector(showPluginPanel), symbol: "gear"))
        pm.addItem(.separator())
        // 插件1：活动感知（已内建，界面在子菜单里）
        pm.addItem(activitySenseItem())
        // 插件3：原始采集器
        pm.addItem(pluginRunnerItem(
            id: .raw, title: T(262), symbol: "record.circle",
            startTitle: T(270), startSel: #selector(startRawRecorder),
            stopSel: #selector(stopRawRecorder), openSel: #selector(openRawDir)))
        // 插件2：律师日志
        pm.addItem(pluginRunnerItem(
            id: .lawyer, title: T(263), symbol: "briefcase",
            startTitle: T(271), startSel: #selector(startLawyerLog),
            stopSel: #selector(stopLawyerLog), openSel: #selector(openLawyerDir)))
        // 插件4：Cloudflare DDNS
        pm.addItem(pluginRunnerItem(
            id: .ddns, title: T(276), symbol: "network",
            startTitle: T(266), startSel: #selector(startDDNS),
            stopSel: #selector(stopDDNS), openSel: #selector(openDDNSDir)))
        pi.submenu = pm
        return pi
    }

    /// 外置插件的通用子菜单：运行状态 + 启动/停止 + 打开输出目录
    private func pluginRunnerItem(id: PluginID, title: String, symbol: String,
                                  startTitle: String, startSel: Selector,
                                  stopSel: Selector, openSel: Selector) -> NSMenuItem {
        let ii = item(title, nil, symbol: symbol)
        let mm = sub()
        let running = PluginCenter.running(id)
        let st = NSMenuItem(title: running ? T(264) : T(265), action: nil, keyEquivalent: "")
        st.isEnabled = false
        st.state = running ? .on : .off
        mm.addItem(st)
        mm.addItem(.separator())
        if PluginCenter.built(id) {
            mm.addItem(item(startTitle, startSel, symbol: "play.fill"))
            mm.addItem(item(T(267), stopSel, symbol: "stop.fill"))
        } else {
            let nb = NSMenuItem(title: T(269), action: nil, keyEquivalent: "")
            nb.isEnabled = false
            mm.addItem(nb)
        }
        mm.addItem(item(T(268), openSel, symbol: "folder"))
        ii.submenu = mm
        return ii
    }

    @objc func showPluginPanel() { PluginPanel.shared.show() }

    // MARK: 插件3 原始采集器控制

    @objc func startRawRecorder() { PluginCenter.start(.raw); rebuildMenu() }
    @objc func stopRawRecorder() { PluginCenter.stop(.raw); rebuildMenu() }
    @objc func openRawDir() { openPluginDir(.raw) }

    // MARK: 插件2 律师日志控制

    @objc func startLawyerLog() { PluginCenter.start(.lawyer); rebuildMenu() }
    @objc func stopLawyerLog() { PluginCenter.stop(.lawyer); rebuildMenu() }
    @objc func openLawyerDir() { openPluginDir(.lawyer) }

    // MARK: 插件4 Cloudflare DDNS 控制

    @objc func startDDNS() {
        // 参数不全直接带去设置面板，比弹个错误让人自己找入口强
        guard PluginCenter.ddnsConfig().complete else {
            let a = NSAlert()
            a.messageText = T(276)
            a.informativeText = T(284)
            a.addButton(withTitle: T(17))
            a.runModal()
            showPluginPanel()
            return
        }
        PluginCenter.start(.ddns)
        rebuildMenu()
    }
    @objc func stopDDNS() { PluginCenter.stop(.ddns); rebuildMenu() }
    @objc func openDDNSDir() { openPluginDir(.ddns) }

    private func openPluginDir(_ id: PluginID) {
        let dir = PluginCenter.outDir(id)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    /// 重建菜单（动作后刷新状态显示）
    private func rebuildMenu() {
        buildMenu()
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

        let before = Set(cfg.targets.map(\.dev))
        var picked: [Target] = []
        for (i, (svc, dev)) in services.enumerated() where boxes[i].state == .on {
            var t = Target(dev: dev, service: svc)
            if let (v, p) = Sys.usbIDs(for: dev) { t.vid = v; t.pid = p }
            picked.append(t)
        }
        let after = Set(picked.map(\.dev))
        guard before != after else { return }
        let added = picked.filter { !before.contains($0.dev) }.map(\.display)
        let removed = cfg.targets.filter { !after.contains($0.dev) }.map(\.display)
        cfg.targets = picked
        cfg.save()
        var parts: [String] = []
        if !added.isEmpty { parts.append(T(243, added.joined(separator: "、"))) }
        if !removed.isEmpty { parts.append(T(244, removed.joined(separator: "、"))) }
        OpsNotify.report("target", parts.isEmpty ? "—" : parts.joined(separator: "、"))
        let names = picked.map(\.display).joined(separator: ", ")
        Sys.log(T(109, names))
        notify(T(109, names))
        refreshIcon()
    }

    @objc func switchLang(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        let wasRTL = UserDefaults.standard.bool(forKey: "NSForceRightToLeftWritingDirection")
        let nowRTL = I18n.isRTL(code)
        let was = I18n.shared.code
        I18n.shared.load(preferred: code)
        SettingsAudit.record(T(13), [(T(13), was, code)])
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
        SettingsAudit.record(T(48), [(T(48), IconMode.current.title, mode.title)])
        IconMode.current = mode
        refreshIcon()
    }

    // MARK: 活动感知

    @objc func setActivitySense(_ sender: NSMenuItem) {
        var cfg = Config.load()
        cfg.activitySense = sender.tag
        cfg.save()
        // 切到 off → 停 timer；否则重启 timer
        if cfg.activitySense == 0 {
            ActivitySense.shared.stopCSVRecording()
        } else {
            ActivitySense.shared.startCSVRecording()
        }
        OpsNotify.report("settings", cfg.activitySense == 0 ? T(254) :
            (cfg.activitySense == 1 ? T(255) : T(256)))
        refreshIcon()
    }

    @objc func pickActivityCSV() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["csv"]
        panel.title = T(257)
        let cfg = Config.load()
        if !cfg.activityCSV.isEmpty { panel.directoryURL = URL(fileURLWithPath: cfg.activityCSV) }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var c = Config.load()
        c.activityCSV = url.path
        c.save()
        if c.activitySense != 0 { ActivitySense.shared.startCSVRecording() }
        refreshIcon()
    }

    @objc func clearActivityCSV() {
        var c = Config.load()
        c.activityCSV = ""
        c.save()
        ActivitySense.shared.stopCSVRecording()
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
            func lines(_ s: String) -> Int { s.split(separator: "\n").filter { !$0.isEmpty }.count }
            let oldPN = lines(oldPre), newPN = lines(cfg.preCmd)
            let oldOpN = lines(oldPost), newOpN = lines(cfg.postCmd)
            var parts: [String] = []
            if oldPN != newPN { parts.append(T(245, "\(oldPN)", "\(newPN)")) }
            if oldOpN != newOpN { parts.append(T(246, "\(oldOpN)", "\(newOpN)")) }
            OpsNotify.report("editcmd", parts.isEmpty ? "—" : parts.joined(separator: "；"))
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
            let added = picked.filter { g in !before.contains("\(g.vid):\(g.pid)") }
            let removed = cfg.usbGuards.filter { g in !after.contains("\(g.vid):\(g.pid)") }
            cfg.usbGuards = picked
            cfg.save()
            var parts: [String] = []
            if !added.isEmpty { parts.append(T(243, added.map(\.name).joined(separator: "、"))) }
            if !removed.isEmpty { parts.append(T(244, removed.map(\.name).joined(separator: "、"))) }
            OpsNotify.report("usb", parts.isEmpty ? "—" : parts.joined(separator: "、"))
            let names = picked.isEmpty ? "—" : picked.map(\.name).joined(separator: "、")
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
        let box = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 178))
        box.addSubview(UI.body(T(64), y: 158))      // 作者
        box.addSubview(UI.body(T(241), y: 138))     // 合作开发
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
        let oldIvName = T(Updater.intervalChoices
            .firstIndex { $0.0 == cfg.updateInterval }.map { Updater.intervalChoices[$0].1 } ?? 199)
        SettingsAudit.record(T(180), [
            (T(198), oldIvName, T(Updater.intervalChoices[sel].1)),
            (T(197), SettingsAudit.onOff(cfg.silentInstall), SettingsAudit.onOff(auto.state == .on)),
            (T(169), SettingsAudit.onOff(Updater.autoCheck), SettingsAudit.onOff(daily.state == .on)),
        ])
        cfg.updateInterval = picked
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
        let oldPlatform = cfg.whPlatform, oldRich = cfg.whRich
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
            if cfg.notifyOps != oldOps {
                let added = cfg.notifyOps.subtracting(oldOps)
                let removed = oldOps.subtracting(cfg.notifyOps)
                var parts: [String] = []
                if !added.isEmpty { parts.append(T(243, added.map { OpsNotify.name($0) }.sorted().joined(separator: "、"))) }
                if !removed.isEmpty { parts.append(T(244, removed.map { OpsNotify.name($0) }.sorted().joined(separator: "、"))) }
                what.append(parts.isEmpty ? T(230, "\(cfg.notifyOps.count)") : parts.joined(separator: "；"))
            }
            OpsNotify.report("notify", what.joined(separator: "、"))
        }
        // 平台与图文这类不涉密的选择，走设置审计留痕（地址仍旧不入）
        SettingsAudit.record(T(184), [
            (T(92), AppDelegate.webhookPlatforms[min(oldPlatform, AppDelegate.webhookPlatforms.count - 1)],
             AppDelegate.webhookPlatforms[min(cfg.whPlatform, AppDelegate.webhookPlatforms.count - 1)]),
            (T(145) + "/" + T(146), oldRich ? T(146) : T(145), cfg.whRich ? T(146) : T(145)),
        ])
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
        // 勾选时已经弹过一次确认，第一次退出再当面说一次就够——
        // 之后都是静默：点退出 → KeepAlive 无声拉起，用户不会觉得「退不掉是故障」
        if LaunchAtLogin.alwaysOn && !LaunchAtLogin.firstExitReminded {
            let a = NSAlert()
            a.messageText = T(225)
            a.informativeText = I18n.shared.paragraph(T(226))
            a.alertStyle = .informational
            a.addButton(withTitle: T(17))
            a.addButton(withTitle: T(18))
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
            LaunchAtLogin.firstExitReminded = true
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
            // 用户确认开启：重置首次退出提醒标记，下次退出时再提醒一次
            LaunchAtLogin.firstExitReminded = false
        }
        LaunchAtLogin.alwaysOn = turningOn
        // 开与关各用各的句子。先前拿 133/134 当通用的「已开启/已关闭」，
        // 那两条是敏感操作验证的专用文案，套到这里就成了驴唇不对马嘴
        SettingsAudit.record(T(226), [(T(226),
            SettingsAudit.onOff(!turningOn), SettingsAudit.onOff(turningOn))])
        notify(T(turningOn ? 227 : 228))
        refreshIcon()
    }

    @objc func toggleAuthGuard() {
        if Auth.guardEnabled {
            Auth.require { [weak self] in
                SettingsAudit.record(T(132), [(T(132), T(239), T(240))])
                Auth.guardEnabled = false
                self?.notify(T(134))
                self?.refreshIcon()
            }
        } else {
            SettingsAudit.record(T(132), [(T(132), T(240), T(239))])
            Auth.guardEnabled = true
            notify(T(133))
            refreshIcon()
        }
    }

    private func notify(_ msg: String) {
        Notifier.post(msg)
    }
}
