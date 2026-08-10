import Cocoa
import IOKit
import IOKit.pwr_mgt

// MARK: - 唤醒监听

// IOKit 电源消息常量（Swift 无法导入这些 C 宏，按 IOMessage.h 定义硬编码）
private let kMsgCanSleep:  UInt32 = 0xE000_0270   // kIOMessageCanSystemSleep
private let kMsgWillSleep: UInt32 = 0xE000_0280   // kIOMessageSystemWillSleep
private let kMsgPoweredOn: UInt32 = 0xE000_0300   // kIOMessageSystemHasPoweredOn

/// 合盖状态变化消息（IOPMPrivate.h 的 kIOPMMessageClamshellStateChange：
/// sys_iokit | sub_iokit_powermanagement | 0x100；messageArgument bit0 = 已合盖）
private let kMsgClamshellChange: UInt32 = 0xE001_8100

/// 盖子此刻是不是合着的——直接问 IOPMrootDomain，不靠攒事件。
/// 原先只监听 clamshell 变化消息、把状态记在变量里，可合盖的一瞬间
/// 系统就开始睡眠，那条私有消息未必赶得及在睡眠通知之前投递到；
/// 没赶上，状态就一直是「不知道」，于是每次都报成「未合盖」。
/// 台式机没有盖子，读不到这个属性，返回 false 正合适
func clamshellClosedNow() -> Bool {
    let root = IOServiceGetMatchingService(Sys.ioDefaultPort,
                                           IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return false }
    defer { IOObjectRelease(root) }
    let v = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                            nil, 0)?.takeRetainedValue()
    return (v as? Bool) ?? false
}

final class WakeWatcher {
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notifyPort: IONotificationPortRef?
    private var clamshellNote: io_object_t = 0
    private var clamshellPort: IONotificationPortRef?
    private var lastClamshell: Bool?   // 消息可能重复投递，只记状态变化

    func start() {
        let cb: IOServiceInterestCallback = { refcon, _, msgType, msgArg in
            guard let refcon = refcon else { return }
            let me = Unmanaged<WakeWatcher>.fromOpaque(refcon).takeUnretainedValue()
            switch msgType {
            case kMsgCanSleep, kMsgWillSleep:
                if msgType == kMsgWillSleep {
                    Sys.log(T(118))   // 真正入睡才记，询问阶段不记
                    // 睡眠通报：此刻网络还活着，同步抢发（≤3.5s，配置了 webhook 才发；
                    // 失败会入待补队列，唤醒恢复后自动补发并注明原时间）
                    if WebhookSender.configured() != nil {
                        // 以此刻的实际状态为准；事件累积只作旁证
                        let lid = (clamshellClosedNow() || me.lastClamshell == true)
                            ? T(142) : T(150)
                        WebhookSender.send(T(147, lid), sync: true)
                    }
                }
                IOAllowPowerChange(me.rootPort, Int(bitPattern: msgArg))
            case kMsgPoweredOn:
                // 唤醒即修，不做预检（详见 Healer 注释）。
                // 不加延迟：「断联时命令」要抢在拔插前跑（如打开网络面板看过程），
                // USB 就绪缓冲由 Healer 在拔插前自行等待
                DispatchQueue.global().async {
                    Healer.shared.checkAndHeal(reason: "wake")
                }
            default: break
            }
        }
        let ref = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(ref, &notifyPort, cb, &notifier)
        if rootPort != 0, let np = notifyPort {
            CFRunLoopAddSource(CFRunLoopGetCurrent(),
                               IONotificationPortGetRunLoopSource(np).takeUnretainedValue(),
                               .commonModes)
        }

        // ── 合盖/开盖时刻：监听 IOPMrootDomain 的 clamshell 状态变化，
        //    与「系统进入休眠」对照即可看出合盖→入睡的间隔 ──
        let pmRoot = IOServiceGetMatchingService(Sys.ioDefaultPort,
                                                 IOServiceMatching("IOPMrootDomain"))
        guard pmRoot != 0 else { return }
        let ccb: IOServiceInterestCallback = { refcon, _, msgType, msgArg in
            guard msgType == kMsgClamshellChange, let refcon = refcon else { return }
            let me = Unmanaged<WakeWatcher>.fromOpaque(refcon).takeUnretainedValue()
            let closed = (UInt(bitPattern: msgArg) & 1) == 1
            guard closed != me.lastClamshell else { return }
            me.lastClamshell = closed
            Sys.log(closed ? T(142) : T(143))
        }
        clamshellPort = IONotificationPortCreate(Sys.ioDefaultPort)
        if let cp = clamshellPort {
            IOServiceAddInterestNotification(cp, pmRoot, kIOGeneralInterest,
                                             ccb, ref, &clamshellNote)
            CFRunLoopAddSource(CFRunLoopGetCurrent(),
                               IONotificationPortGetRunLoopSource(cp).takeUnretainedValue(),
                               .commonModes)
        }
        IOObjectRelease(pmRoot)
    }
}
