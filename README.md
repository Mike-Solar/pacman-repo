# pacman-repo

自托管 Pacman 源（Cloudflare R2 托管，GitHub Actions 自动跟踪 AUR 更新打包）。

## 使用

`/etc/pacman.conf` 添加：

```ini
[mikesolar]
SigLevel = Optional TrustAll
Server = https://pacman.rjs04.com/pacman/$arch
```

## 跟踪的包

见 `packages.txt`（AUR 包名，每行一个）。

## 工作方式

- 每周四 05:00（CST）自动运行，也可 Actions 页面手动触发
- 对每个包：浅克隆 `aur.archlinux.org/<pkg>.git`，读 `.SRCINFO` 的 pkgver+pkgrel 与 `versions.json` 对比
- 有更新则在 Arch 容器中 `makepkg` 构建，`repo-add` 更新 `mikesolar.db`，rclone 同步到 R2
- 构建成功的版本写回 `versions.json`（失败的包不推进版本，下周重试）

## 说明

- S3/R2 不支持符号链接，`mikesolar.db` / `mikesolar.files` 是实体副本（repo-add 产物 `cp -L` 展开）
- 未签名（SigLevel Optional）；自用足够，分发他人前建议加 GPG 签名
- 同一 bucket 还托管 Flatpak 源（`repo/` 前缀，见 flatpak.rjs04.com）
