import Cocoa

// MARK: - 「恢复后执行命令」对话框

/// 勾选项与命令文本的双向实时同步控制器。
///
/// 所有权规则（重要）：程序添加的行末尾带 `#lteguard` 标记，取消勾选时只删
/// 带标记的行；**用户手写的行程序永不触碰**，只能由用户自己删除。因此勾选框
/// 有三种状态：
///   - on     该命令存在且由程序添加（可通过取消勾选移除）
///   - mixed  该命令存在但是用户手写的（勾选框置灰，仅提示不可自动移除）
///   - off    不存在
final class PostCmdEditor: NSObject, NSTextViewDelegate {
    private let preTV: NSTextView    // 「发现断联时执行」
    private let postTV: NSTextView   // 「恢复后执行」
    private var boxes: [(NSButton, PresetCmd)] = []
    private var syncing = false
    /// 勾选前的放行检查（如摄像头权限）。返回 false 则本次不勾；
    /// 检查方可在异步授权成功后再 performClick 该按钮补勾
    var willEnable: ((PresetCmd, NSButton) -> Bool)?
    /// 文本或勾选发生任何变化后的回调（如刷新「图文」可用性）
    var onChange: (() -> Void)?

    init(preTV: NSTextView, postTV: NSTextView) {
        self.preTV = preTV
        self.postTV = postTV
        super.init()
        preTV.delegate = self
        postTV.delegate = self
    }

    /// 每个预设归属其中一个文本框，由 preset.pre 决定
    private func tv(for p: PresetCmd) -> NSTextView { p.pre ? preTV : postTV }

    func register(_ button: NSButton, _ preset: PresetCmd) {
        button.target = self
        button.action = #selector(toggled(_:))
        button.allowsMixedState = true
        boxes.append((button, preset))
    }

    var currentPre: String { preTV.string }
    var currentPost: String { postTV.string }

    /// 依据文本内容刷新所有勾选框状态
    func refreshBoxes() {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        for (btn, p) in boxes {
            let lines = tv(for: p).string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var state: NSControl.StateValue = .off
            for raw in lines {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                let tagged = line.hasSuffix(Detect.mark)
                let body = tagged
                    ? String(line.dropLast(Detect.mark.count)).trimmingCharacters(in: .whitespaces)
                    : line
                let hit = (body == p.command) || (!p.hint.isEmpty && line.contains(p.hint))
                guard hit else { continue }
                // 带标记 = 程序所加，可取消；无标记 = 用户手写，仅提示
                state = tagged ? .on : .mixed
                if state == .mixed { break }   // 手写优先，不再被后续行覆盖
            }
            btn.state = state
            btn.isEnabled = (state != .mixed)   // 手写的置灰，避免误以为能点掉
            if state == .mixed && btn.toolTip == nil { btn.toolTip = p.tooltip }
        }
    }

    /// 勾选/取消 → 立即改写文本（所勾即所得）
    ///
    /// 注意：不能依据 sender.state 判断意图——allowsMixedState 会让点击循环变成
    /// off→mixed→on，第一跳落在 .mixed 上，永远走不到 .on。因此这里改为从
    /// 文本内容推导：已有带标记的行→本次点击=取消；没有→本次点击=勾选。
    /// 最终显示状态交给 refreshBoxes() 统一校正。
    @objc private func toggled(_ sender: NSButton) {
        guard let idx = boxes.firstIndex(where: { $0.0 === sender }) else { return }
        let p = boxes[idx].1
        let target = tv(for: p)
        syncing = true
        var lines = target.string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let hasTagged = lines.contains { Self.taggedMatches($0, p) }

        if !hasTagged {
            if let gate = willEnable, !gate(p, sender) {
                syncing = false
                refreshBoxes()   // 权限未就绪：状态回弹为未勾
                return
            }
            let entry = "\(p.command)   \(Detect.mark)"
            if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == entry }) {
                while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
                lines.append(entry)
            }
        } else {
            // 只删带标记的行——用户手写的同名行原样保留
            lines.removeAll { Self.taggedMatches($0, p) }
        }
        target.string = lines.joined(separator: "\n")
        syncing = false
        refreshBoxes()
        onChange?()
    }

    /// 该行是否为「程序添加的、属于此预设」的行。
    /// tagged 行是程序自己写的，按 hint 宽松匹配是安全的——
    /// 这让"命令可变"的预设（如换了声音的提示音）也能被正确识别和取消
    private static func taggedMatches(_ raw: String, _ p: PresetCmd) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasSuffix(Detect.mark) else { return false }
        let body = String(line.dropLast(Detect.mark.count)).trimmingCharacters(in: .whitespaces)
        return body == p.command || (!p.hint.isEmpty && body.contains(p.hint))
    }

    /// 预设的命令变了（如用户换了提示音）：更新注册表；若该预设当前已勾选
    /// （文本框里有它的 tagged 行），就地替换为新命令，保持勾选状态
    func updateCommand(for button: NSButton, to newCommand: String) {
        guard let idx = boxes.firstIndex(where: { $0.0 === button }) else { return }
        let old = boxes[idx].1
        boxes[idx].1.command = newCommand
        let p = boxes[idx].1
        let target = tv(for: p)
        var lines = target.string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var replaced = false
        for i in lines.indices where Self.taggedMatches(lines[i], old) {
            lines[i] = "\(newCommand)   \(Detect.mark)"
            replaced = true
        }
        if replaced {
            syncing = true
            target.string = lines.joined(separator: "\n")
            syncing = false
        }
        refreshBoxes()
    }

    /// 用户手动编辑文本 → 勾选框状态跟着变
    func textDidChange(_ notification: Notification) { refreshBoxes(); onChange?() }
}
