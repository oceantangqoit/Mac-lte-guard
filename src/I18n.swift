// 多语言（数字键 INI）
// 文案全部走数字代码，语言文件在 App 内 Resources/lang/*.ini，
// 用户自定义可放 ~/.lte-guard-lang/*.ini（同名覆盖内置）。
import Cocoa

final class I18n {
    static let shared = I18n()
    private var table: [Int: String] = [:]
    private(set) var code: String = ""

    /// 可选语言列表 [(文件代码, 显示名)]
    var available: [(String, String)] {
        var found: [String: String] = [:]
        for dir in I18n.searchDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".ini") && !f.hasSuffix(".template.ini") {
                let c = String(f.dropLast(4))
                if found[c] == nil { found[c] = I18n.metaName(dir + "/" + f) ?? c }
            }
        }
        // 排序：汉语及其方言 → 中国少数民族语言 → 其他（按代码）
        let priority = [
            // 汉语及其方言
            // 文言紧随简繁体之后：它是汉语的书面源头，不属地域方言
            "zh-Hans", "zh-Hant", "zh-Hant-HK", "lzh",
            "yue", "cmn-sichuan", "cmn-dongbei", "cmn-henan",
            "cmn-shaanxi", "hsn", "cmn-xinjiang", "nan", "nan-chaoshan", "hak", "wuu", "wuu-shanghai",
            // 中国少数民族语言
            "bo", "ug", "mn-Mong", "kk", "za", "ko-CN",
            // 邻近与友好国家
            "ja", "ko", "ko-KP", "vi", "th", "km", "my", "ms", "id", "fil",
            "ru", "kk", "uz", "az", "sr", "rw", "sw", "am", "ha",
        ]
        func rank(_ c: String) -> Int { priority.firstIndex(of: c) ?? priority.count }
        return found.sorted {
            let (a, b) = (rank($0.key), rank($1.key))
            return a != b ? a < b : $0.key < $1.key
        }.map { ($0.key, $0.value) }
    }

    /// 应用配置根目录（菜单中一键打开）
    static var appSupportDir: String {
        NSHomeDirectory() + "/Library/Application Support/LTE Guard"
    }

    /// 用户自定义语言目录
    static var userLangDir: String { appSupportDir + "/lang" }

    static var searchDirs: [String] {
        // 新标准位置 → 旧隐藏路径（向后兼容） → App 内置
        var d = [userLangDir, NSHomeDirectory() + "/.lte-guard-lang"]
        if let r = Bundle.main.resourcePath { d.append(r + "/lang") }
        return d
    }

    /// 确保目录存在，并放一份 en.ini 作为翻译模板
    static func prepareUserLangDir() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: userLangDir, withIntermediateDirectories: true)
        let sample = userLangDir + "/README.txt"
        if !fm.fileExists(atPath: sample) {
            let text = """
            把你自己的 <语言代码>.ini 放在这个文件夹里（例如 nl.ini、sr.ini）。

            最简单的做法：把这里的 zhs.template.ini（简体中文）或 en.template.ini
            （英文）复制一份，改名为目标语言代码，然后翻译每行等号右边的文字。
            重启 LTE Guard 后就会出现在「语言」菜单里。

            同名文件会覆盖 App 内置的版本。
            欢迎把翻译提交到项目，让更多人用上：
            https://github.com/oceantangqoit/Mac-lte-guard

            ---

            Put your own <language>.ini files here (e.g. nl.ini, sr.ini).

            Easiest way: copy zhs.template.ini (Simplified Chinese) or
            en.template.ini here, rename it to your language code, and translate
            the right-hand side of each numbered line. Restart LTE Guard and it
            appears in the Language menu.

            A file here overrides a bundled one with the same name.
            Translation pull requests are very welcome.
            """
            try? text.write(toFile: sample, atomically: true, encoding: .utf8)
        }
        // 附带英文与简体中文两份模板，省去用户去 App 包里翻。
        // 无条件覆盖：模板不应被用户编辑（应复制改名后翻译），
        // 覆盖才能保证升级后模板始终与当前版本的键位同步
        if let r = Bundle.main.resourcePath {
            for (src, dst) in [("en", "en"), ("zh-Hans", "zhs")] {
                let from = r + "/lang/\(src).ini", to = userLangDir + "/\(dst).template.ini"
                try? fm.removeItem(atPath: to)
                try? fm.copyItem(atPath: from, toPath: to)
            }
        }
    }

    private static func metaName(_ path: String) -> String? {
        guard let t = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in t.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.lowercased().hasPrefix("name=") { return String(s.dropFirst(5)) }
        }
        return nil
    }

    private init() { load(preferred: nil) }

    /// 载入语言：显式指定 > 用户偏好 > 系统语言 > en
    func load(preferred: String?) {
        let want = preferred
            ?? UserDefaults.standard.string(forKey: "lang")
            ?? Locale.preferredLanguages.first.map { l -> String in
                if l.hasPrefix("zh-Hant") || l.hasPrefix("zh-TW") || l.hasPrefix("zh-HK") || l.hasPrefix("zh-MO") { return "zh-Hant" }
                if l.hasPrefix("zh") { return "zh-Hans" }
                // 保留地区变体（pt-BR / es-MX / es-AR），其余取主语言
                let parts = l.split(separator: "-")
                if parts.count >= 2, ["pt","es"].contains(String(parts[0])) {
                    return "\(parts[0])-\(parts[1])"
                }
                return String(l.prefix(2))
            }
            ?? "en"

        // 依次尝试：完整代码 -> 主语言 -> en
        var chain = [want]
        if want.contains("-"), let base = want.split(separator: "-").first { chain.append(String(base)) }
        chain.append("en")

        // 从兜底到首选逐层叠加，后加载的覆盖先加载的。
        // 关键在于：用户自己导出改过的语言文件往往停留在导出那天的版本，
        // 后来新增的键它没有。若像从前那样「找到第一个文件就用」，
        // 那些键就只能在界面上露出 #236 这样的编号。分层叠加之后，
        // 缺的键由内置的同语言文件补，再不济由英文补，绝不会露编号
        table = [:]
        var hit: String? = nil
        for cand in chain.reversed() {                     // en → 主语言 → 完整代码
            for dir in I18n.searchDirs.reversed() {        // 内置 → 旧路径 → 用户目录
                let path = "\(dir)/\(cand).ini"
                if let t = try? String(contentsOfFile: path, encoding: .utf8) {
                    parse(t)
                    hit = cand
                }
            }
        }
        code = hit ?? want
        if preferred != nil, hit != nil {
            UserDefaults.standard.set(code, forKey: "lang")
        }
    }

    /// 叠加解析：只往表里添，不清空。分层加载靠它——
    /// 后加载的层覆盖先加载的同号键，缺的键则保留下层的值
    private func parse(_ text: String) {
        var inStrings = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                inStrings = line.lowercased() == "[strings]"
                continue
            }
            guard inStrings, let eq = line.firstIndex(of: "="),
                  let key = Int(line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces))
            else { continue }
            table[key] = String(line[line.index(after: eq)...])
        }
    }

    /// 当前语言是否从右向左书写
    var isRTL: Bool { I18n.isRTL(code) }

    /// 某语言是否自右向左书写（按语言代码判断，与当前界面语言无关）
    /// lzh（文言）依传统竖排右起之制，取右起排布：菜单右起、子菜单向左而开。
    /// 汉字为强左向字符，行内仍左起——此为 Unicode 双向算法所定，不作反转。
    static func isRTL(_ code: String) -> Bool {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return ["ar", "he", "fa", "ur", "ug", "ps", "ckb", "yi", "dv", "lzh"].contains(base)
    }

    // Unicode 双向算法隔离符（W3C i18n 推荐做法）
    static let FSI = "\u{2068}"   // First Strong Isolate
    static let PDI = "\u{2069}"   // Pop Directional Isolate
    static let RLM = "\u{200F}"           // Right-to-Left Mark

    /// 语言包定做模式：每条文案前挂上它的序号。改语言包的人最费神的
    /// 不是翻译，而是「界面上这句话是第几号」——把号码直接显示出来，
    /// 对着改即可，不必回头在 ini 里逐条比对
    static var showKeys: Bool {
        get { UserDefaults.standard.bool(forKey: "showLangKeys") }
        set { UserDefaults.standard.set(newValue, forKey: "showLangKeys") }
    }

    /// 是否逐字倒排显示。仅文言（lzh）如此：汉字是强左向字符，Unicode
    /// 双向算法不会把它们右起排布，故由程序显式倒序。
    /// 阿拉伯语、希伯来语等真正的 RTL 文字自有双向算法处理，绝不走这条路径。
    var isGlyphReversed: Bool { code == "lzh" }

    /// 按显示宽度折行，再逐行倒排。**行序不动**——右起读的是每一行，
    /// 不是整段：整段倒置会把末句顶到最前，读序全反，那是错的。
    /// width 为可用像素宽，font 用于实测每个字的宽度。
    static func reverseWrapped(_ s: String, width: CGFloat, font: NSFont) -> String {
        guard width > 20 else { return reverseGlyphs(s) }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return s.split(separator: "\n", omittingEmptySubsequences: false).map { para -> String in
            var lines: [String] = []
            var cur: [String] = []
            var used: CGFloat = 0
            for tok in tokens(of: String(para)) {
                let w = (tok as NSString).size(withAttributes: attrs).width
                // 行首的空格不占位置，否则倒排后行末会多出悬空的空白
                if used + w > width, !cur.isEmpty {
                    lines.append(cur.reversed().joined())
                    cur = []; used = 0
                    if tok == " " { continue }
                }
                cur.append(tok); used += w
            }
            if !cur.isEmpty { lines.append(cur.reversed().joined()) }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// 逐字倒排：汉字一字一序自右而左，拉丁词、数字、占位符整体保序
    /// （"USB" 倒成 "BSU" 便不可读），成对括号引号左右互易。
    /// 只倒每行之内，行序不动。短文本（菜单项、通知）用这个就够。
    static func reverseGlyphs(_ s: String) -> String {
        return s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            tokens(of: String(line)).reversed().joined()
        }.joined(separator: "\n")
    }

    /// 切分成倒排的最小单位：汉字与标点各自成粒（标点顺带左右互易），
    /// 拉丁字母、数字及其粘连符号聚成一词——"USB"、"LTE Guard"、"{0}"
    /// 都得整块搬，拆开就不可读了
    private static func tokens(of line: String) -> [String] {
        let mirror: [Character: Character] = [
            "「": "」", "」": "「", "『": "』", "』": "『", "（": "）", "）": "（",
            "(": ")", ")": "(", "《": "》", "》": "《", "〈": "〉", "〉": "〈",
            "【": "】", "】": "【", "[": "]", "]": "[", "〔": "〕", "〕": "〔",
        ]
        func joinable(_ c: Character) -> Bool {
            (c.isASCII && (c.isLetter || c.isNumber)) || "{}._:/@-+#".contains(c)
        }
        let cs = Array(line)
        var toks: [String] = []
        var buf = ""
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if joinable(c) {
                buf.append(c)
            } else if c == " " && !buf.isEmpty && i + 1 < cs.count && joinable(cs[i + 1]) {
                buf.append(c)          // "LTE Guard" 词组中间的空格不拆
            } else {
                if !buf.isEmpty { toks.append(buf); buf = "" }
                toks.append(String(mirror[c] ?? c))
            }
            i += 1
        }
        if !buf.isEmpty { toks.append(buf) }
        return toks
    }

    /// 取文案：t(21, "Wi-Fi", "USB") -> "已守护 Wi-Fi，方式：USB"
    /// RTL 语言下，插入值用 FSI/PDI 包裹，避免接口名、VID:PID 等拉丁片段
    /// 被 BiDi 算法重排后标点跑到错误一侧。
    func t(_ id: Int, _ args: CVarArg...) -> String {
        var s = table[id] ?? "#\(id)"
        // ini 是单行格式，文案里的换行写作字面 \n——在这里统一还原，
        // 否则对话框会把 "\n\n" 原样显示出来
        s = s.replacingOccurrences(of: "\\n", with: "\n")
        // 文言自行倒排，不用 BiDi 隔离符（隔离符会成为倒排中的杂质）
        let iso = isRTL && !isGlyphReversed
        for (i, a) in args.enumerated() {
            let v = iso ? I18n.FSI + "\(a)" + I18n.PDI : "\(a)"
            s = s.replacingOccurrences(of: "{\(i)}", with: v)
        }
        let body = isGlyphReversed ? I18n.reverseGlyphs(s) : s
        // 号码不参与倒排：它是给编辑者的标记，不是正文的一部分
        return I18n.showKeys ? "\(id)·\(body)" : body
    }

    /// 段落级方向标记：让整段在 RTL 语言下右对齐显示。
    /// 文言已逐字倒排成形，再加 RLM 会让双向算法二次重排，故不加；
    /// 但要按对话框正文的实际宽度重新折行——t() 只倒了字序，
    /// 段落若整块交给系统折行，倒排的行就与视觉的行对不上。
    /// width 取 NSAlert 正文的常见可用宽度，略留余量以免系统二次折行。
    /// width 默认取窄值：不带 accessoryView 的 NSAlert 正文只有 260pt 上下，
    /// 按宽了折，系统会把我折出的行再折一次——视觉的行与倒排的行错开，
    /// 读起来就是乱的。宁可折窄些多占一行，也不能让系统二次折行。
    /// 带 accessoryView 的窗体正文跟着它加宽，那些地方显式传实际宽度。
    func paragraph(_ s: String, width: CGFloat = 248) -> String {
        guard isRTL else { return s }
        guard isGlyphReversed else { return I18n.RLM + s }
        // 语言包定做模式下不再折行重排：序号是给编辑者的标记，一旦卷进
        // 倒排就会被挪到行尾去，反倒认不出哪句是哪句。此时形制让位于对号入座
        guard !I18n.showKeys else { return s }
        // t() 已把字序倒过来了，这里先还原成正序，再按宽度折行重倒一次
        let upright = I18n.reverseGlyphs(s)
        return I18n.reverseWrapped(upright, width: width,
                                   font: .systemFont(ofSize: NSFont.systemFontSize))
    }
}

func T(_ id: Int, _ args: CVarArg...) -> String {
    switch args.count {
    case 0: return I18n.shared.t(id)
    case 1: return I18n.shared.t(id, args[0])
    case 2: return I18n.shared.t(id, args[0], args[1])
    default: return I18n.shared.t(id, args[0], args[1], args[2])
    }
}
