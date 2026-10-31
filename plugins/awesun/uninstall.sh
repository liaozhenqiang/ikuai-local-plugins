#!/bin/bash
# awesun 插件卸载动作：停进程、清软链。
# 注意：**不动** /etc/log/awesun（runtime + 身份凭证备份），重装后无需重新登录。
export PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
exec "$PLUGIN_DIR/bin/awesunctl" stop
