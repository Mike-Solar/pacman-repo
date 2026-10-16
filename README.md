# pacman-repo

自托管 Pacman 源（Cloudflare R2 托管，GitHub Actions 自动跟踪**上游官网/GitHub** 更新打包，GPG 签名）。

## 使用

```bash
# 导入签名公钥并本地信任
curl -O https://pacman.rjs04.com/pacman/mikesolar.pub
sudo pacman-key --add mikesolar.pub
sudo pacman-key --lsign-key 62D63E707B5BA921
```

`/etc/pacman.conf` 添加：

```ini
[mikesolar]
SigLevel = Required
Server = https://pacman.rjs04.com/pacman/$arch
```

## 包清单与更新策略

见 `pkgs/` 目录。每个包一个目录：vendored `PKGBUILD`（固化自 AUR 快照，之后**不再从 AUR 拉取**，防投毒）+ `update.json`（上游版本检查方式）：

| type | 来源 | 包 |
|---|---|---|
| `github` | GitHub Releases | hiddify, httpdirfs, mimalloc2, naps2, nipaplay-reload-bin, dsh-tauri-desktop-bin |
| `npm` | npm registry | deepseek-harness-bin |
| `vscode` | VSCode 更新 API | visual-studio-code-bin |
| `none` | 手动维护 | kirigami2（上游停更）、pantum-universal-driver（官网无 API） |

## 工作方式

- 每周四 05:00（CST）自动运行，也可 Actions 页面手动触发
- `update.py` 按 `update.json` 查上游最新版 → 更新 vendored PKGBUILD 的 pkgver
- Arch 容器中 `updpkgsums` 重算校验和 → `makepkg --sign` 构建并签名
- `repo-add --sign` 更新 `mikesolar.db`（含 db 签名），rclone 同步到 R2
- 触发构建的条件：上游新版、已升版未发布、从未发布

## 说明

- S3/R2 不支持符号链接，`mikesolar.db` / `mikesolar.files` 是实体副本
- 签名密钥：ed25519，指纹 `039997D802A98F156F2F501262D63E707B5BA921`，公钥在 `mikesolar.pub`
- 同一 bucket 还托管 Flatpak 源（`repo/` 前缀，见 flatpak.rjs04.com）
