#!/usr/bin/env python3
"""构建结束后：versions.json 记录构建成功包的 pkgver-pkgrel（取自 PKGBUILD）"""
import json, os, re

vers = json.load(open("versions.json")) if os.path.exists("versions.json") else {}
failed = set()
if os.path.exists("failed.txt"):
    failed = {l.replace("BUILD_FAIL", "").replace("NO_PKG", "").strip() for l in open("failed.txt")}

def get(pk, name):
    m = re.search(rf"^{name}=['\"]?([^'\"\n]+)", open(f"pkgs/{pk}/PKGBUILD").read(), re.M)
    return m.group(1) if m else "?"

built = [l.strip() for l in open("build-list.txt") if l.strip()]
for p in built:
    if p not in failed:
        vers[p] = f"{get(p, 'pkgver')}-{get(p, 'pkgrel')}"
json.dump(vers, open("versions.json", "w"), indent=1, ensure_ascii=False)
print("versions.json:", {p: vers[p] for p in built if p not in failed} or "无变化")
