import Cocoa
import AVFoundation

// MARK: - 自测
// 只测纯函数：给定输入必得确定输出，不依赖网络、摄像头或用户点击。
// 这类错误最阴——不崩溃、不报错，只是结果悄悄是错的。
func runSelfTest() -> Never {
    var pass = 0, fail = 0
    func check(_ name: String, _ got: String, _ want: String) {
        if got == want { pass += 1 }
        else { fail += 1; print("✗ \(name)\n   得到: \(got)\n   应为: \(want)") }
    }
    func checkTrue(_ name: String, _ cond: Bool) {
        if cond { pass += 1 } else { fail += 1; print("✗ \(name)") }
    }

    // 配置转义：命令里带引号、反斜杠、换行是常态，存取必须原样往返
    for raw in ["echo 'it\\'s'", "curl -d '{\"k\":\"v\"}' url",
                "a=1; b=$(date); echo $b", "第一行\n第二行", "结尾反斜杠\\",
                "混合 '单' \"双\" \\ 与\n换行"] {
        check("配置往返: \(raw.prefix(16))", Config.unescape(Config.escape(raw)), raw)
    }

    // 文言逐字倒排：倒两次必回原样，否则次序会越滚越乱
    for raw in ["連斷之時，所擇之器自復。", "Mac 醒後，此程察器而自修之",
                "重啟「en0」（此服綁 LTE Guard 也）", "已守 Wi-Fi，法：USB (05c6:9091)"] {
        check("倒排自反: \(raw.prefix(12))", I18n.reverseGlyphs(I18n.reverseGlyphs(raw)), raw)
    }
    // 拉丁词与占位符不许被拆开
    checkTrue("倒排保词序", I18n.reverseGlyphs("甲 LTE Guard 乙").contains("LTE Guard"))
    checkTrue("倒排保占位符", I18n.reverseGlyphs("已用 {0} 秒").contains("{0}"))

    // 版本比较：错一次就可能让人永远收不到更新，或反复装旧版
    let vers: [(String, String, Bool)] = [
        ("2.10.0", "2.9.0", true), ("2.9.0", "2.10.0", false),
        ("2.53.0", "2.53.0", false), ("3.0.0", "2.99.99", true),
        ("2.0.1", "2.0", true), ("2.0", "2.0.1", false),
    ]
    for (a, b, want) in vers {
        checkTrue("版本 \(a) > \(b) = \(want)", AppDelegate.versionNewer(a, than: b) == want)
    }

    // 提示折行：不折的话会横着顶出屏幕，越要紧的话越看不全
    let long = String(repeating: "这是一句很长的说明文字。", count: 4)
    checkTrue("提示折行生效", UI.tip(long).contains("\n"))
    checkTrue("短提示不动它", !UI.tip("很短").contains("\n"))

    // 合盖判定：与 ioreg 的读数对照。这项曾经错得很隐蔽——靠攒事件记状态，
    // 事件没来就一直是「不知道」，于是每次都报「未合盖」，日志看着还挺正常
    let byIOReg = Sys.run("ioreg -r -k AppleClamshellState -d 1 2>/dev/null "
                          + "| grep -c '\"AppleClamshellState\" = Yes'") == "1"
    checkTrue("合盖状态与 ioreg 一致", clamshellClosedNow() == byIOReg)

    // 语言包的完整性不在这里测：那要碰 I18n 的私有表，为测试破封装不划算。
    // 它由仓库里的校验脚本覆盖（72 语言 × 全部在用键，含占位符比对）

    print("\n自测：通过 \(pass)，失败 \(fail)")
    exit(fail == 0 ? 0 : 1)
}
