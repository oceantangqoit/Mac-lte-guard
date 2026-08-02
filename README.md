# LTE Guard

<p align="center">
  <img src="src/icon.svg" width="120" alt="LTE Guard">
</p>

<p align="center">
  <b>Mac 合盖睡眠后 USB 网卡断联？醒来自动修好，不用再拔插。</b><br>
  <sub>macOS 菜单栏小工具 · Swift 原生 · 零依赖 · MIT</sub>
</p>

<p align="center">
  <b>简体中文</b> · <a href="README.en.md">English</a>
</p>

---

## 问题

不少 USB LTE 上网卡 / USB 有线网卡在 Mac 合盖睡眠后会"假死"：指示灯还亮着、系统里接口也在，但就是不通网，**必须拔下来重插一次**才恢复。

原因是睡眠时 macOS 不切断 USB 供电（VBUS 由 SMC 固件直管，软件无法关闭），设备侧的 USB 会话却已失效——重启网络服务没用，因为要重置的是 USB 层。

## 方案

LTE Guard 常驻菜单栏，监听系统唤醒事件，醒来后自动检测目标网卡：ping 不通网关就通过 IOKit 对该 USB 设备执行 **软件拔插（USBDeviceReEnumerate）**，等效于手动插拔，通常 **8 秒左右恢复**。

- 🎯 **不挑品牌** — 选中网卡后自动探测 VID/PID，没有内置设备清单
- 🔌 **非 USB 网卡也能用** — 自动降级为重启网络服务
- 🌙 **两种睡眠策略** — 「保持联网」阻止睡眠全程在线 /「正常睡眠」醒来自愈
- 🛠 **可挂后续命令** — 恢复后自动执行自定义命令（重连代理、重新拨号等）
- 🌍 **16 种语言** — 跟随系统自动切换，菜单里也能手动选
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

## 使用

1. 启动后菜单栏出现信号图标
2. 点开菜单 → **选择治愈对象…** → 选中你的网卡（带 `· USB` 标记的可用软件拔插）
3. 完事。之后合盖睡眠、开盖，断了会自己修好

菜单其他项：

| 项 | 作用 |
|---|---|
| 睡眠时保持联网 | caffeinate 阻止深睡，网络全程在线（费电，适合挂任务时用） |
| 正常睡眠（唤醒自愈） | 默认模式 |
| 立即检测并修复 | 手动触发一次 |
| 查看日志 | 打开 `~/.lte-wake.log` |

**可选**：想让「保持联网」在合盖时也生效，需要给 pmset 免密权限（执行一次）：

```bash
echo "$(whoami) ALL=(root) NOPASSWD: /usr/bin/pmset" | sudo tee /etc/sudoers.d/pmset-nopasswd
```

## 多语言

内置 16 种语言：简体中文、繁體中文、English、日本語、한국어、العربية、Русский、Français、Deutsch、Italiano、Suomi、Español（含墨西哥/阿根廷变体）、Português（含巴西变体）。

启动时按系统语言自动选择，也可在菜单「语言」中手动切换（记住选择）。

**语言文件格式**：一种语言一个 INI，放在 `lang/` 目录，用数字代码作键：

```ini
[meta]
name=简体中文

[strings]
1=LTE Guard
2=守护：{0}  {1}
3=● 正常
```

`{0}` `{1}` 是占位符，由程序填入。**新增语言**：复制任意 `.ini` 改名为目标语言代码（如 `nl.ini`），翻译等号右侧即可——放进 `~/.lte-guard-lang/` 无需重新构建就能生效，同名文件优先于内置。欢迎提 PR 贡献翻译。

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

## 许可

MIT License
