#!/bin/bash
# 在 archlinux 容器中：检查 AUR 更新 → 构建 → 更新 repo db → 同步 R2 → 提交版本状态
set -euo pipefail
export PACKAGER="mikesolar-bot <mike@mikesolar.dev>"

pacman -Syu --noconfirm --needed base-devel git python sudo rclone >/dev/null
useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

# 拉取现有仓库（首次为空）
mkdir -p repo out
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"
rclone sync "r2:$R2_BUCKET/pacman" repo/ || true

python3 scripts/plan.py
if [ ! -s build-list.txt ]; then
    echo "全部最新，无事发生"
    exit 0
fi

while read -r pkg; do
    echo "=== 构建 $pkg ==="
    rm -rf /home/builder/build
    cp -r "/tmp/src/$pkg" /home/builder/build
    chown -R builder:builder /home/builder/build
    if (cd /home/builder/build && runuser -u builder -- makepkg -s --noconfirm); then
        cp /home/builder/build/*.pkg.tar.zst out/ 2>/dev/null || echo "NO_PKG $pkg" >> failed.txt
    else
        echo "BUILD_FAIL $pkg" >> failed.txt
    fi
done < build-list.txt

# 只有成功产出才更新仓库
if ls out/*.pkg.tar.zst >/dev/null 2>&1; then
    mkdir -p repo/x86_64
    cp out/*.pkg.tar.zst repo/x86_64/
    (cd repo/x86_64 && repo-add mikesolar.db.tar.gz ./*.pkg.tar.zst)
    # R2/S3 不支持符号链接，展开为副本
    (cd repo/x86_64 && rm -f mikesolar.db mikesolar.files &&
      cp mikesolar.db.tar.gz mikesolar.db && cp mikesolar.files.tar.gz mikesolar.files)
    rclone sync repo/ "r2:$R2_BUCKET/pacman"
    echo "REPO_UPDATED"
fi

python3 scripts/finalize.py
