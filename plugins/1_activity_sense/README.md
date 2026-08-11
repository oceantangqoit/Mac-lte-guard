# 插件1：活动感知（Activity Sense）

源码并入 LTE Guard 主程序编译（`build.sh` 会包含本目录），功能入口在菜单：**设置 → 活动感知**。

## 模式

| 模式 | 说明 | 权限 |
|------|------|------|
| 关闭 | 默认，什么都不做 | — |
| 内建 | 前台 App + 空闲时间 + 电源状态，webhook 通报附带一行"当前活动" | 零权限 |
| ActivityWatch | 在内建基础上读取 ActivityWatch 的窗口标题/AFK 状态 | 需自装 aw-server |

## CSV 记录

菜单里"选择记录文件…"后可定时（60s）采样写入：

```csv
time,app,bundle_id,idle_sec,on_battery,charging,battery_pct,aw_extra
```

配置键：`ACTIVITY_SENSE`（0/1/2）、`ACTIVITY_CSV`（路径）。

## 说明

- 这是"最小活动感知"，信号有限；更丰富的信号请用 `../3_raw_recorder/` + `../2_lawyer_log/`
- 本插件代码在编译期与主程序耦合（依赖 `Config`/`I18n`），不做成独立程序
