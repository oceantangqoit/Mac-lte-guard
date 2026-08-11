# 插件2：律师工作日志守护程序（Lawyer Work Log）

自动记录律师每天的工作：观察屏幕、盖子、WiFi、蓝牙、键鼠、前台窗口、激活目录，
由规则引擎判定**有价值的工作片段**，只把片段写进 CSV——不是什么都存。
无法归属案件的片段会**弹对话框问你**办的是谁的案件。

## 用法

```sh
./build.sh
bin/lawyer_log                                    # 内置兜底规则
bin/lawyer_log --rules Rules.json                 # 用 AI 分析出的规则（推荐）
bin/lawyer_log --csv ~/Documents/律师日志.csv      # 指定日志路径
bin/lawyer_log --ask off                          # 关闭"询问"（默认开）
bin/lawyer_log --debug                            # 调试：打印每次采样
```

## 工作日志 CSV 字段

```csv
start,end,duration_min,case,type,type_zh,app,dir,window_title,note
2026-08-11 09:12:00,2026-08-11 10:03:00,51,张三诉李四,drafting,文书写作,Word,案卷/张三诉李四/答辩状.md,答辩状 - 张三诉李四,
```

| 字段 | 含义 |
|------|------|
| case | 当事人/案件名（从路径/标题提取；提取不到会询问） |
| type / type_zh | 活动类型：drafting 文书写作 / research 检索 / client_comms 沟通 / meeting 会议 / admin 行政 / break 休息 |
| dir | 从窗口标题提取的激活目录 |
| note | 结束原因（空闲超时/屏幕熄灭/睡眠）或"待补充案件" |

## 观察的信号

| 信号 | 获取方式 | 权限 |
|------|----------|------|
| 前台窗口 / 标题 / 激活目录 | NSWorkspace / CGWindowList（标题需屏幕录制权限，无则空） | 尽力而为 |
| 盖子 / 屏幕 | IOKit 电源事件 + CGDisplayIsAsleep | 无 |
| WiFi / LTE 网络 | route / ipconfig / SCDynamicStore | 无 |
| 蓝牙（手机远近） | 读系统配对 plist，前后对比 | 尽力而为 |
| 键盘/鼠标/触摸板闲置 | CGEventSource | 无 |
| 电源 / CPU / 内存 / 显示器 | pmset / mach / NSScreen | 无 |
| 角度 / 加速度 | **macOS 无公开 API**，不实现 | — |

## 规则从哪来（重要）

1. 先跑 `../3_raw_recorder/` 采集 3-7 天原始数据
2. 把 JSONL + `../PROMPT.md` 交给 AI
3. AI 输出 `Rules.json` → 放到本目录 → `bin/lawyer_log --rules Rules.json`

没有 Rules.json 时用**内置兜底规则**（通用启发式，能跑但不专业）。规则结构见 `../PROMPT.md`。

## 常驻（LaunchAgent）

让它在后台常驻，开机自动启动：

```xml
<!-- ~/Library/LaunchAgents/com.oceantang.lawyerlog.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.oceantang.lawyerlog</string>
  <key>ProgramArguments</key>
  <array>
    <string>/ABSOLUTE/PATH/plugins/2_lawyer_log/bin/lawyer_log</string>
    <string>--rules</string>
    <string>/ABSOLUTE/PATH/plugins/2_lawyer_log/Rules.json</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/lawyer_log.out</string>
  <key>StandardErrorPath</key><string>/tmp/lawyer_log.err</string>
</dict>
</plist>
```

```sh
launchctl load ~/Library/LaunchAgents/com.oceantang.lawyerlog.plist
```

## 隐私哲学

- 所有信号本地处理，日志只写在本机 CSV，**不联网、不上传**
- 无法归属时才弹询问，绝不偷记
- 想停：`launchctl unload` 或 Ctrl-C
