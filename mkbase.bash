#!/bin/bash

set -x
set -e

# flatpak runtime名称
appid=$1
# flatpak runtime版本
version=$2
# 打包版本号，默认为0
tweak=${3:-"0"}

# 常量定义
readonly SCRIPT_DIR="$PWD"
readonly FLATHUB_REPO_URL="https://dl.flathub.org/repo/"
readonly LINGLONG_REPO_URL="https://repo-dev.cicd.getdeepin.org"
readonly PROFILE_SCRIPT_NAME="10flatpak.sdk.sh"

# flatpak runtime在ostree中的分支名
ref="flathub:runtime/$appid/x86_64/$version"

# 创建临时工作目录
project="$SCRIPT_DIR"
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

# 重试执行函数
retry_command() {
    local max_attempts=5
    local attempt=1
    local cmd="$1"
    local description="$2"
    
    while (( attempt <= max_attempts )); do
        echo "$description (try $attempt/$max_attempts)"
        if eval "$cmd"; then
            echo "$description succeeded"
            return 0
        else
            log_warn "$description failed (try $attempt/$max_attempts)，five seconds later retry..."
            sleep 5
        fi
        (( attempt++ ))
    done
    
    log_error "$description 在 $max_attempts 次尝试后仍然失败"
    return 1
}

# 初始化ostree仓库
ostree init --repo=flathub --mode bare-user-only
ostree --repo=flathub remote delete --if-exists flathub
ostree --repo=flathub remote add --no-sign-verify flathub $FLATHUB_REPO_URL

# 下载flatpak的platform
ostree --repo=flathub refs | grep "$ref" || {
    retry_command "ostree --validate depend versionrepo=flathub pull '$ref'" "下载 flatpak platform $ref"
}
ostree --repo=flathub checkout "$ref" "$workdir/binary/files"
# 获取runtime的gl扩展的版本
glVersion=$(grep -A100 'Extension org.freedesktop.Platform.GL' "$workdir/binary/files/metadata" |grep -E '^versions|Extension'|head -n2|grep versions|awk -F'[=;]' '{print $2}'|xargs)

# 仅支持最新安装到 lib/x86_64-linux-gnu/GL 的GL版本，其他版本还未测试
if ! grep -A100 'Extension org.freedesktop.Platform.GL' "$workdir/binary/files/metadata" |grep -E 'directory|Extension'|head -n2|grep lib/x86_64-linux-gnu/GL; then
    echo "暂不支持依赖 $glVersion 版本的GL扩展"
    exit -1
fi

# 下载GL扩展
mkdir -p "$workdir/binary/files/files/lib/x86_64-linux-gnu/GL"
glRef="flathub:runtime/org.freedesktop.Platform.GL.default/x86_64/$glVersion"
ostree --repo=flathub refs | grep "$glRef" || {
    retry_command "ostree --repo=flathub pull '$glRef'" "下载 GL 扩展 $glRef"
}
ostree --repo=flathub checkout --subpath=files "$glRef" "$workdir/binary/files/files/lib/x86_64-linux-gnu/GL/default"

# 将 metadata 的 Environment 保存到 /etc/profile.d/10flatpak.sdk.sh
if grep '^\[Environment\]' "$workdir/binary/files/metadata"; then
    mkdir -p "$workdir/binary/files/etc/profile.d"
    profile="$workdir/binary/files/etc/profile.d/$PROFILE_SCRIPT_NAME"
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
rm -rf etc/ssl/certs

# 给base添加一些必要的文件，文件具体作用见 README.md
cp -rP $project/patch_rootfs/* ./

# 创建etc/resolv.conf
rm -f etc/resolv.conf || true
touch etc/resolv.conf || true


# 创建缺失的目录
mkdir tmp || true
mkdir dev || true
mkdir sys || true

rm -rf "$workdir/binary/files/lib/systemd" || true

# 打包为tar格式
cd $project
tar -czf "${APPID}_${VERSION}_binary.tgz" -C $workdir/binary .
# develop和binary共用同一个files目录
mv "$workdir/binary/files" "$workdir/develop/"
tar -czf "${APPID}_${VERSION}_develop.tgz" -C $workdir/develop .

# 清理临时工作目录
rm -rf "$workdir"