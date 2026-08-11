#!/bin/sh
# 编译插件3：原始数据采集器
set -e
cd "$(dirname "$0")"
mkdir -p bin
swiftc -O -o bin/raw_recorder main.swift ../core/Sensors.swift \
  -framework Cocoa -framework IOKit -framework CoreGraphics -framework SystemConfiguration
echo "完成 → bin/raw_recorder"
echo "用法: bin/raw_recorder [输出文件.jsonl]"
