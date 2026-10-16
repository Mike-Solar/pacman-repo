#!/usr/bin/env python3
"""构建结束后：versions.json = 旧值 + 构建成功的包的新版本"""
import json, os

vers = json.load(open("versions.json")) if os.path.exists("versions.json") else {}
planned = json.load(open("versions-planned.json"))
failed = set()
if os.path.exists("failed.txt"):
    failed = {l.replace("BUILD_FAIL", "").replace("NO_PKG", "").strip() for l in open("failed.txt")}

built = [l.strip() for l in open("build-list.txt") if l.strip()]
for p in built:
    if p not in failed:
        vers[p] = planned[p]
json.dump(vers, open("versions.json", "w"), indent=1, ensure_ascii=False)
print("versions.json 更新:", {p: vers[p] for p in built if p not in failed} or "无")
