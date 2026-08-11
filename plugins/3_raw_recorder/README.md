# 插件3：原始数据采集器（Raw Recorder）

**目的**：什么都记，为行业插件（如插件2 律师日志）收集真实数据 → 交给 AI 分析规则。

## 用法

```sh
./build.sh
bin/raw_recorder                # 默认写到 ~/Documents/activity-raw-<日期>.jsonl
bin/raw_recorder ~/mydata.jsonl # 指定输出文件
```

每 5 秒采样一行 JSONL，Ctrl-C 停止。系统睡眠/唤醒也会各记一条 `event`。

## 数据字段（一行一个采样）

```json
{
  "ts": "2026-08-11 21:30:00",
  "app": "Visual Studio Code",
  "bundle_id": "com.microsoft.VSCode",
  "pid": 1234,
  "window_title": "张三诉李四 - 合同纠纷 - /Users/ocean/cases/张三诉李四/答辩状.md",
  "dir": "cases/张三诉李四/答辩状.md",
  "idle_sec": 3,
  "mouse_moved_sec": 1,
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
| 前台 App / PID | NSWorkspace | 无 |
| 窗口标题 | CGWindowList | 需屏幕录制权限，**没有则留空**，不会弹框 |
| 激活目录 | 从窗口标题正则提取（cwd 无权限拿不到） | — |
| 键鼠空闲 | CGEventSource | 无 |
| 电源 | pmset | 无 |
| 网络接口/IP | route / ipconfig | 无 |
| SSID | SCDynamicStore | 尽力而为，拿不到留空 |
| 显示器/睡眠 | NSScreen / CGDisplayIsAsleep | 无 |
| CPU/内存 | mach | 无 |
| 蓝牙配对设备 | 读系统 plist | 尽力而为 |
| 陀螺仪/加速度计 | **macOS 无公开 API，不采集** | — |

## 收集数据 → 分析规则

跑几天后，把 JSONL 交给 AI（提示词见 `../PROMPT.md`），输出插件2 的规则集。
