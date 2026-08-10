import Cocoa

/// 菜单栏图标显示模式
enum IconMode: Int {
    case always = 0, problemOnly = 1, hidden = 2
    /// 供日志与通报称呼这三档，用界面上原话，免得日志里出现只有开发者
    /// 看得懂的代号
    var title: String {
        switch self {
        case .always:      return T(49)
        case .problemOnly: return T(50)
        case .hidden:      return T(51)
        }
    }
    static var current: IconMode {
        get { IconMode(rawValue: UserDefaults.standard.integer(forKey: "iconMode")) ?? .always }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "iconMode") }
    }
}
