#!/bin/sh
# 编译插件4：Cloudflare DDNS
set -e
cd "$(dirname "$0")"
mkdir -p bin
swiftc -O -o bin/cf_ddns main.swift -framework Foundation
echo "完成 → bin/cf_ddns"
echo "用法: bin/cf_ddns --token <API Token> --zone <Zone ID> --record <域名> [--interval 秒] [--ttl N] [--dir 目录]"
