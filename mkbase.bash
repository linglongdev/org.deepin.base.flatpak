#!/bin/bash

set -x
set -e

# flatpak runtime名称
appid=$1
# flatpak runtime版本
version=$2
# 打包版本号，默认为0
tweak=${3:-"0"}

# flatpak runtime在ostree中的分支名
ref="flathub:runtime/$appid/x86_64/$version"

# 创建临时工作目录
workdir=$(mktemp -d)
mkdir -p "$workdir/binary"
mkdir -p "$workdir/develop"

# 转换为玲珑的应用ID，规则是将runtime名称按'.'分割，取第二位 如 org.kde.Platform生成org.deepin.base.flatpak.kde
export APPID="org.deepin.base.flatpak.$(echo "$appid"|awk -F'.' '{print $2}')"
# 转换为玲珑的版本，规则是按'.'和'-'分割取前三位，不足三位补0，再末尾补充输入的打包版本号，如 5.15-23.08 生成 5.15.23.0
export VERSION="$(echo "$version.0.0.0" | awk -F'[-.]' 'BEGIN {OFS="."} {print $1,$2,$3}').$tweak"
# 生成linglong.yaml文件和info.json文件
envsubst < linglong.template.yaml > "linglong.yaml"
cp linglong.yaml "$workdir/binary/"
cp linglong.yaml "$workdir/develop/"
MODULE="binary" envsubst < info.template.json > "$workdir/binary/info.json"
MODULE="develop" envsubst < info.template.json > "$workdir/develop/info.json"

# 初始化ostree仓库
ostree init --repo=flathub --mode bare-user-only
ostree --repo=flathub remote add --if-not-exists --no-sign-verify flathub https://dl.flathub.org/repo/

# 下载flatpak的platform
ostree --repo=flathub refs | grep "$ref" || ostree --repo=flathub pull "$ref"
ostree --repo=flathub checkout "$ref" "$workdir/binary/files"
# 获取runtime的gl扩展的版本
glVersion=$(grep -A100 'Extension org.freedesktop.Platform.GL' "$workdir/binary/files/metadata" |grep -E '^versions|Extension'|head -n2|grep versions|awk -F'[=;]' '{print $2}'|xargs)

# 仅支持最新安装到 lib/x86_64-linux-gnu/GL 的GL版本，其他版本还未测试
if ! grep -A100 'Extension org.freedesktop.Platform.GL' "$workdir/binary/files/metadata" |grep -E 'directory|Extension'|head -n2|grep lib/x86_64-linux-gnu/GL; then
    echo "暂不支持依赖 $glVersion 版本的GL扩展"
    exit 1
fi

# 下载GL扩展
mkdir -p "$workdir/binary/files/files/lib/x86_64-linux-gnu/GL"
glRef="flathub:runtime/org.freedesktop.Platform.GL.default/x86_64/$glVersion"
ostree --repo=flathub refs | grep "$glRef" || ostree --repo=flathub pull "$glRef"
ostree --repo=flathub checkout --subpath=files "$glRef" "$workdir/binary/files/files/lib/x86_64-linux-gnu/GL/default"

cd "$workdir/binary/files"
# flatpak的platform做为base的usr目录
mv files usr
# 合并usr目录
ln -s usr/bin ./
ln -s usr/sbin ./
ln -s usr/lib ./
ln -s usr/lib64 ./
cp -r usr/etc ./

# 删除certs，因为玲珑会使用宿主机的certs目录
rm etc/ssl/certs

# 处理ldconfig，玲珑需要base包含ld.so.conf
echo 'include /etc/ld.so.conf.d/*.conf' > etc/ld.so.conf
mkdir etc/ld.so.conf.d
echo '/usr/lib/x86_64-linux-gnu/GL/default/lib' > etc/ld.so.conf.d/gl.conf
echo '# Multiarch support
/usr/local/lib/x86_64-linux-gnu
/lib/x86_64-linux-gnu
/usr/lib/x86_64-linux-gnu
/usr/lib/*' > etc/ld.so.conf.d/x86_64-linux-gnu.conf
# 提交到layer中
cd /tmp
rm -rf "$HOME/.cache/linglong-builder/layers/main/$APPID/$VERSION/x86_64" || true
mkdir -p "$HOME/.cache/linglong-builder/layers/main/$APPID/$VERSION/x86_64"
cp -r "$workdir/binary" "$HOME/.cache/linglong-builder/layers/main/$APPID/$VERSION/x86_64/"
cp -r "$workdir/develop" "$HOME/.cache/linglong-builder/layers/main/$APPID/$VERSION/x86_64/"
# develop和binary共用同一个files目录
cp -r "$workdir/binary/files" "$HOME/.cache/linglong-builder/layers/main/$APPID/$VERSION/x86_64/develop/"
# 清理临时工作目录
rm -rf "$workdir"