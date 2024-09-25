#!/bin/sh
if [ -n "$QT_PLUGIN_PATH" ]; then
    # xcb插件放在/usr/plugins目录，但metadata的Environment没有包含这个目录，暂不知道原因
    export QT_PLUGIN_PATH="/usr/plugins:$QT_PLUGIN_PATH"
fi