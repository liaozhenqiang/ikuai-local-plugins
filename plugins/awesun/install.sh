#!/bin/bash
# awesun 插件安装动作（框架在"安装/升级"时调用，必须幂等）
export PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
exec "$PLUGIN_DIR/bin/awesunctl" setup
