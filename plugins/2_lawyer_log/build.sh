#!/bin/sh
# 编译插件2：律师工作日志守护程序
set -e
cd "$(dirname "$0")"
mkdir -p bin
swiftc -O -o bin/lawyer_log main.swift ../core/Sensors.swift \
  -framework Cocoa -framework IOKit -framework CoreGraphics -framework SystemConfiguration
echo "完成 → bin/lawyer_log"
echo "用法: bin/lawyer_log [--rules Rules.json] [--csv 路径.csv] [--ask off] [--debug]"
