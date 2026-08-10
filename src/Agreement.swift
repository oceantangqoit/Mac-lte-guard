import Cocoa

// MARK: - 签约存档
// 责任移交/风险确认属于"签约"：验证即签名，存档即立据。
// 每次签约在配置目录 agreement/ 下留一份可读文本，内容固定中英双语，
// 并原文保留确认时展示的条款（按当时的界面语言）。
enum Agreement {
    static var dir: String { I18n.appSupportDir + "/agreement" }

    static func record(kind: String, subject: String, terms: String, method: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let now = Date()
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let human = DateFormatter(); human.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let who = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let text = """
        LTE Guard \(ver) — Agreement Record / 签约存档
        =============================================
        Time    时间：\(human.string(from: now))
        Type    类型：\(kind)
        Subject 对象：\(subject)
        Signer  签署人：\(who)
        Method  确认方式：\(method)

        Terms as shown at confirmation / 确认时展示的条款原文：
        ---------------------------------------------
        \(terms)
        ---------------------------------------------
        The signer confirmed and accepted the terms above via the method stated.
        签署人已通过上述方式确认并接受以上条款。
        """
        let safe = subject.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let name = "\(stamp.string(from: now))_\(kind)_\(String(safe)).txt"
        try? text.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8)
        Sys.log(T(135, name))
        // 签约现场：留影入门卫室（已授权时）+ webhook 通报，证据链闭环
        if CameraSnap.authorized {
            DispatchQueue.main.async { CameraSnap.take(tag: "agreement") { _ in } }
        }
        WebhookSender.send(T(148, "\(kind) · \(subject)"))
    }

    /// 是否已签署过某类协议（如拍照协议签一次即可，不重复打扰）
    static func hasRecord(kind: String) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .contains { $0.contains("_\(kind)_") }
    }

    /// 《门卫室拍照功能使用协议》——中文为准，英文为参考译文
    static let cameraTerms = """
    《门卫室拍照功能使用协议》

    一、功能说明。开启本功能后，本软件将在检测到网络断联和/或恢复时调用本机摄像头拍摄照片。照片仅保存于本机配置目录 gatehouse 文件夹，本软件不上传、不对外传输，作者亦无法接触照片内容。

    二、用户承诺。用户承诺仅将本功能用于保护本人合法持有之设备的正当目的；不得用于偷拍、监视、跟踪他人，或实施其他侵害他人肖像权、名誉权、隐私权、个人信息权益的行为；拍摄范围可能涉及第三人的，用户应依法自行履行告知、提示义务并取得必要同意。

    三、责任承担与免责。用户使用本功能的一切行为及其后果由用户自行承担；因用户违反法律法规或本协议使用本功能而产生的任何民事、行政或刑事责任，均由用户自行承担，与作者无关。本软件系依 MIT 许可按"现状"免费提供的开源软件，作者不对本功能的适用性、连续性及照片的完整性作出任何明示或默示的保证。

    四、数据管理。照片的保管、使用与删除均由用户自行负责。

    五、法律适用。本协议的订立、效力、解释与争议解决，适用中华人民共和国法律。

    六、签署。用户通过 Touch ID 或设备密码完成身份验证，即视为已阅读、理解并同意本协议全部条款；签署记录存于配置目录 agreement 文件夹。本协议以中文文本为准，英文译文仅供参考。

    Gatehouse Camera Feature Agreement (reference translation — the Chinese text prevails)
    1. When enabled, this software takes photos via the built-in camera upon network disconnection and/or recovery. Photos are stored only in the local "gatehouse" folder; nothing is uploaded, and the author has no access to them.
    2. The user undertakes to use this feature solely for the legitimate purpose of protecting the user's own lawfully held device; not for candid photography, surveillance, stalking, or any act infringing others' portrait, reputation, privacy, or personal-information rights; where third parties may be captured, the user shall give due notice and obtain necessary consent as required by law.
    3. All consequences of using this feature are borne by the user alone. Any civil, administrative, or criminal liability arising from unlawful or non-compliant use rests with the user and not the author. This is open-source software provided free of charge "as is" under the MIT License, without any express or implied warranty.
    4. Storage, use, and deletion of photos are the user's own responsibility.
    5. This agreement is governed by the laws of the People's Republic of China.
    6. Verification via Touch ID or the device password constitutes the user's signature and acceptance of all terms; the signed record is kept in the "agreement" folder.
    """
}
