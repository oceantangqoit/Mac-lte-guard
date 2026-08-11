#!/bin/bash
# 停止原始数据采集器（插件3）
# 用法：./stop.sh
cd "$(dirname "$0")"

PID=""
if [ -f .recorder.pid ]; then
    PID="$(cat .recorder.pid 2>/dev/null || true)"
fi
if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
    PID="$(pgrep -f 'bin/raw_recorder' | head -1 || true)"
fi

if [ -z "$PID" ]; then
    echo "没有在运行的采集器。"
    exit 0
fi

# SIGINT → 采集器写一行 stop 事件后优雅退出
kill -INT "$PID"
echo "已发送停止信号 (PID $PID)，等待写入 stop 事件…"
for _ in $(seq 1 10); do
    kill -0 "$PID" 2>/dev/null || { echo "已停止。"; rm -f .recorder.pid; exit 0; }
    sleep 0.3
done
# 5 秒还没退则强制
kill -9 "$PID" 2>/dev/null || true
rm -f .recorder.pid
echo "已强制停止。"
