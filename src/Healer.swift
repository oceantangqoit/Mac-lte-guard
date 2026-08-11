import Cocoa
import IOKit

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
    /// 若被守护的正是网卡所在的那只 USB 设备，先复位反而省了后面一遍。
    /// 复位结果并入 autoheal 汇总通知，不再独立发——同一轮唤醒里
    /// "usb" 和 "autoheal" 都勾了会把同一批设备报两遍
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
        if !done.isEmpty {
            self.infoParts.append(T(242, done.joined(separator: "、")))
        }
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
                    if cfg.notifyOps.contains("autoheal") {
                        var text = T(235, info)
                        let act = ActivitySense.shared.summary()
                        if !act.isEmpty { text += "\n" + T(247, act) }
                        WebhookSender.sendRich(text, images: shots)
                    }
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
