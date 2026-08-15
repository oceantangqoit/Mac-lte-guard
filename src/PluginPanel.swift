import Cocoa

// MARK: - 插件设置面板
// 外置插件的统一配置窗口：输出文件夹选择、运行状态与启停、DDNS 参数。
// 状态实时重建（每次 show / 操作后 reload），不缓存——插件进程随时可能被外部杀掉。

final class PluginPanel: NSObject {
    static let shared = PluginPanel()

    private var win: NSPanel?
    private var stack: NSStackView?

    // DDNS 输入框（保存时回读）
    private var tokenF: NSSecureTextField?
    private var zoneF: NSTextField?
    private var recordF: NSTextField?
    private var intervalF: NSTextField?
    private var ttlF: NSTextField?

    func show() {
        if win == nil { build() }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        win?.center()
        win?.makeKeyAndOrderFront(nil)
    }

    // ── 骨架 ──

    private func build() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 100),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = T(273).replacingOccurrences(of: "…", with: "")
        w.isReleasedWhenClosed = false
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.alignment = .leading
        sv.spacing = 14
        sv.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        sv.translatesAutoresizingMaskIntoConstraints = false
        w.contentView?.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: w.contentView!.topAnchor),
            sv.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor),
            sv.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor),
        ])
        win = w
        stack = sv
    }

    /// 清空重建全部内容
    private func reload() {
        guard let sv = stack else { return }
        sv.arrangedSubviews.forEach { sv.removeArrangedSubview($0); $0.removeFromSuperview() }

        sv.addArrangedSubview(section(id: .raw))
        sv.addArrangedSubview(NSBox.separator())
        sv.addArrangedSubview(section(id: .lawyer))
        sv.addArrangedSubview(NSBox.separator())
        sv.addArrangedSubview(ddnsSection())
        sv.addArrangedSubview(NSBox.separator())
        let note = label(T(286), secondary: true)
        note.maximumNumberOfLines = 2
        note.lineBreakMode = .byWordWrapping
        note.preferredMaxLayoutWidth = 520
        sv.addArrangedSubview(note)

        win?.setContentSize(NSSize(width: 560, height: sv.fittingSize.height + 32))
    }

    // ── 采集器 / 律师日志：通用段落 ──

    private func section(id: PluginID) -> NSView {
        let v = vstack(spacing: 8)
        v.addArrangedSubview(titleLabel(PluginCenter.name(id)))

        // 状态 + 启停
        let row = hstack(spacing: 10)
        row.addArrangedSubview(statusLabel(PluginCenter.running(id)))
        row.addArrangedSubview(spacer())
        if PluginCenter.built(id) {
            row.addArrangedSubview(button(T(266), #selector(startPlugin(_:)), tag: id))
            row.addArrangedSubview(button(T(267), #selector(stopPlugin(_:)), tag: id))
        } else {
            row.addArrangedSubview(label(T(269), secondary: true))
        }
        v.addArrangedSubview(row)

        // 输出文件夹
        v.addArrangedSubview(folderRow(id))
        return v
    }

    private func folderRow(_ id: PluginID) -> NSView {
        let row = hstack(spacing: 8)
        row.addArrangedSubview(label(T(274) + "："))
        let f = NSTextField(string: PluginCenter.outDir(id))
        f.isEditable = false; f.isSelectable = true
        f.lineBreakMode = .byTruncatingMiddle
        f.widthAnchor.constraint(equalToConstant: 240).isActive = true
        row.addArrangedSubview(f)
        row.addArrangedSubview(button(T(275), #selector(pickFolder(_:)), tag: id))
        row.addArrangedSubview(button(T(268), #selector(openFolder(_:)), tag: id))
        return row
    }

    // ── Cloudflare DDNS 段落 ──

    private func ddnsSection() -> NSView {
        let v = vstack(spacing: 8)
        v.addArrangedSubview(titleLabel(T(276)))

        // 状态 + 启停
        let row = hstack(spacing: 10)
        row.addArrangedSubview(statusLabel(PluginCenter.running(.ddns)))
        row.addArrangedSubview(spacer())
        if PluginCenter.built(.ddns) {
            row.addArrangedSubview(button(T(266), #selector(startPlugin(_:)), tag: .ddns))
            row.addArrangedSubview(button(T(267), #selector(stopPlugin(_:)), tag: .ddns))
        } else {
            row.addArrangedSubview(label(T(269), secondary: true))
        }
        v.addArrangedSubview(row)

        // 参数表单
        let c = PluginCenter.ddnsConfig()
        let form = NSGridView(numberOfColumns: 2, rows: 0)
        form.rowSpacing = 6; form.columnSpacing = 8
        let tok = NSSecureTextField(string: c.token)
        tokenF = tok
        zoneF = NSTextField(string: c.zone)
        recordF = NSTextField(string: c.record)
        intervalF = NSTextField(string: "\(c.interval)")
        ttlF = NSTextField(string: "\(c.ttl)")
        for (lab, field) in [(T(277), tok as NSTextField), (T(278), zoneF!),
                             (T(279), recordF!), (T(280), intervalF!), (T(285), ttlF!)] {
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
            form.addRow(with: [label(lab + "："), field])
        }
        form.translatesAutoresizingMaskIntoConstraints = false
        v.addArrangedSubview(form)

        let saveRow = hstack(spacing: 8)
        saveRow.addArrangedSubview(button(T(281), #selector(saveDDNS)))
        // 状态摘要：当前公网 IP / 上次更新
        if let st = PluginCenter.ddnsState() {
            saveRow.addArrangedSubview(label(
                "\(T(282))：\(st.ip)　\(T(283))：\(st.update)（\(st.result)）", secondary: true))
        }
        v.addArrangedSubview(saveRow)

        v.addArrangedSubview(folderRow(.ddns))
        return v
    }

    // ── 动作 ──

    /// 用 representedObject 带 PluginID，避免按 tag 猜
    /// 用 identifier 带 PluginID（NSButton 没有 representedObject）
    private func button(_ title: String, _ sel: Selector, tag: PluginID? = nil) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        if let tag = tag { b.identifier = NSUserInterfaceItemIdentifier(tag.rawValue) }
        return b
    }

    private func pluginID(of sender: NSButton) -> PluginID? {
        guard let raw = sender.identifier?.rawValue else { return nil }
        return PluginID(rawValue: raw)
    }

    @objc private func startPlugin(_ sender: NSButton) {
        guard let id = pluginID(of: sender) else { return }
        if id == .ddns, !PluginCenter.ddnsConfig().complete {
            let a = NSAlert()
            a.messageText = T(276)
            a.informativeText = T(284)
            a.addButton(withTitle: T(17))
            a.runModal()
            return
        }
        PluginCenter.start(id)
        reload()
    }

    @objc private func stopPlugin(_ sender: NSButton) {
        guard let id = pluginID(of: sender) else { return }
        PluginCenter.stop(id)
        reload()
    }

    @objc private func pickFolder(_ sender: NSButton) {
        guard let id = pluginID(of: sender) else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: PluginCenter.outDir(id))
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        PluginCenter.setOutDir(id, url.path)
        reload()
    }

    @objc private func openFolder(_ sender: NSButton) {
        guard let id = pluginID(of: sender) else { return }
        let dir = PluginCenter.outDir(id)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    @objc private func saveDDNS() {
        var c = PluginCenter.DDNSConfig()
        c.token = tokenF?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        c.zone = zoneF?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        c.record = recordF?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        c.interval = max(30, Int(intervalF?.stringValue ?? "") ?? 300)
        c.ttl = max(1, Int(ttlF?.stringValue ?? "") ?? 1)
        PluginCenter.saveDDNS(c)
        // 改了参数且正在跑：重启生效
        if PluginCenter.running(.ddns) { PluginCenter.stop(.ddns); PluginCenter.start(.ddns) }
        reload()
    }

    // ── 控件小工厂 ──

    private func vstack(spacing: CGFloat) -> NSStackView {
        let v = NSStackView()
        v.orientation = .vertical; v.alignment = .leading; v.spacing = spacing
        return v
    }

    private func hstack(spacing: CGFloat) -> NSStackView {
        let v = NSStackView()
        v.orientation = .horizontal; v.alignment = .centerY; v.spacing = spacing
        return v
    }

    private func label(_ s: String, secondary: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        if secondary { l.textColor = .secondaryLabelColor; l.font = .systemFont(ofSize: 11) }
        return l
    }

    private func titleLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 13)
        return l
    }

    private func statusLabel(_ running: Bool) -> NSTextField {
        label((running ? "● " : "○ ") + (running ? T(264) : T(265)))
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
}

private extension NSBox {
    static func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }
}
