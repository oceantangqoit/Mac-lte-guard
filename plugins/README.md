# LTE Guard 插件目录

LTE Guard 主程序（网络守护）保持纯净，所有"观察类"功能以插件形式放在本目录，**默认全部不启用**，需要的人自行开启。

| 目录 | 插件 | 定位 |
|------|------|------|
| `1_activity_sense/` | 活动感知（内建/ActivityWatch） | 已并入主程序菜单（设置 → 活动感知），源码归此管理 |
| `2_lawyer_log/` | 律师工作日志守护程序 | 独立程序：观察屏幕/盖子/WiFi/蓝牙/键鼠/窗口/目录，按规则判定后只记有价值的工作片段到 CSV，可随 LaunchAgent 常驻 |
| `3_raw_recorder/` | 原始数据采集器 | 独立程序：什么都记（JSONL），为行业插件（如律师日志）提供真实数据 → 交给 AI 分析规则 |
| `4_cloudflare_ddns/` | Cloudflare DDNS | 独立程序：轮询公网 IP，变化时调 Cloudflare API 更新 DNS A 记录 |

## 启动方式（v2.68.0 起）

外置插件（2/3/4）统一由主程序「插件 ▸ 插件设置…」面板管理：
- 每个插件可指定**输出文件夹**（NSOpenPanel 选择）
- 运行状态持久化——App 重启后自动拉起上次在跑的插件，不用每次手工开
- 菜单里仍可单个启停（插件 ▸ 各插件子菜单）

## 工作流

```
3_raw_recorder 采原始数据（几天）
      ↓
把 JSONL + PROMPT.md 交给 AI
      ↓
产出插件2 的规则集（Rules.json）
      ↓
2_lawyer_log 加载规则，按规则只记有价值的工作日志
```

## 权限哲学

- 插件1、插件2 核心信号全部**零权限**（NSWorkspace / CGEventSource / pmset / route / IOKit）
- 更精细的信号（窗口标题、SSID、蓝牙扫描）在 macOS 上需要授权——能拿就拿，拿不到留空，**绝不主动弹权限框**
- 陀螺仪/加速度计在 Mac 上无公开 API，不实现（详见 `2_lawyer_log/README.md`）
