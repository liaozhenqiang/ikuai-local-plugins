# plugins/ —— 我这条 iKuai 上在跑的其它插件

这里放的是除 [devmon](../devmon/README.md) 之外、我按同一套插件框架做的 **iKuai 集成层源码**：
`Release` / `install.sh` / `boot.sh` / `uninstall.sh`、后端 `function/*`、`bin/*ctl` 控制脚本、
`www/plugins/**` 卡片与页面，以及必要的默认配置。

**第三方程序本体没有放进仓库**——它们体积大（几个到几百 MB）、各有自己的许可证和发布渠道，
请按各自的上游获取后放到对应位置。所以这里的目录是「源码 / 集成层」，不是能直接安装的成品包。

| 插件 | 版本 | 作用 | 仓库里有 | 需要自己补 |
| --- | --- | --- | --- | --- |
| [adguardhome](adguardhome/) | 0.107.79.3 | AdGuard Home 广告拦截（DNS） | 集成层 + `share/AdGuardHome.yaml.default` | `share/AdGuardHome` 静态二进制 |
| [alist](alist/) | 3.65.0 | AList 网盘聚合（WebDAV/多网盘） | 集成层 | `share/alist` 二进制 |
| [aria2](aria2/) | 1.0.4 | aria2 下载器 + AriaNg 界面 | 集成层 + `aria2_page_check.js` | `bin/aria2c`、`www/plugins/app/aria2ng.html` |
| [awesun](awesun/) | 1.0.0 | 向日葵远程控制 + 虚拟桌面（X11） | 集成层 + `bin/*` 渲染/键鼠脚本 | `payload/`（向日葵 Linux 客户端、Xvfb 等） |
| [bnfix](bnfix/) | 1.0.0 | 修系统 `libcrypto.so.1.0.0` 里 `BN_mod_sqrt` 死循环（1 字节补丁） | 补丁描述 + 控制脚本 | 无（作用于系统库，按你的固件版本核对偏移） |
| [ddnsgo](ddnsgo/) | 6.17.7 | ddns-go 动态域名解析 | 集成层 | `share/ddns-go` 二进制 |
| [frpc](frpc/) | 0.71.1.1 | FRP 内网穿透（客户端） | 集成层 + 页面 | `share/frpc` 二进制 |
| [frps](frps/) | 0.71.1.1 | FRP 内网穿透（服务端） | 集成层 + 页面 | `share/frps` 二进制 |
| [gecoos](gecoos/) | 2.2.20251015.1 | 集客 AC 无线控制器 | 集成层 | `share/ac` 二进制 |
| [ikupd](ikupd/) | 1.0.0 | 插件在线升级（从 GitHub Release 检查/下载/安装） | 全部 | 无 |
| [miot-panel](miot-panel/) | 1.1.1 | 米家墙面板（设备控制/摄像头/音乐，跑在路由器本机） | 集成层 + 菜单补丁 | `app/`、`payload/`、`site/`；`runtime/python` 由 `install.sh` 在线下载 |
| [npc](npc/) | 0.26.39.2 | npc 内网穿透客户端 | 集成层 + 页面 | `share/npc` 二进制 |
| [nps](nps/) | 0.26.39.3 | nps 内网穿透服务端（默认端口 81） | 集成层 + 页面 | `share/nps` 二进制 |
| [openclash](openclash/) | 0.48.003 | OpenClash for iKuai：mihomo 内核 + 订阅 + 透明代理 | 集成层（`bin/occtl`、`function/openclash`、页面、`share/conf/template.yaml`、`openclash-guard.sh`） | `bin/mihomo`、`share/geo/*`、`share/ui/zashboard/*` |
| [ttyd](ttyd/) | 1.7.7 | 浏览器里的 root 终端 | 集成层 | `share/ttyd` 二进制 |

## 怎么装

补齐上表「需要自己补」的文件后，把插件目录按 iKuai 插件包格式打成 zip（顶层就是
`Release`/`install.sh`/`bin`/`function`/`www`/`share`）：

```bash
cd plugins/ttyd && zip -r ../../dist/ttyd.zip .      # 或 bash build.sh 里同样的做法
```

然后在「高级应用 → 插件管理」上传，或 SSH `ikplugin install /root/ttyd.zip`。

## 注意

* 插件以 root 运行，并且都会修改 `/usr/ikuai`（菜单/SPA 路由/i18n）或启动常驻进程。
  **装之前先读 `install.sh` 和 `function/*`**，确认它在你机器上要做什么。
* 这些集成层是按我这台 **iKuai 3.7.16 x64 Build202411141700** 写的：二进制路径、服务名、
  菜单锚点都依赖这个固件版本，换版本可能要重新适配。
* 二进制版本号我按装在这台机器上的写；你要换新版本，注意 `bin/*ctl` 里可能按版本号做过判断。
