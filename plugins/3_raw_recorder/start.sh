#!/bin/bash
# 启动原始数据采集器（插件3）
# 用法：./start.sh  或  ./start.sh /自定义/输出/路径.jsonl
set -e
cd "$(dirname "$0")"

OUT="${1:-$HOME/Documents/lte-guard-raw/raw.jsonl}"
OUTDIR="$(dirname "$OUT")"
mkdir -p "$OUTDIR"

# 已在运行则提示退出
if pgrep -f "bin/raw_recorder" >/dev/null 2>&1; then
    echo "采集器已在运行。"
    echo "查看进度：tail -f '$OUT'"
    exit 0
fi

nohup ./bin/raw_recorder "$OUT" >/dev/null 2>&1 &
echo $! > .recorder.pid
sleep 1
echo "已启动采集器 (PID $!)"
echo "记录文件：$OUT"
echo "查看进度：tail -f '$OUT'"
echo "停止采集：./stop.sh"
