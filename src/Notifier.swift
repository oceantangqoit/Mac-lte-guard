import Cocoa
import UserNotifications

// MARK: - 原生通知
// osascript 的 display notification 在现代 macOS 上会被静默丢弃
//（发送者是"脚本编辑器"，默认无通知权限），必须用 App 自己的通知。
enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, err in
            Sys.log(granted ? T(114) : T(115, err?.localizedDescription ?? ""))
        }
    }

    static func post(_ body: String, title: String = "LTE Guard") {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { st in
            if st.authorizationStatus == .authorized {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let req = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
                center.add(req) { err in
                    if let err = err { Sys.log(T(115, err.localizedDescription)) }
                }
            } else {
                // 未授权 / ad-hoc 签名被拒 → 老 API 兜底（已废弃但仍可投递）
                let n = NSUserNotification()
                n.title = title
                n.informativeText = body
                NSUserNotificationCenter.default.deliver(n)
            }
        }
    }
}
