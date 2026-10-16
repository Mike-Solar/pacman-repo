#!/usr/bin/env python3
"""上游版本检查（GitHub/npm/vscode 官方源，不碰 AUR）。
发现新版 → 直接改 vendored PKGBUILD 的版本变量和 pkgrel，输出 build-list.txt。
PKGBUILD 是唯一事实来源，versions.json 只做记录。"""
import json, os, re, urllib.request

def fetch_json(url, accept="application/vnd.github+json"):
    return json.load(urllib.request.urlopen(
        urllib.request.Request(url, headers={"User-Agent": "mikesolar-repo", "Accept": accept}), timeout=30))

def gh_latest(repo, prefix=""):
    # 跳过 draft；有 tag 前缀时允许 prerelease，否则只取正式版
    pre_ok = bool(prefix)
    for r in fetch_json(f"https://api.github.com/repos/{repo}/releases?per_page=30"):
        tag = r["tag_name"]
        if r["draft"] or (r["prerelease"] and not pre_ok):
            continue
        if not prefix or tag.startswith(prefix):
            return tag[len(prefix):].lstrip("v")
    raise RuntimeError(f"{repo} 无匹配 {prefix} 的 release")

def npm_latest(pkg):
    return fetch_json(f"https://registry.npmjs.org/{pkg.replace('/', '%2F')}/latest",
                      accept="application/json")["version"]

def vscode_latest():
    rels = fetch_json("https://update.code.visualstudio.com/api/releases/stable?target=linux-deb-x64")
    r = rels[0]
    return r if isinstance(r, str) else r.get("version") or r.get("productVersion")

def cur_ver(path, var):
    m = re.search(rf"^{re.escape(var)}=['\"]?([^'\"\n]+)", open(path).read(), re.M)
    return m.group(1) if m else None

def bump(path, var, newv):
    txt = open(path).read()
    txt = re.sub(rf"^{re.escape(var)}=['\"]?[^'\"\n]+", f"{var}={newv}", txt, count=1, flags=re.M)
    if var == "pkgver":  # 直接改 pkgver 时重置 pkgrel
        txt = re.sub(r"^pkgrel=\d+", "pkgrel=1", txt, count=1, flags=re.M)
    open(path, "w").write(txt)

build = []
vers = json.load(open("versions.json")) if os.path.exists("versions.json") else {}
for pkg in sorted(os.listdir("pkgs")):
    pj = f"pkgs/{pkg}/PKGBUILD"
    if not os.path.isfile(pj):
        continue
    meta = json.load(open(f"pkgs/{pkg}/update.json"))
    var = meta.get("var", "pkgver")
    cur = cur_ver(pj, var)
    rel = re.search(r"^pkgrel=(\d+)", open(pj).read(), re.M)
    cur_full = f"{cur}-{rel.group(1) if rel else '1'}"
    published = vers.get(pkg)
    try:
        if meta["type"] == "github":
            new = gh_latest(meta["repo"], meta.get("tag_prefix", ""))
        elif meta["type"] == "npm":
            new = npm_latest(meta["package"])
        elif meta["type"] == "vscode":
            new = vscode_latest()
        else:
            new = None
            print(f"{pkg}: {cur} [跳过: {meta.get('reason', '手动维护')}]")
    except Exception as e:
        print(f"{pkg}: 上游检查失败 ({e})，跳过")
        continue
    if new and cur != new:
        print(f"{pkg}: {cur} → {new}  [构建: 上游新版]")
        bump(pj, var, new)
        build.append(pkg)
    elif published is not None and published != cur_full:
        print(f"{pkg}: {cur_full} [构建: 已升版但未发布]")
        build.append(pkg)
    elif published is None:
        print(f"{pkg}: {cur_full} [构建: 未发布过]")
        build.append(pkg)
    else:
        print(f"{pkg}: {cur} [最新]")

open("build-list.txt", "w").write("\n".join(build) + ("\n" if build else ""))
print("待构建:", build or "无")
