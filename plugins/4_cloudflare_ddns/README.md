# 插件4：Cloudflare DDNS

**目的**：家里/办公室宽带没有固定 IP，把动态公网 IP 同步到 Cloudflare 的 DNS A 记录，
让 `home.example.com` 永远指向当前这台 Mac 所在的网络。

## 用法

### 从主程序面板（推荐）

菜单栏 → 插件 ▸ 插件设置… → Cloudflare DDNS 段落：

| 字段 | 说明 |
|------|------|
| API Token | Cloudflare 控制台 → My Profile → API Tokens，权限只需 `Zone.DNS` 编辑 |
| Zone ID | 域名概览页右下角的 Zone ID |
| DNS 记录名 | 完整域名，如 `home.example.com` |
| 轮询间隔（秒） | 默认 300，最短 30 |
| TTL | 默认 1（Cloudflare 自动） |

保存后点「启动」。记录不存在会自动创建（A 记录、proxied=false）。

### 命令行

```sh
./build.sh
bin/cf_ddns --token <API Token> --zone <Zone ID> --record home.example.com \
            --interval 300 --ttl 1 --dir ~/Documents/lte-guard-ddns
```

## 输出文件（输出目录内）

- `ddns-log.jsonl`：每次动作一行（start / update / create / error / stop）
- `ddns-state.json`：当前 IP、上次更新时间与结果（面板状态行读它）

## 行为说明

- 公网 IP 从 api.ipify.org / icanhazip.com / ifconfig.me 三个源轮询获取
- IP 没变就不调 Cloudflare；每 24 个周期（默认 2 小时）强制核对一次记录内容，
  防止记录被外部改动后长期漂移
- Token 只走 `Authorization: Bearer` 请求头，不写日志、不落盘（配置存在主程序 UserDefaults）
