# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Mac 合盖睡眠后 USB 网卡断联？醒来自动修好，不用再拔插。</b><br>
  <sub>常驻菜单栏的 USB 网卡守护工具 · Swift 原生 · 零依赖 · MIT</sub>
</p>

<p align="center">
  <b>简体中文</b> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.ru.md">Русский</a> · <a href="README.rw.md">Ikinyarwanda</a>
</p>

---

## 问题

不少 USB LTE 上网卡 / USB 有线网卡在 Mac 合盖睡眠后会"假死"：指示灯还亮着、系统里接口也在，但就是不通网，**必须拔下来重插一次**才恢复。

原因是睡眠时 macOS 不切断 USB 供电（VBUS 由 SMC 固件直管，软件无法关闭），设备侧的 USB 会话却已失效——重启网络服务没用，因为要重置的是 USB 层。

## 谁会用到

只要 Mac 靠 **USB 外接网卡上网**，就可能撞上这个问题：

- 🚁 **无人机图传改 LTE** —— DJI 一代图传改蜂窝回传等玩法，Mac 端插 4G/5G 上网卡长时间值守
- 📡 **USB LTE / 4G / 5G 上网卡、随身 WiFi、USB 蜂窝模块** —— 户外作业、车载、船载、展会、临时办公
- 🔌 **USB-C / Thunderbolt 转以太网适配器** —— Mac 没有网口，接会议室、机房、客户现场的网线
- 🧩 **扩展坞 / Dock 里的网卡** —— Belkin、Plugable、Anker、绿联、CalDigit 等
- 🎥 **依赖稳定上行的直播、RTMP 推流、远程运维**
- 🖥 **软路由 / 树莓派 / 工控设备通过 USB 网卡直连 Mac 调试**

共同点：合盖一次，回来就断网，指示灯还亮着，**只能拔了重插**。

### 不止网卡

同样的"睡醒后假死、只能物理拔插"在其他 USB 设备上也很常见——[Apple 官方社区](https://discussions.apple.com/thread/7745583)、[MacRumors](https://forums.macrumors.com/threads/mac-mini-m1-usb-ports-not-working-after-wake-from-sleep.2326616/)、[Plugable 知识库](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos)都有大量记录：音频接口、摄像头、外置硬盘、读卡器、扩展坞上的各个组件都会中招。

因为底层机制相同，本工具的菜单里提供了 **「重置 USB 设备」**：列出当前所有 USB 设备，选一个就能对它做软件拔插，不必伸手去拔线。网卡之外的设备目前需要手动触发（自动检测只覆盖网络，因为"通不通"有明确的判定标准，而摄像头、音频接口很难自动判断是否假死）。

> ⚠️ 对外置硬盘等存储设备使用前，请先停止读写并推出，否则可能损坏数据。

## 如果你是搜索着找过来的

这些说法描述的多半是同一件事，本工具就是为它写的：

> Mac 睡眠唤醒后网线没反应 · 合盖后 USB 网卡断网 · 外接网卡要拔了重插才恢复 · USB-C 转以太网适配器休眠后失效 · 扩展坞网口睡醒不通 · LTE 上网卡合盖后掉线 · 4G 网卡唤醒后无法上网 · 指示灯亮但没网 · 接口还在但 ping 不通

英文常见搜索词（本工具同样适用）：

> `usb ethernet adapter not working after sleep mac` · `macbook ethernet doesn't wake up after sleep` · `usb-c ethernet adapter stops working after lid close` · `mac dock ethernet not detected after wake` · `lte modem disconnects after macbook sleeps` · `have to unplug and replug ethernet adapter macos`

### 这个问题有多普遍

Apple 官方社区、MacRumors、Plugable 知识库里同类求助跨越多年、横跨 Intel 与 Apple Silicon：

- [Ethernet USB-C adapter doesn't wake up after sleep](https://forums.macrumors.com/threads/ethernet-usb-c-adapter-doesnt-wake-up-after-sleep.2220969/) — MacRumors
- [Ethernet adapter doesn't want to wake up after sleep](https://discussions.apple.com/thread/8272273) — Apple 官方社区
- [MacBook Air 2020 USB LAN issue after sleep](https://discussions.apple.com/thread/255925525) — Apple 官方社区
- [Usb ethernet adapter is not working after sleep](https://discussions.apple.com/thread/7686532) · [Ethernet not waking after sleep](https://discussions.apple.com/thread/250166501) · [Ethernet reset/disconnect on wake-up](https://discussions.apple.com/thread/251074085) · [Ethernet disconnected after sleep](https://discussions.apple.com/thread/8425667)
- [Devices are not detected after waking from sleep on macOS](https://kb.plugable.com/docking-stations-and-video/devices-are-not-detected-after-waking-from-sleep-or-after-rebooting-on-macos) — Plugable 官方知识库

### 为什么常见的"官方办法"解决不了

| 常被推荐的做法 | 为什么在这个场景下没用 |
|---|---|
| 重置 SMC / NVRAM | Apple Silicon 机型**根本没有 SMC 重置**这一操作；即便在 Intel 机上做了，下次合盖照样复现——它治的不是这个病 |
| 关闭「唤醒以供网络访问」(Wake for network access) | 那个开关管的是"睡眠中被网络唤醒"，与醒来后 USB 会话失效是两码事 |
| 完全断电重启 / 更新系统 | 有效但荒谬——难道每次合盖后都重启一次电脑？ |
| 拔掉网线而不是拔适配器 | 论坛里被反复推荐，实测无效（原帖作者原话："也试过了，不管用"） |
| **拔下 USB 适配器再插回** | 唯一稳定有效的办法——**而这正是本工具用软件自动完成的事** |

## 方案

LTE Guard 是一个常驻在菜单栏里的守护工具，监听系统唤醒事件，醒来后自动检测目标网卡：ping 不通网关就通过 IOKit 对该 USB 设备执行 **软件拔插（USBDeviceReEnumerate）**，等效于手动插拔，通常 **8 秒左右恢复**。

- 🎯 **不挑品牌** — 选中网卡后自动探测 VID/PID，没有内置设备清单
- 🔌 **非 USB 网卡也能用** — 自动降级为重启网络服务
- 🛠 **可挂后续命令** — 恢复后自动执行自定义命令（重连代理、重新拨号等）
- 🌍 **53 种语言** — 跟随系统自动切换，菜单里也能手动选
- 🪶 **零依赖** — 单个 App，不装守护进程、不要 Homebrew

## 安装

**方式一：下载安装包**（[Releases](../../releases)）

- `LTEGuard-x.y.z.dmg` — 拖进 Applications
- `LTEGuard-x.y.z.pkg` — 双击安装，自动配置开机启动

首次打开若提示"无法验证开发者"（未签名应用的正常提示）：**右键点 App → 打开 → 再点打开**，或终端执行

```bash
xattr -dr com.apple.quarantine /Applications/LTEGuard.app
```

**方式二：自己构建**（需 Xcode 命令行工具）

```bash
git clone https://github.com/oceantangqoit/Mac-lte-guard.git
cd Mac-lte-guard && ./build.sh
```

产物在 `dist/`。图标渲染需要 `brew install librsvg`，不装也能构建（App 使用默认图标）。

## 首次使用

安装后第一次打开会有引导：**说明 → 选择要守护的网卡 → 询问是否开机自启**，跟着点完即可。

遇到问题先点菜单里的 **运行诊断**，它会逐项检查并直接告诉你怎么修：

| 诊断项 | 出问题时的含义与对策 |
|---|---|
| 安装位置 | 若显示在 `/Volumes/…`，说明你在从 DMG 里直接运行 —— 先把 App 拖进「应用程序」 |
| 隔离属性 (Gatekeeper) | 未签名应用的正常标记。若打不开：**右键 App → 打开 → 打开**，或 `xattr -dr com.apple.quarantine /Applications/LTEGuard.app` |
| 修复工具 | usbreset 是否可用；正常情况随 App 一起安装，不需要单独装 |
| 守护目标 | 是否已选网卡、接口是否真实存在（换了网卡会提示） |
| 开机启动 | 关闭时重启电脑不会自动运行，可在菜单里一键开启 |

**权限说明**：本工具**完全不需要提权**——不用辅助功能、不用磁盘访问、不用 root、不装任何后台守护进程。

## 使用

1. 启动后菜单栏出现信号图标
2. 点开菜单 → **选择治愈对象…** → 选中你的网卡（带 `· USB` 标记的可用软件拔插）
3. 完事。之后合盖睡眠、开盖，断了会自己修好

菜单其他项：

| 项 | 作用 |
|---|---|
| 立即检测并修复 | 手动触发一次 |
| 查看日志 | 打开 `~/.lte-wake.log` |
| 开机启动 | 开关，随时可改（DMG 安装的用户也能用） |
| 运行诊断 | 逐项自检并给出对策 |
| 恢复后执行命令… | 可选钩子：网卡恢复后自动跑一条 Shell 命令（留空则什么都不做） |
| 重置 USB 设备 | 列出所有 USB 设备，一键软件拔插——音频接口、摄像头、硬盘、扩展坞同样适用 |
| 菜单栏图标 | 始终显示 / 仅异常时显示 / 隐藏（**隐藏后，从「应用程序」再打开一次 App 即可找回**） |
| 打开配置文件夹 | 一键在访达中打开配置、日志与语言目录 |
| 语言 | 53 种语言切换；子菜单内可直接打开语言文件夹 |

## 从右向左的语言（RTL）

内置 4 种从右向左书写的语言：**العربية**（阿拉伯语）、**עברית**（希伯来语）、**فارسی**（波斯语）、**اردو**（乌尔都语）。

由于本工具的语言切换是应用内自行实现（读 `lang/*.ini`）而非走 macOS 的 `.lproj` 本地化机制，系统不会自动镜像界面，因此做了两层处理：

1. **界面镜像**——切换到 RTL 语言时，菜单与子菜单设为 `.rightToLeft`：文本右对齐、图标移到右侧、子菜单箭头翻转；
2. **双向文本隔离**——插入到文案里的值（接口名 `en2`、`2c7c:0125`、服务名等）都是拉丁字母与数字，直接嵌进阿拉伯语句子会被 Unicode BiDi 算法重排，**冒号和括号会跑到错误的一侧**。因此所有占位符替换时都用 `U+2068 FSI` / `U+2069 PDI` 包裹（W3C i18n 推荐做法），让每个插入值成为独立的方向单元。
3. 「恢复后执行命令」输入框强制左对齐——Shell 命令本身始终是拉丁文，右对齐反而难读。

## 多语言

内置 **62 种语言**，启动时按系统语言自动选择，也可在菜单「语言」中手动切换（会记住选择）。

后加入的语言由 AI 辅助翻译、尚未经母语者校对，文件头部已注明。**发现表述不地道，欢迎直接改一行提 PR** —— 这是最容易上手的贡献方式。

**改现有语言的措辞**：菜单「语言 → 编辑当前语言…」会把当前语言的 ini **从 App 里复制到你的语言文件夹并直接打开**，改完重启 App 生效。这份副本优先级高于内置版本，**升级 App 也不会被覆盖**。

导出时会先弹出提示并做一件事：**移除原作者署名与联系方式，替换为你的名字**。也就是说，这份副本从导出那一刻起就是你自己的文件，内容由你负责，与原作者无关——请勿写入违法、冒犯或侵犯他人权利的内容。文件只保存在你自己的电脑上，不会自动上传。

**新增一种语言**：菜单「语言 → 打开语言文件夹…」（会自动放入 `zhs.template.ini` 简体中文与 `en.template.ini` 英文两份模板），复制一份改名为目标语言代码（如 `nl.ini`），翻译等号右侧即可。

语言文件的查找顺序是：**你的语言文件夹 → App 内置**，同名文件以你的为准。改好的文件欢迎提 PR，让用同种语言的人都受益。

**语言文件格式**：一种语言一个 INI，放在 `lang/` 目录，用数字代码作键：

```ini
[meta]
name=简体中文
author=……

[strings]
1=LTE Guard
2=守护：{0}  {1}
3=● 正常
```

`{0}` `{1}` 是占位符，由程序填入。

## 配置文件

`~/.lte-guard.conf`（App 自动维护，也可手改）：

```sh
DEV="en2"              # 网络接口
SERVICE="My LTE"       # 网络服务名（非 USB 设备时用于重启服务）
USB_VID="2c7c"         # USB 厂商 ID，留空则改用重启服务方式
USB_PID="0125"         # USB 产品 ID
POST_CMD=''            # 恢复后执行的命令，例如重启代理进程
```

`POST_CMD` 示例——恢复后重启一个绑定该网卡的 gost 代理：

```sh
POST_CMD='launchctl kickstart -k gui/$(id -u)/com.user.gost-lte'
```

## 工作原理

```
系统唤醒 (IORegisterForSystemPower)
      ↓  等 5 秒让接口稳定
ping 网关，两次确认        → 通 → 结束
      ↓ 不通
USBDeviceReEnumerate      → 非 USB 则 networksetup 重启服务
      ↓  轮询等待拿到 IP（最长 60s）
执行 POST_CMD → 写日志 → 刷新菜单栏图标
```

带 90 秒冷却，避免反复抖动。

## 兼容性与测试情况

### 已实测有效

| 项目 | 环境 |
|---|---|
| 机型 | MacBook（Apple Silicon，arm64） |
| 系统 | macOS 26（Darwin 25.x） |
| 网卡 | 移远 Quectel EC25（VID `2c7c` / PID `0125`），以 ECM/NCM 网卡模式呈现为 `enX` |
| 场景 | 合盖睡眠 → 唤醒后接口存在但网关不通 → 软件拔插后 **约 8 秒恢复**，连续多次可复现 |
| 附加 | 恢复后自动重启绑定该网卡的代理进程（`POST_CMD`） |

### 按原理应当可用，但尚缺实测反馈

| 场景 | 预判与可能需要的调整 |
|---|---|
| **Intel Mac** | `USBDeviceReEnumerate` 在部分 Intel 机型上需要 root，日志会出现 `open failed … try sudo`。对策：以 `sudo` 运行一次确认，或改用「重启网络服务」方式（把配置里的 `USB_VID` 留空即可） |
| **macOS 13 / 14 / 15** | 所用 API（IOKit 电源通知、`USBDeviceReEnumerate`、`NSStatusItem.isVisible`）均为 13+ 稳定接口，预期正常。低于 13 无法运行（Info.plist 已限制） |
| **USB 转以太网适配器**（AX88179、RTL8153、CM3xx 等） | 原理相同，应当可用。注意有些适配器重新枚举后接口名会变（`en5`→`en6`），此时到菜单里重新「选择治愈对象」一次即可 |
| **拨号型 4G 模块**（非 ECM/NCM，走 PPP/AT 拨号） | 重新枚举后需要重新拨号才有 IP，否则会在等待 60 秒后判定失败。对策：在「恢复后执行命令」里填入你的拨号/重连命令 |
| **扩展坞里的网卡** | 重新枚举的是整只 Dock 的 USB 设备时，会连带重置坞上其他设备（外接硬盘、摄像头）。若坞上挂着正在读写的硬盘，建议改用「重启网络服务」方式 |
| **复合设备**（网卡+读卡器+串口一体） | 同上，重置会波及同一 USB 设备的其他功能 |
| **iPhone USB 个人热点** | 属于 Apple 自家 NCM 设备，通常由系统自行恢复；如遇同样问题，本工具原理上同样适用 |
| **Wi-Fi、雷雳网口等非 USB 接口** | 自动降级为「重启网络服务」。能解决软件层假死，解决不了驱动级卡死 |

如果你的设备不在上表中，**欢迎开一个 Issue 告诉我结果**（型号、`USB VID:PID`、`~/.lte-wake.log` 片段），无论成功还是失败——这是目前最需要的反馈。

## 为什么不做「睡眠时保持联网」

早期版本有过这个开关，实测无效后已移除。原因值得写下来，省得别人再踩：

- **`caffeinate -i -s` 挡不住合盖睡眠**。`man caffeinate` 明确写着 `-s` 的断言 *"is valid only when system is running on AC power"*，而且它挡的是**空闲睡眠**；**合盖睡眠（Clamshell Sleep）是另一条独立的触发路径**，接不接电源都拦不住（除非外接显示器进入 clamshell 工作模式）。实测日志里，caffeinate 全程在跑，系统照样 `Entering Sleep state due to 'Clamshell Sleep'`。
- **唯一能拦住它的是 `sudo pmset -a disablesleep 1`**（Amphetamine、InsomniaX 等工具的做法），但这要求 root 提权；而且合盖不睡意味着 CPU 持续运行——**笔记本合盖塞进包里不睡觉，是真的会过热**。
- 权衡之后：本工具专注做好「醒来 8 秒自愈」这一件事，不为一个需要提权、有硬件风险的小众场景扩大攻击面。

**真的需要合盖挂机不断网**（挂下载、推流值守、远程连接保活）？推荐搭配 [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704)（免费、App Store 上架）使用——它负责让机器不睡，本工具负责万一断了自动修好，各司其职。

## 已知限制

- **真正切断 USB 供电做不到** —— Apple Silicon 的 VBUS 由 SMC 固件控制，无公开 API。要物理断电只能外接支持 PPPS 的 USB hub 配合 [uhubctl](https://github.com/mvp/uhubctl)。
- **Intel Mac** 上 `USBDeviceReEnumerate` 偶尔需要 root 权限，日志会提示 `try sudo`。
- **拨号型上网卡**（非 ECM/NCM）重新枚举后可能需要重新拨号，请用 `POST_CMD` 补上。
- App 未做 Apple 公证，首次打开需右键→打开。

## 卸载

```bash
launchctl bootout gui/$(id -u)/com.oceantang.lteguard
rm -f ~/Library/LaunchAgents/com.oceantang.lteguard.plist ~/.lte-guard.conf ~/.lte-wake.log
rm -rf /Applications/LTEGuard.app
```

## 支持项目

如果这个小工具帮你省了反复拔插 USB 的麻烦：

- ⭐ 给仓库点个 Star，或把它推荐给同样被这个问题困扰的人
- 🐛 提 Issue 反馈你的设备型号与日志，帮助覆盖更多网卡
- 🌍 贡献一种语言翻译（[CONTRIBUTING.md](CONTRIBUTING.md)，改几行 INI 就行）
- ☕ 请作者喝杯咖啡

详见 [支持项目](SPONSOR.md)。

## 交流与联系

- 💬 用法讨论、想法交流：[Discussions](../../discussions)
- 🐛 Bug 与功能建议：[Issues](../../issues)

### 关于作者

**唐海洋（Ocean Tang）**，北京市东元（深圳）律师事务所执业律师，2011 年入行、2012 年执业至今。

- **业务领域**：商事诉讼与仲裁、刑事辩护与刑事被害人代理、劳动争议、企业常年法律顾问、尽职调查
- **执业经历**：代理各类诉讼与非诉案件 500 余宗，多家单位常年法律顾问

**为什么律师会写 App**：我 2002 年就考了 CCNA、2003 年考了 CIW 网络安全分析师，2005 年毕业于武汉理工大学。一直用 VBA + Excel 给自己写案件管理工具（案件跟踪、制式文书生成、OCR 提取、自动邮件）。这个 App 的起因也很具体——我把 DJI 一代图传改成 LTE 回传来玩，当个 4G 上网卡，结果每次合盖再打开都要拔了重新插一次才能继续上网，烦到不行，索性和 Claude 配合写了这个 App。

法律上的事、或者技术上的事想聊，都欢迎来 [Discussions](../../discussions) 或发 Issue。

## 许可

MIT License
