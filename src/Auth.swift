import Cocoa
import LocalAuthentication

// MARK: - 身份验证（Touch ID / 锁屏密码）
// 不自建密码：LocalAuthentication 由系统管理凭据，App 零存储。
// 两类场景：
//   · 敏感操作（命令编辑/退出/关自启/拍照开关/配置文件夹）——受总开关控制
//   · 签约场景（语言文件责任移交、USB 数据风险确认）——始终验证，
//     生物识别/密码即签名，确认动作可归属到本人
enum Auth {
    static var guardEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "authGuard") }
        set { UserDefaults.standard.set(newValue, forKey: "authGuard") }
    }

    /// 模态对话框期间主队列不排程，回调必须用 common modes 派发才能及时执行
    static func onMain(_ block: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common], block: block)
    }

    /// 验证通过才执行 action；机器没有任何验证手段（未设锁屏密码）时直接放行
    static func require(then action: @escaping () -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            action(); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: T(131)) { ok, _ in
            if ok { onMain(action) }
        }
    }

    /// 敏感操作入口：开关未开则直接执行
    static func gate(_ op: String = "", then action: @escaping () -> Void) {
        let go = {
            if !op.isEmpty { OpsNotify.report(op) }
            action()
        }
        guardEnabled ? require(then: go) : go()
    }

    /// 签约场景：始终验证，并把使用的验证方式告知回调（供签约存档记录）
    static func sign(then action: @escaping (_ method: String) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // 机器未设锁屏密码：无凭据可验，仅凭点击确认（存档中如实记录）
            action("confirmation click only — no device credential set")
            return
        }
        let bio = ctx.biometryType == .touchID ? "Touch ID or device password"
                                                : "device password"
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: T(131)) { ok, _ in
            if ok { onMain { action("\(bio) (LocalAuthentication)") } }
        }
    }
}
