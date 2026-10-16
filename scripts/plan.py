#!/usr/bin/env python3
"""对比 AUR 最新 pkgver-pkgrel 与 versions.json，产出待构建清单"""
import json, os, re, subprocess, sys

pkgs = [l.strip() for l in open("packages.txt") if l.strip() and not l.startswith("#")]
vers = json.load(open("versions.json")) if os.path.exists("versions.json") else {}
planned = dict(vers)
build = []
os.makedirs("/tmp/src", exist_ok=True)

for p in pkgs:
    subprocess.run(["git", "clone", "-q", "--depth", "1",
                    f"https://aur.archlinux.org/{p}.git", f"/tmp/src/{p}"], check=True)
    si = open(f"/tmp/src/{p}/.SRCINFO").read()
    v = re.search(r"^\tpkgver = (.+)$", si, re.M).group(1)
    r = re.search(r"^\tpkgrel = (.+)$", si, re.M).group(1)
    nv = f"{v}-{r}"
    status = "重建" if vers.get(p) != nv else "最新"
    print(f"{p}: 源里 {vers.get(p, '(无)')} → AUR {nv}  [{status}]")
    if vers.get(p) != nv:
        build.append(p)
        planned[p] = nv

open("build-list.txt", "w").write("\n".join(build) + ("\n" if build else ""))
json.dump(planned, open("versions-planned.json", "w"), indent=1, ensure_ascii=False)
print("待构建:", build or "无")
