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
project=$PWD
workdir=$(mktemp -d -p "$project")
mkdir -p "$workdir/binary"
mkdir -p "$workdir/develop"

# 转换为玲珑的应用ID，规则是将runtime名称按'.'分割，取第二位 如 org.kde.Platform生成org.deepin.base.flatpak.kde
export APPID="org.deepin.base.flatpak.$(echo "$appid"|awk -F'.' '{print $2}')"
# 转换为玲珑的版本，规则是按'.'和'-'分割取前三位，不足三位补0，再末尾补充输入的打包版本号，如 5.15-23.08 生成 5.15.23.0
# 如果某位版本号以0开头，去掉0，如 5.15-23.08 生成 5.15.23.8
export VERSION="$(echo "${version/.0/.}.0.0.0" | awk -F'[-.]' 'BEGIN {OFS="."} {print $1,$2,$3}').$tweak"
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

# 将 metadata 的 Environment 保存到 /etc/profile.d/0flatpak.sdk.sh
if grep '^\[Environment\]' "$workdir/binary/files/metadata"; then
    mkdir -p "$workdir/binary/files/etc/profile.d"
    profile="$workdir/binary/files/etc/profile.d/10flatpak.sdk.sh"
    echo "#!/bin/sh" > "$profile"
    grep -A 1000 '^\[Environment\]' "$workdir/binary/files/metadata" | # 匹配 [Environment] 后面的内容
        sed -n '1!p' | # 去除 [Environment] 这一行
        grep -B 1000 -m 1 '^\[' | # 匹配下一个[开头之前的内容
        sed -n '$!p' | # 去除下一个[开头的行
        sed 's/ //g' | # 去除所有空格
        xargs -i echo export {} | # 在每行前面添加export
        cat >> "$profile" # 保存文件
    sed -i "s#/app/#/opt/apps/\$LINGLONG_APPID/files/#g" "$profile"
fi

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

# 给base添加一些必要的文件
# etc/ld.so.conf 用于给ldconfig提供配置，引用 ld.so.conf.d 目录下的配置
# etc/ld.so.conf.d/x86_64-linux-gnu.conf 复制于deepin 23，提供基础配置
# etc/ld.so.conf.d/zz_deepin-linglong-app.conf 空文件，提供一个挂载点
# etc/ld.so.conf.d/gl.conf opengl相关的配置，提供opengl相关库的搜索路径

# etc/profile 用于给bash提供配置，引用 profile.d 目录下的配置
# etc/profile.d/linglong.sh 用于配置玲珑应用环境变量

# /usr/bin/xdg-email和/usr/bin/xdg-open 通过dbus调用宿主机
cp -rP $project/patch_rootfs/* ./

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