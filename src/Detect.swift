import Cocoa

// MARK: - 环境探测（用于「恢复后执行命令」的动态勾选项）

/// 一条可勾选的命令。程序添加的行会带 #lteguard 标记，
/// 以便与用户手写的内容严格区分——用户手写的行程序永不删除。
struct PresetCmd {
    let title: String       // 勾选框显示文字
    var command: String     // 实际命令（不含标记）；可变——如提示音预设随选择的声音更新
    let hint: String        // 宽松匹配用的关键字；为空则只做精确匹配
    var tooltip: String = ""
    var pre = false         // true = 写入「发现断联时执行」，false = 「恢复后执行」
}

enum Detect {
    static let mark = "#lteguard"

    /// 扫描用户 LaunchAgent，找出参数中提到指定网络接口的服务。
    /// 这样不论用户用的是 gost、v2ray、clash 还是自写脚本，只要绑定了
    /// 这块网卡就能被发现，无需在代码里硬编码任何工具名。
    static func agentsBound(to dev: String) -> [(label: String, reason: String)] {
        guard !dev.isEmpty else { return [] }
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [(String, String)] = []
        for f in files where f.hasSuffix(".plist") {
            guard let text = try? String(contentsOfFile: dir + "/" + f, encoding: .utf8) else { continue }
            // 跳过本程序自己
            guard !text.contains("com.oceantang.lteguard") else { continue }
            // 参数里出现 interface=en2 / %en2 / 独立的 en2 才算绑定
            let patterns = ["interface=\(dev)", "%\(dev)", "bind=\(dev)", "dev=\(dev)", "-i \(dev)"]
            guard patterns.contains(where: { text.contains($0) }) else { continue }
            let label = (f as NSString).deletingPathExtension
            out.append((label, dev))
        }
        return out
    }

    /// 已挂载的网络卷（SMB / NFS / AFP / WebDAV）
    static func networkVolumes() -> [String] {
        let out = Sys.run("mount | awk '/smbfs|nfs|afpfs|webdav/ {for(i=1;i<=NF;i++) if($i==\"on\"){print $(i+1); break}}'")
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// 正在运行的 VPN 类进程
    static func vpnProcesses() -> [String] {
        var found: [String] = []
        for (proc, name) in [("tailscaled", "Tailscale"), ("wireguard-go", "WireGuard"),
                             ("openvpn", "OpenVPN"), ("com.wireguard", "WireGuard")] {
            if Sys.run("pgrep -x \(proc) >/dev/null 2>&1 && echo y") == "y", !found.contains(name) {
                found.append(name)
            }
        }
        return found
    }

    /// 正在运行的、依赖网络的同步/下载类 App
    static func networkApps() -> [(name: String, bundleID: String)] {
        let known: [String: String] = [
            "com.synology.SynologyDrive": "Synology Drive",
            "com.synology.CloudStation": "Synology Drive",
            "com.getdropbox.dropbox": "Dropbox",
            "com.microsoft.OneDrive": "OneDrive",
            "com.jianguoyun.nutstore": "Nutstore",
            "org.m0k.transmission": "Transmission",
            "org.qbittorrent.qBittorrent": "qBittorrent",
            "com.baidu.BaiduNetdisk": "Baidu Netdisk",
        ]
        var out: [(String, String)] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, let name = known[bid] else { continue }
            if !out.contains(where: { $0.1 == bid }) { out.append((name, bid)) }
        }
        return out
    }
}
