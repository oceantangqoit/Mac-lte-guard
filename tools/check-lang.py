#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""语言包审查脚本 —— 判定口径见 lang/TRANSLATION-POLICY.md

  python3 tools/check-lang.py

四项检查：
  ① 结构：键集一致、无重复键、无空值、占位符匹配、meta 完整
  ② 英文兜底：非英语文件里逐字等于 en.ini 的长文本
  ③ 汉语方言未本地化：逐字等于 zh-Hans.ini 的长文本（扣除有意统一项）
  ④ 汉字污染：非汉字书写语言的文件里残留汉字
退出码非零表示有问题。
"""
import os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = os.path.join(ROOT, "lang")

# 政策第一节：允许与英文同形
KEEP_EN = {1, 57, 65, 66, 120, 121, 165}
# 政策第三节：方言允许与普通话同形
KEEP_ZH = {1, 5, 6, 7, 56, 57, 58, 64, 65, 66, 67, 68, 75, 77, 88, 89, 90, 93, 94, 98, 99,
           101, 112, 113, 120, 121, 122, 135, 136, 137, 145, 146, 156, 160, 162,
           163, 165, 169, 170, 171, 172, 173, 175, 177, 178, 179, 180, 182, 184,
           186, 189, 190, 191}
DIALECTS = ["yue", "nan", "nan-chaoshan", "hak", "hsn", "wuu", "wuu-shanghai",
            "cmn-sichuan", "cmn-dongbei", "cmn-henan", "cmn-shaanxi",
            "cmn-xinjiang", "lzh"]
# 以汉字书写的语言，不参与汉字污染检查
CJK = set(DIALECTS) | {"zh-Hans", "zh-Hant", "zh-Hant-HK", "ja", "ko", "ko-KP", "ko-CN"}


def parse(path):
    d, dup = {}, []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^(\d+)=(.*)$", line.rstrip("\n"))
        if m:
            k = int(m.group(1))
            if k in d:
                dup.append(k)
            d[k] = m.group(2)
    return d, dup


def main():
    files = sorted(glob.glob(os.path.join(L, "*.ini")))
    zh, _ = parse(os.path.join(L, "zh-Hans.ini"))
    en, _ = parse(os.path.join(L, "en.ini"))
    base = set(zh)
    bad = []

    # ① 结构
    for f in files:
        code = os.path.basename(f)[:-4]
        d, dup = parse(f)
        if dup:
            bad.append(f"[结构] {code}: 重复键 {dup}")
        if set(d) != base:
            miss, extra = sorted(base - set(d)), sorted(set(d) - base)
            bad.append(f"[结构] {code}: 缺 {miss} 多 {extra}")
        for k in sorted(base & set(d)):
            if not d[k].strip():
                bad.append(f"[结构] {code}:{k} 空值")
            if set(re.findall(r"\{(\d+)\}", zh[k])) != set(re.findall(r"\{(\d+)\}", d[k])):
                bad.append(f"[结构] {code}:{k} 占位符不匹配")
        txt = open(f, encoding="utf-8").read()
        if "[meta]" not in txt or "\nname=" not in txt:
            bad.append(f"[结构] {code}: meta 段缺失")

    # ② 英文兜底
    for f in files:
        code = os.path.basename(f)[:-4]
        if code == "en":
            continue
        d, _ = parse(f)
        for k in sorted(d):
            if k in en and k not in KEEP_EN and d[k] == en[k] and len(en[k]) > 12:
                bad.append(f"[兜底] {code}:{k} 仍为英文原文")

    # ③ 方言未本地化
    for code in DIALECTS:
        p = os.path.join(L, code + ".ini")
        if not os.path.exists(p):
            continue
        d, _ = parse(p)
        for k in sorted(d):
            if k not in KEEP_ZH and d[k] == zh[k] and len(zh[k]) >= 6:
                bad.append(f"[方言] {code}:{k} 未改写为方言")

    # ④ 汉字污染
    for f in files:
        code = os.path.basename(f)[:-4]
        if code in CJK:
            continue
        d, _ = parse(f)
        for k, v in d.items():
            if re.search(r"[一-鿿]", v):
                bad.append(f"[污染] {code}:{k} 残留汉字 → {v[:40]}")

    # 第五项：条目不得被真换行截断。
    # ini 是单行格式，正文换行必须写成字面 \\n。一旦写进真换行，后半段
    # 就成了不匹配 ^数字= 的孤立行，加载器读不到，界面上的文案缺一截——
    # 而且缺得不声不响。曾有 529 处这样的残缺，起因是 re.sub 的替换串
    # 会把 \\n 当转义序列处理
    for f in files:
        code = os.path.basename(f)[:-4]
        prev = None
        for i, line in enumerate(open(f, encoding="utf-8"), 1):
            s = line.rstrip("\n")
            if re.match(r"^\d+=", s):
                prev = s.split("=")[0]
                continue
            if not s.strip() or s.startswith("#") or s.startswith("["):
                continue
            if re.match(r"^(name|author)=", s):
                continue
            bad.append(f"[截断] {code}:{prev} 第 {i} 行游离于任何键之外 → {s[:40]}")

    print(f"语言文件 {len(files)} 个 × {len(base)} 条键")
    if bad:
        print(f"\n发现 {len(bad)} 处问题：")
        for b in bad:
            print("  " + b)
        return 1
    print("五项检查全部通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
