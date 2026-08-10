import Cocoa

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
            WebhookSender.send(T(232, cur, version), sync: true)
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

/// 设置变更的统一去处。两条规矩：
/// 一、**以保存为准**——点开界面看看又取消，不该留下任何痕迹；
/// 二、**只记真变了的**——否则每按一次「确定」都刷一条，日志就成了噪音。
/// 日志无条件写（改了什么总该查得到），推送按「操作通报」的勾选走
enum SettingsAudit {
    static func record(_ scope: String, _ changes: [(String, String, String)]) {
        let real = changes.filter { $0.1 != $0.2 }
        guard !real.isEmpty else { return }
        let detail = real.map { T(237, $0.0, $0.1, $0.2) }.joined(separator: "；")
        Sys.log(T(236, scope, detail))
        OpsNotify.report("settings", "\(scope) — \(detail)", alsoLog: false)
    }
    /// 开关类的值统一措辞，免得各处各写各的
    static func onOff(_ v: Bool) -> String { v ? T(239) : T(240) }
}
