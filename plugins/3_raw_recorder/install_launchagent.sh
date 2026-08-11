#!/bin/bash
# 安装采集器为 LaunchAgent（开机自启 + 崩溃自动拉起）
# 注意：必须在你的图形界面终端里运行（本脚本会操作 GUI 登录会话）
# 用法：./install_launchagent.sh
# 卸载：launchctl bootout gui/$(id -u)/com.oceantang.lteguard.rawrecorder && rm ~/Library/LaunchAgents/com.oceantang.lteguard.rawrecorder.plist
set -e
cd "$(dirname "$0")"

BIN="$(pwd)/bin/raw_recorder"
OUT="$HOME/Documents/lte-guard-raw/raw.jsonl"
PLIST="$HOME/Library/LaunchAgents/com.oceantang.lteguard.rawrecorder.plist"

mkdir -p "$HOME/Documents/lte-guard-raw"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.oceantang.lteguard.rawrecorder</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>$OUT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$HOME/Documents/lte-guard-raw/recorder.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Documents/lte-guard-raw/recorder.err</string>
</dict>
</plist>
EOF

launchctl bootout gui/$(id -u)/com.oceantang.lteguard.rawrecorder 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "已安装并启动。"
echo "记录文件：$OUT"
echo "查看进度：tail -f '$OUT'"
