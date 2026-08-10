import Cocoa
import IOKit
import IOKit.usb

// MARK: - 系统操作

enum Sys {
    @discardableResult
    static func run(_ cmd: String, wait: Bool = true) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        if !wait { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var logPath: String { I18n.appSupportDir + "/lte-guard.log" }

    /// IOKit 默认端口。kIOMainPortDefault（12+）与 kIOMasterPortDefault（已废弃）
    /// 的值都是 0，用命名常量同时兼容新旧系统
    static let ioDefaultPort: mach_port_t = 0

    /// 打开「系统设置 → 网络」——macOS 13 起是 x-apple URL，
    /// 更早的系统只认 prefPane 路径（在 13+ 上反而会落到 Wi-Fi 页）
    static var openNetworkPaneCmd: String {
        if #available(macOS 13.0, *) {
            return "open \"x-apple.systempreferences:com.apple.Network-Settings.extension\""
        }
        return "open -b com.apple.systempreferences /System/Library/PreferencePanes/Network.prefPane"
    }

    /// 该行是否为「打开网络面板」命令（任一历史变体）。
    /// 迁移去重、执行时替换共用这一份判定，新增变体只改这里
    static func isNetworkPaneCmd(_ line: String) -> Bool {
        line.contains("Network-Settings.extension") || line.contains("Network.prefPane")
    }

    /// 执行用户配置的命令前逐行解析：配置里可能存着在其他系统版本上写入的
    /// 网络面板命令变体（配置会跟着系统升级走），执行时刻替换为当前系统的
    /// 正确形式——版本分支挂在执行层，持久化的字符串形态就无所谓了
    static func resolveUserCmds(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                isNetworkPaneCmd(String(line)) ? openNetworkPaneCmd : String(line)
            }
            .joined(separator: "\n")
    }

    /// 执行用户命令：含 --snap 的行走 App 进程内拍照（快，不起第二实例），
    /// 其余合并交给 shell。用户手写的 $(… --snap) 组合行含命令替换符，
    /// 不拆——整行交 shell 由 CLI 模式接住
    @discardableResult
    static func runUserCmds(_ text: String, wait: Bool, prefix: String = "") -> String {
        var shellLines: [String] = []
        var snapTags: [String] = []
        for raw in resolveUserCmds(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("--snap") && !t.contains("$(") {
                snapTags.append(t.contains("restored") ? "restored" : (t.contains("wake") ? "wake" : "snap"))
            } else if !t.isEmpty {
                shellLines.append(line)
            }
        }
        for tag in snapTags {
            if wait {
                // 等照片真正落盘再跑 shell，并记住本次的实际路径——
                // 图文 webhook 只用这些路径，绝不去"找最新文件"（那会捞到旧照）
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    CameraSnap.take(tag: tag) { p in
                        if let p = p { CameraSnap.recordShot(tag, p) }
                        sem.signal()
                    }
                }
                _ = sem.wait(timeout: .now() + 8)   // 含曝光收敛等待
            } else {
                // 断联阶段：拍照与打开网络面板并行，互不拖累
                DispatchQueue.main.async {
                    CameraSnap.take(tag: tag) { p in if let p = p { CameraSnap.recordShot(tag, p) } }
                }
            }
        }
        guard !shellLines.isEmpty else { return "" }
        // 本次拍到什么就给什么；没拍到则为空，命令里会自动退化为纯文本
        let imgs = "LTE_IMG1='\(CameraSnap.lastShots["wake"] ?? "")'; "
                 + "LTE_IMG2='\(CameraSnap.lastShots["restored"] ?? "")'; "
        return run(prefix + imgs + shellLines.joined(separator: "\n"), wait: wait)
    }

    /// 一次性迁移：配置与日志的真身从家目录隐藏文件搬到标准
    /// Application Support 目录（此前那里只放替身）。历史日志保留。
    static func migrateLegacyFiles() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: I18n.appSupportDir, withIntermediateDirectories: true)
        for (old, new) in [(NSHomeDirectory() + "/.lte-guard.conf", Config.path),
                           (NSHomeDirectory() + "/.lte-wake.log", logPath)] {
            guard fm.fileExists(atPath: old) else { continue }
            // 新位置若是此前放的替身，先删替身再搬真身
            if let t = (try? fm.attributesOfItem(atPath: new))?[.type] as? FileAttributeType,
               t == .typeSymbolicLink {
                try? fm.removeItem(atPath: new)
            }
            if !fm.fileExists(atPath: new) { try? fm.moveItem(atPath: old, toPath: new) }
        }
        // v2.8 短暂用过中文目录名「门卫室」，统一为 gatehouse
        let oldSnap = I18n.appSupportDir + "/门卫室"
        if fm.fileExists(atPath: oldSnap) && !fm.fileExists(atPath: CameraSnap.dir) {
            try? fm.moveItem(atPath: oldSnap, toPath: CameraSnap.dir)
        }
    }

    /// usbreset 可执行文件：优先 App 内置资源，回退用户目录（兼容早期手工安装）
    static var usbresetPath: String {
        if let r = Bundle.main.resourcePath {
            let bundled = r + "/usbreset"
            if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        }
        return NSHomeDirectory() + "/.local/bin/usbreset"
    }

    static func log(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(msg)\n"
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            try? FileManager.default.createDirectory(atPath: I18n.appSupportDir, withIntermediateDirectories: true)
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    /// 枚举网络服务 -> [(服务名, 接口名)]
    static func networkServices() -> [(String, String)] {
        let out = run("networksetup -listnetworkserviceorder")
        var result: [(String, String)] = []
        var svc = ""
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            if line.hasPrefix("(") , let r = line.range(of: ") ") {
                svc = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if line.contains("Hardware Port:"),
                      let r = line.range(of: "Device: ") {
                let dev = String(line[r.upperBound...]).replacingOccurrences(of: ")", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !svc.isEmpty && !dev.isEmpty { result.append((svc, dev)) }
            }
        }
        return result
    }

    /// 枚举所有已连接的 USB 设备 -> [(vid, pid, 显示名)]
    /// USB 设备的用途分类。分类决定了「能不能自动拔插」这件事：
    /// 存储与影像设备正在读写时被拔插会丢数据，只该手工重置；
    /// 网络与调制解调器正是本工具要守护的对象。
    enum USBKind: Int {
        case network = 0   // 网络、调制解调器——自动守护的正主
        case other   = 1   // 键鼠、音视频、打印机等
        case data    = 2   // 存储、相机——数据类，自动拔插有丢数据之虞
        case hub     = 3   // 集线器——复位它等于把下游全部复位一遍

        /// 排序权重即列表次序：正主在前，有风险的垫后
        var rank: Int { rawValue }
        /// 是否该在界面上标红劝阻。集线器与数据类风险不同，但都不宜自动守护：
        /// 数据类是自身在读写，集线器是替下游背了这个风险
        var risky: Bool { self == .data || self == .hub }
        /// 劝阻的缘由。标题只能短，缘由长，挂在悬停提示里——要看才看
        var why: Int? { self == .data ? 221 : self == .hub ? 222 : nil }
    }

    /// 由 USB 类代码判定用途。设备类为 0（按接口定）或 0xEF（复合设备）时，
    /// 必须往下看接口类才作数——LTE 模块多是复合设备，只看设备类会漏判。
    private static func kind(ofClass dc: Int, interfaces ic: [Int]) -> USBKind {
        // 集线器先认出来：它下面可以挂任何东西——移动硬盘、读卡器、采集卡。
        // 复位集线器等于把下游全部拔插一遍，风险不由它自己决定，
        // 而由用户往上插了什么决定，所以一律不建议自动守护
        if dc == 0x09 || ic.contains(0x09) { return .hub }
        let all = (dc == 0x00 || dc == 0xEF) ? ic : [dc] + ic
        // 一台设备可能兼具多种接口（如带读卡器的模块）：只要沾了存储/影像，
        // 就按数据类对待——宁可少守护一个，不可丢一份数据
        if all.contains(0x08) || all.contains(0x06) { return .data }
        if all.contains(0x02) || all.contains(0x0A) { return .network }
        return .other
    }

    static func usbDevices() -> [(String, String, String, USBKind)] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(Sys.ioDefaultPort,
                IOServiceMatching(kIOUSBDeviceClassName), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var out: [(String, String, String, USBKind)] = []
        while case let dev = IOIteratorNext(iter), dev != 0 {
            defer { IOObjectRelease(dev) }
            func prop(_ k: String) -> Any? {
                IORegistryEntryCreateCFProperty(dev, k as CFString, nil, 0)?.takeRetainedValue()
            }
            guard let v = prop("idVendor") as? Int, let p = prop("idProduct") as? Int else { continue }
            let name = (prop("USB Product Name") as? String)
                ?? (prop("USB Vendor Name") as? String)
                ?? String(format: "%04x:%04x", v, p)
            let dc = prop("bDeviceClass") as? Int ?? 0
            out.append((String(format: "%04x", v), String(format: "%04x", p), name,
                        kind(ofClass: dc, interfaces: interfaceClasses(of: dev))))
        }
        // 先按用途，再按名字：网络类在最前，数据类沉到最后
        return out.sorted {
            $0.3.rank != $1.3.rank ? $0.3.rank < $1.3.rank
                                   : $0.2.localizedStandardCompare($1.2) == .orderedAscending
        }
    }

    /// 递归取该设备下所有接口的 bInterfaceClass。接口挂在设备的子节点上，
    /// 中间可能隔着若干层驱动节点，故子树要走一遍——但**遇到下游 USB 设备
    /// 必须止步**：集线器的子树里挂着所有下游设备，穿过去就会把下游的接口
    /// 算到集线器头上，把集线器误判成网卡。
    private static func interfaceClasses(of dev: io_object_t) -> [Int] {
        var kids: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(dev, kIOServicePlane, &kids) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(kids) }
        var out: [Int] = []
        while case let k = IOIteratorNext(kids), k != 0 {
            defer { IOObjectRelease(k) }
            // 另一台设备的地界，到此为止
            if IOObjectConformsTo(k, "IOUSBHostDevice") != 0
                || IOObjectConformsTo(k, "IOUSBDevice") != 0 { continue }
            if let c = IORegistryEntryCreateCFProperty(k, "bInterfaceClass" as CFString, nil, 0)?
                .takeRetainedValue() as? Int { out.append(c) }
            // 最硬的证据：设备真的在系统里挂出了 enX 网络接口。
            // 描述符里的类代码是厂商「声称」的，enX 是系统「认下」的——
            // 认下的比声称的可信，凡挂得出 enX 的一律按网络类算
            if IOObjectConformsTo(k, "IONetworkInterface") != 0,
               let bsd = IORegistryEntryCreateCFProperty(k, "BSD Name" as CFString, nil, 0)?
                   .takeRetainedValue() as? String,
               bsd.hasPrefix("en"), bsd.dropFirst(2).allSatisfy(\.isNumber) {
                out.append(0x02)
            }
            // 存储设备会在子树里挂出 IOMedia——这是「有数据在上面」的铁证
            if IOObjectConformsTo(k, "IOMedia") != 0 { out.append(0x08) }
            out += interfaceClasses(of: k)
        }
        return out
    }

    /// 接口 -> USB (VID, PID)，非 USB 返回 nil
    static func usbIDs(for bsd: String) -> (String, String)? {
        guard let match = IOServiceMatching("IONetworkInterface") as NSMutableDictionary? else { return nil }
        match["BSD Name"] = bsd
        let svc = IOServiceGetMatchingService(Sys.ioDefaultPort, match as CFDictionary)
        guard svc != 0 else { return nil }
        var cur = svc
        for _ in 0..<12 {
            let v = IORegistryEntryCreateCFProperty(cur, "idVendor" as CFString, nil, 0)?
                .takeRetainedValue() as? Int
            let p = IORegistryEntryCreateCFProperty(cur, "idProduct" as CFString, nil, 0)?
                .takeRetainedValue() as? Int
            if let v = v, let p = p {
                return (String(format: "%04x", v), String(format: "%04x", p))
            }
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(cur, kIOServicePlane, &parent) != KERN_SUCCESS { break }
            cur = parent
        }
        return nil
    }

    /// 接口是否还在系统里。USB 网卡假死时接口整个消失，这是硬故障的标志，
    /// 与「接口在、只是还没拿到 IP」（DHCP 未完成）截然不同，不该混为一谈。
    static func interfaceExists(_ dev: String) -> Bool {
        run("ifconfig \(dev) >/dev/null 2>&1 && echo y") == "y"
    }

    static func interfaceHealthy(_ dev: String) -> Bool {
        let hasIP = run("ifconfig \(dev) 2>/dev/null | grep -q 'inet ' && echo y") == "y"
        guard hasIP else { return false }
        var gw = run("ipconfig getoption \(dev) router 2>/dev/null")
        if gw.isEmpty {
            gw = run("netstat -rn -f inet | awk '$1==\"default\" && $NF==\"\(dev)\" {print $2; exit}'")
        }
        guard !gw.isEmpty else { return false }
        // 局域网关正常 <10ms 应答，1 秒超时足够；假死时快速失败让修复更早启动
        return run("ping -c 1 -t 1 -b \(dev) \(gw) >/dev/null 2>&1 && echo y") == "y"
    }
}
