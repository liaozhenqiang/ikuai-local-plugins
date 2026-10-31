# plugins/ —— 我这台 iKuai 上在用的社区插件

除 [devmon](../devmon/README.md) 之外、按同一套插件框架做的 **iKuai 集成层**：
`Release` / `install.sh` / `boot.sh` / `uninstall.sh`、后端 `function/*`、`bin/*ctl` 控制脚本、
`www/plugins/**` 卡片与页面，以及必要的默认配置。

各组件的**第三方程序本体不放进仓库**（体积大、各有许可证和发布渠道），但
[Releases](../../releases) 里每个插件都提供**含程序本体的完整包**，可直接安装、也能被 ikupd 升级。

## 一览

| 插件 | 版本 | 功能 | 形态 | 完整包 |
| --- | --- | --- | --- | --- |
| [adguardhome](adguardhome/) | 0.107.79.3 | 局域网 DNS 广告/追踪拦截：启停、重启、监听端口、上游 DNS、运行日志（查看/清空） | 后端 + 页面 | ✅ |
| [alist](alist/) | 3.65.0 | 网盘聚合（阿里云盘/115/天翼云盘/夸克/OneDrive…）统一 Web 与 WebDAV：自启、端口、一键打开管理界面 | 启动器 + 页面 | ✅ |
| [aria2](aria2/) | 1.0.4 | 多协议下载（HTTP/FTP/BT/磁力）+ AriaNg 界面：RPC 密钥、下载目录、启停、日志 | 后端 + 页面 | ✅ |
| [bnfix](bnfix/) | 1.0.0 | 修系统 `libcrypto.so.1.0.0` 里 `BN_mod_sqrt()` 的死循环（1 字节补丁 `je`→`jle`）：状态、单点校验、完整校验、重启 | 后端 + 页面 | ✅ |
| [ddnsgo](ddnsgo/) | 6.17.7 | ddns-go 动态域名客户端：启停、重启、监听端口、日志 | 后端 + 页面 | ✅ |
| [frpc](frpc/) | 0.71.1.1 | FRP 客户端：服务端地址/token、多条 tcp/udp/http/https 代理规则增删、启停、日志 | 后端 + 页面 | ✅ |
| [frps](frps/) | 0.71.1.1 | FRP 服务端：通信端口、仪表盘端口、认证 Token 自动生成、启停、日志 | 后端 + 页面 | ✅ |
| [gecoos](gecoos/) | 2.2.20251015.1 | 集客 AC：集中管理集客 AP、管理端口、AP 通信端口、公网访问开关（默认仅内网）、Web 密码 | 后端 + 页面 | ✅ |
| [miot-panel](miot-panel/) | 1.1.4 | 米家墙面板（设备控制/摄像头/音乐中心）：内置 Songloft/go-music-dl/FFmpeg，装好即用；启停、端口、日志、一键打开面板 | 后端 + 页面 | ✅ |
| [npc](npc/) | 0.26.39.2 | NPC 内网穿透客户端：装好即自启，卡片直达其自身管理界面 | 启动器 + 页面 | ✅ |
| [nps](nps/) | 0.26.39.3 | NPS 内网穿透服务端：默认端口 81，自启，卡片直达 Web 管理 | 启动器 + 页面 | ✅ |
| [openclash](openclash/) | 0.48.003 | mihomo(Meta) 内核 + 订阅导入/转换 + 透明代理（redirect/tproxy/tun）+ 原生 Web 控制台：配置/订阅/规则/节点/延迟/旁路/自检/日志 | 后端 + 页面 | ✅ |
| [ttyd](ttyd/) | 1.7.7 | 浏览器里的 root 终端：启停、自定义端口、访问口令 | 后端 + 页面 | ✅ |

**形态说明**：`后端 + 页面` = 有 `function/<插件名>` 接口，卡片页里能直接启停/改配置/看日志；
`启动器 + 页面` = 没有自定义后端，`install.sh`/`boot.sh` 拉起进程，页面只负责打开它自己的管理界面。

**源码里缺的二进制**（只有自己重新打包时才需要补）：`AdGuardHome`、`alist`、`ddns-go`、`ttyd`、
`frpc`/`frps`、`npc`/`nps`、`gecoos` 的 `share/ac`、`aria2c` 与 AriaNg、openclash 的
`bin/mihomo` + `share/geo/*` + `share/ui/zashboard/*`、miot-panel 的 `app/ payload/ site/`（1.1.4 完整包还内置 `Songloft`、`go-music-dl`、`FFmpeg/FFprobe` 和音乐插件）。

> `awesun`（向日葵远程控制）和 `ikupd`（插件在线升级）**不在本仓库**：
> 前者是厂商闭源客户端，后者用上游 [deadash/ikuai-plugins](https://github.com/deadash/ikuai-plugins/releases) 的包。

## 安装

从 [Releases](../../releases) 下载对应 `<插件名>-v<版本>-plugin.zip`：

```bash
ikplugin install /root/ttyd-v1.7.7-plugin.zip
```

或在「高级应用 → 插件管理」上传；卸载 `ikplugin remove <插件名>`。

## 自己打完整包

```bash
# 在路由器上：把已安装的插件连同二进制打回安装包（排除 data/、日志、旧签名清单）
bash tools/pack-on-device.sh ttyd     # => /tmp/ttyd-v1.7.7-plugin.zip + sha256
gh release upload <tag> ttyd-v1.7.7-plugin.zip
```

包名必须守 `<插件名>-v<版本>-plugin.zip`，ikupd 只认这个格式；
详见[根 README 的「插件在线升级」](../README.md#插件在线升级ikupd)。

## 注意

* 插件以 **root** 运行，并且会修改 `/usr/ikuai`（菜单 / SPA 路由 / i18n）或启动常驻进程。
  **装之前先读 `install.sh` 和 `function/*`**。
* 集成层按 **iKuai 3.7.16 x64 Build202411141700** 编写/验证：二进制路径、服务名、
  菜单锚点都依赖这个固件版本，换版本可能要重新适配。
* 安装会**替换整个插件目录**，只保留 `data/`（证书 / 配置 / 数据库）；升级前别手改插件目录里的文件。
* 发布包**不含 `data/`**：那里有证书、token、清单和数据库，不随包分发。
* miot-panel 的 Python 运行时是 **x86_64** 的，并且依赖插件自带的 `runtime/lib/ld-linux-x86-64.so.2`：
  iKuai 是 uClibc，系统里没有 glibc 的 `/lib64/ld-linux-x86-64.so.2`，所以启动必须用自带 loader 显式引导
  （1.1.3 起已改成这样；1.1.2 及更早会在日志里报 `env: can't execute ...: No such file or directory`）。
