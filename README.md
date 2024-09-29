# org.deepin.base.flatpak

将 flatpak 的 runtime 转换为 linglong 的 base

## 用法

`./mkbase.bash org.kde.Platform 5.15-23.08`

执行上述命令会将 flatpak 的 org.kde.Platform/5.15-23.08 转换为玲珑的 org.deepin.base.flatpak.kde/5.15.23.0

如果同一个 Platform 需要进行更新，可以在命令后面再加一个打包版本号，例如`./mkbase.bash org.kde.Platform 5.15-23.08 1` 会转换为玲珑的 org.deepin.base.flatpak.kde/5.15.23.1

需要注意的是，如果同一个 Platform 版本号包含前置 0，例如 org.kde.Platform/23.08 这种，会去掉前置 0 转换后的版本是 23.8.0.0，这是因为玲珑的版本号不能包含前置 0。

## 项目文件

patch_rootfs/etc/linglong-triplet-list 玲珑独有的文件， 用于表明 base 支持的架构列表
patch_rootfs/etc/ld.so.conf 用于给 ldconfig 提供配置，引用 ld.so.conf.d 目录下的配置
patch_rootfs/etc/ld.so.conf.d/x86_64-linux-gnu.conf 复制于 deepin 23，提供基础配置
patch_rootfs/etc/ld.so.conf.d/zz_deepin-linglong-app.conf 空文件，提供一个挂载点
patch_rootfs/etc/ld.so.conf.d/gl.conf opengl 相关的配置，提供 opengl 相关库的搜索路径

patch_rootfs/etc/profile 用于给 bash 提供配置，引用 profile.d 目录下的配置
patch_rootfs/etc/profile.d/linglong.sh 用于配置玲珑应用环境变量
patch_rootfs/etc/profile.d/plugins.sh 用于添加 QT_PLUGIN_PATH 路径

patch_rootfs/usr/bin/xdg-email 和/usr/bin/xdg-open 通过 dbus 调用宿主机
patch_rootfs/app 软链接用于模拟 flatpak 的 app 目录，由于 linglong 的 app 目录包含应用 ID, 所以 base 的 /app 指向 /run/linglong/app ，应用再运行时创建 /run/linglong/app 软链接指向真实的 /opt/apps/$APPID/files

refs.sh 用于生成 refs.list 文件，方便查看 flathub 的所有 ref，并且会批量下载所有 Platform（被视为玲珑的 base） 皆为的 ref

platforms.list 是经过测试可用的 Platforms，可使用 `cat supports.list | xargs -i sh -c "./mkbase.bash {}; ll-builder push --no-develop -v"` 批量更新
