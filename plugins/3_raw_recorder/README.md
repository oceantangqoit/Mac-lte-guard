# 插件3：原始数据采集器（Raw Recorder）

**目的**：什么都记，为行业插件（如插件2 律师日志）收集真实数据 → 交给 AI 分析规则。

## 用法

### 最快启动（推荐）

```sh
./build.sh        # 首次先编译
./start.sh        # 后台启动，默认写到 ~/Documents/lte-guard-raw/raw.jsonl
tail -f ~/Documents/lte-guard-raw/raw.jsonl   # 看实时数据
./stop.sh         # 优雅停止（写一条 stop 事件）
```

### 自定义输出路径

```sh
./start.sh ~/mydata.jsonl
```

### 开机自启（可选）

```sh
./install_launchagent.sh   # 必须在你的图形界面终端里运行
```

装成 LaunchAgent 后开机自启、崩溃自动拉起。卸载：
`launchctl bootout gui/$(id -u)/com.oceantang.lteguard.rawrecorder && rm ~/Library/LaunchAgents/com.oceantang.lteguard.rawrecorder.plist`

每 5 秒采样一行 JSONL。系统睡眠/唤醒也会各记一条 `event`。

### 访达路径授权（一次性）

前台是访达时，采集器会通过 AppleScript 读取当前文件夹完整路径（写入 `dir`）。
首次触发时 macOS 会弹「"终端"想控制"访达"」授权框，**点"允许"**即可，之后静默生效。
授权记在启动采集器的那个终端 App 上（Terminal/iTerm 等），与 WorkBuddy 无关。
误点了"不允许"：系统设置 → 隐私与安全性 → 自动化 → 找到你的终端 → 打开"访达"开关。
未授权时 `dir` 保持空，不影响其他字段。

## 数据字段（一行一个采样）

```json
{
  "ts": "2026-08-11 21:30:00",
  "app": "Visual Studio Code",
  "bundle_id": "com.microsoft.VSCode",
  "pid": 1234,
  "window_title": "张三诉李四 - 合同纠纷 - /Users/ocean/cases/张三诉李四/答辩状.md",
  "dir": "cases/张三诉李四/答辩状.md",
  "kbd_idle_sec": 3,
  "mouse_idle_sec": 1,
  "mouse_x": 1024.5,
  "mouse_y": 640.2,
  "hover_app": "Safari",
  "hover_pid": 5678,
  "hover_title": "",
  "charging": true,
  "on_battery": false,
  "battery_pct": 95,
  "iface": "en0",
  "gateway": "192.168.1.1",
  "ip": "192.168.1.5",
  "ssid": "office-wifi",
  "displays": 2,
  "display_sleep": false,
  "cpu": 12.5,
  "mem_free_gb": 8.3,
  "bt": ["iPhone", "AirPods"]
}
```

## 信号与权限说明

| 信号 | 方式 | 权限 |
|------|------|------|
| 前台 App / PID | CGWindowList 取最前窗口的 owner（NSWorkspace 在后台进程会拿错） | 无 |
| 窗口标题 | CGWindowList | 需屏幕录制权限，**没有则留空**，不会弹框 |
| 激活目录 | 从窗口标题正则提取（cwd 无权限拿不到） | — |
| **访达当前路径** | AppleScript 取 front window 的 target，写入 `dir` 字段 | 需一次性"自动化"授权（仅前台是访达时才查询） |
| 键盘/鼠标空闲 | CGEventSource（`kbd_idle_sec` / `mouse_idle_sec`） | 无 |
| 光标位置 | CGEvent(source:nil).location | 无 |
| 悬停窗口 | CGWindowList bounds 命中测试（`hover_*`）；悬停≠聚焦，键盘输入永远进前台焦点窗口 | 无（hover_title 需屏幕录制权限，无则空） |
| 电源 | pmset | 无 |
| 网络接口/IP | route / ipconfig | 无 |
| SSID | SCDynamicStore | 尽力而为，拿不到留空 |
| 显示器/睡眠 | NSScreen / CGDisplayIsAsleep | 无 |
| CPU/内存 | mach | 无 |
| 蓝牙配对设备 | 读系统 plist | 尽力而为 |
| 陀螺仪/加速度计 | **macOS 无公开 API，不采集** | — |

## 收集数据 → 分析规则

跑几天后，把 JSONL 交给 AI（提示词见 `../PROMPT.md`），输出插件2 的规则集。
