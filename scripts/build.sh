#!/bin/bash
# 在 archlinux 容器中：上游版本检查（不碰 AUR）→ vendored PKGBUILD 构建 → GPG 签名 → 同步 R2
set -euo pipefail
export PACKAGER="sunyu (mikesolar pacman repo) <Mike-Solar@users.noreply.github.com>"
KEYID=62D63E707B5BA921

pacman -Syu --noconfirm --needed base-devel git python sudo rclone gnupg pacman-contrib >/dev/null
useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

# GPG：导入私钥到 builder 和 root，预设口令到 gpg-agent（makepkg --sign 和 repo-add -s 非交互用）
import_key() {  # $1 = 以谁的身份执行
    echo "$GPG_PRIVATE_KEY" | runuser -u "$1" -- gpg --batch --import 2>/dev/null || \
      { [ "$1" = root ] && echo "$GPG_PRIVATE_KEY" | gpg --batch --import; }
    runuser -u "$1" -- bash -c '
        echo allow-preset-passphrase >> ~/.gnupg/gpg-agent.conf
        gpgconf --reload gpg-agent 2>/dev/null || true
        grip=$(gpg --list-secret-keys --with-keygrip --with-colons | awk -F: "/^grp/{print \$10; exit}")
        /usr/lib/gnupg/gpg-preset-passphrase --preset "$grip" <<< "$GPG_PASSPHRASE"
    '
}
import_key builder
GPG_PASSPHRASE="$GPG_PASSPHRASE" bash -c '
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import
    echo allow-preset-passphrase >> ~/.gnupg/gpg-agent.conf
    gpgconf --reload gpg-agent 2>/dev/null || true
    grip=$(gpg --list-secret-keys --with-keygrip --with-colons | awk -F: "/^grp/{print \$10; exit}")
    /usr/lib/gnupg/gpg-preset-passphrase --preset "$grip" <<< "$GPG_PASSPHRASE"
'
echo "GPGKEY=$KEYID" >> /etc/makepkg.conf

# 拉取现有仓库（首次为空）
mkdir -p repo/x86_64 out
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"
rclone sync "r2:$R2_BUCKET/pacman" repo/ || true

# 已有仓库注册为本地源：包间依赖直接装（如 nipaplay→mimalloc2）
if [ -f repo/x86_64/mikesolar.db ]; then
    printf '[mikesolar]\nSigLevel = Never\nServer = file://%s/repo/x86_64\n' "$PWD" >> /etc/pacman.conf
    pacman -Sy >/dev/null
fi

# 一次性模式：重签全部存量包
if [ "${RESIGN_ALL:-0}" = "true" ]; then
    cd repo/x86_64
    for f in *.pkg.tar.zst; do
        [ -f "$f.sig" ] || gpg --batch --yes --detach-sign --local-user $KEYID "$f"
    done
    repo-add --sign --key $KEYID mikesolar.db.tar.gz ./*.pkg.tar.zst
    # repo-add 生成的 db/files 及其 .sig 都是符号链接，全部展开为实体文件
    rm -f mikesolar.db mikesolar.files mikesolar.db.sig mikesolar.files.sig
    cp mikesolar.db.tar.gz mikesolar.db && cp mikesolar.files.tar.gz mikesolar.files
    cp mikesolar.db.tar.gz.sig mikesolar.db.sig && cp mikesolar.files.tar.gz.sig mikesolar.files.sig
    cd - >/dev/null
    cp mikesolar.pub repo/
    rclone sync repo/ "r2:$R2_BUCKET/pacman"
    echo "RESIGNED_ALL"
    exit 0
fi

# 上游版本检查（vendored PKGBUILD 是唯一事实来源）
python3 scripts/update.py
if [ ! -s build-list.txt ]; then
    echo "全部最新，无事发生"
    exit 0
fi

while read -r pkg; do
    echo "=== 构建 $pkg ==="
    rm -rf /home/builder/build
    cp -r "pkgs/$pkg" /home/builder/build
    chown -R builder:builder /home/builder/build
    # 版本变了 → 重算校验和（下载上游源码，可能需要几分钟）
    runuser -u builder -- bash -c 'cd /home/builder/build && updpkgsums' || true
    build_ok() { (cd /home/builder/build && runuser -u builder -- makepkg -s --noconfirm --sign --key $KEYID) 2>&1 | tee /tmp/mk.log; }
    if ! build_ok; then
        # 上游 PGP 签名验证失败：自动导入缺失公钥重试一次
        key=$(grep -oP 'unknown public key \K[0-9A-F]+' /tmp/mk.log | head -1 || true)
        if [ -n "$key" ]; then
            echo "导入上游 PGP 公钥 $key 后重试"
            runuser -u builder -- gpg --keyserver keyserver.ubuntu.com --recv-keys "$key" || true
            build_ok || { echo "BUILD_FAIL $pkg" >> failed.txt; continue; }
        else
            echo "BUILD_FAIL $pkg" >> failed.txt; continue
        fi
    fi
    if cp /home/builder/build/*.pkg.tar.zst /home/builder/build/*.sig repo/x86_64/ 2>/dev/null; then
        # 就地更新本地源并签名 db，后续包的依赖即可安装
        (cd repo/x86_64 && repo-add --sign --key $KEYID mikesolar.db.tar.gz ./*.pkg.tar.zst) && pacman -Sy >/dev/null
        cp /home/builder/build/*.pkg.tar.zst out/ 2>/dev/null || true
    else
        echo "NO_PKG $pkg" >> failed.txt
    fi
done < build-list.txt

# 发布
if ls out/*.pkg.tar.zst >/dev/null 2>&1; then
    (cd repo/x86_64 && rm -f mikesolar.db mikesolar.files mikesolar.db.sig mikesolar.files.sig &&
      cp mikesolar.db.tar.gz mikesolar.db && cp mikesolar.files.tar.gz mikesolar.files &&
      cp mikesolar.db.tar.gz.sig mikesolar.db.sig && cp mikesolar.files.tar.gz.sig mikesolar.files.sig)
    cp mikesolar.pub repo/ 2>/dev/null || true
    rclone sync repo/ "r2:$R2_BUCKET/pacman"
    echo "REPO_UPDATED"
fi

python3 scripts/finalize.py
