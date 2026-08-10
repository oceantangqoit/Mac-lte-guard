// 窗体排版常量与工厂方法
import Cocoa

enum UI {
    /// 内容宽度。定 480：容得下命令编辑框里的等宽命令，
    /// 又不超出对话框正文的可读行宽——再宽，眼睛回行就开始费劲
    static let W: CGFloat = 480
    static let gap: CGFloat = 8          // 相邻控件
    static let group: CGFloat = 24       // 分组之间：留白就是分组，胜过画线
    static let ctrlH: CGFloat = 26       // 下拉、按钮
    static let fieldH: CGFloat = 24      // 输入框
    static let rowH: CGFloat = 24        // 勾选行
    static let labelH: CGFloat = 16

    /// 分组标题：加粗小字、次级色。靠字重而非字号拉开层次，省空间
    static func section(_ s: String, y: CGFloat, width: CGFloat = W) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 0, y: y, width: width, height: labelH)
        return l
    }

    /// 正文标签：与控件同一档字号，并排时基线才齐
    static func body(_ s: String, y: CGFloat, width: CGFloat = W) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.frame = NSRect(x: 0, y: y, width: width, height: labelH)
        return l
    }

    /// 附注：更小、更淡、可折行。说明性文字不该与正文抢注意力
    static func note(_ s: String, y: CGFloat, width: CGFloat = W, height: CGFloat = 52) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: 10)
        l.textColor = .tertiaryLabelColor
        l.frame = NSRect(x: 0, y: y, width: width, height: height)
        return l
    }

    /// 悬停提示折行。一句话不折，toolTip 会铺成一长条顶出屏幕，
    /// 越是要紧的说明越看不全。按显示宽度折——汉字算两格，拉丁算一格
    static func tip(_ s: String, cols: Int = 30) -> String {
        var out = "", line = 0
        for ch in s {
            if ch == "\n" { out.append(ch); line = 0; continue }
            let w = ch.isASCII ? 1 : 2
            if line + w > cols, ch != "，", ch != "。", ch != "、" {
                out.append("\n"); line = 0
            }
            out.append(ch); line += w
        }
        return out
    }

    /// 带边框的滚动列表：勾选项多时统一这一种容器
    static func list(height: CGFloat, width: CGFloat = W) -> NSScrollView {
        let s = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        s.hasVerticalScroller = true
        s.borderType = .bezelBorder
        s.autohidesScrollers = true
        return s
    }
}
