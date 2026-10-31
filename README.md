# ikuai-local-plugins

自己写的两个 iKuai（爱快）软路由插件，加上**我这台路由器上在跑的其它 15 个社区插件的集成层源码**
（AdGuard Home / AList / aria2 / OpenClash / FRP / NPS / TTYD …，见 [plugins/](plugins/README.md)）。
目标都是：不绑定爱快云，也能在本地看到/管住路由器上的服务。纯 shell + Lua + 前端补丁，
不需要额外的服务器、Docker 或主机。

| 目录 | 状态 | 作用 |
| --- | --- | --- |
| [devmon](devmon/README.md) | **在用 / 1.1.0** | 把「状态监控」下被云平台拦住的摄像头/交换机/周边设备三个页面合并成一个本地「周边设备监控」：设备清单、品牌型号、在线/离线、增删改、局域网发现导入、新设备自动收录 |
| [mimon](mimon/README.md) | 已废弃（存档） | 小米/米家设备发现与监控（ARP + IEEE OUI + miIO DID + iKuai 终端列表取型号）。已从设备卸载、不再更新，只作为那几段发现实现的参考 |
| [plugins/](plugins/README.md) | 在用（集成层） | 15 个社区插件的 iKuai 集成层源码：AdGuard Home、AList、aria2、awesun、bnfix、ddns-go、frpc/frps、集客AC、ikupd、miot-panel、npc/nps、OpenClash、TTYD。第三方二进制不入库，需按上游自行补齐 |

## 运行环境

在 iKuai **3.7.16 x64 Build202411141700** 上开发并真机验证。设备侧只有这些可用，代码都按此约束写：

* `jq` **1.4**（没有 `--argjson` / `--indent` / 组合 `-cn`）、`sqlite3` **3.8.11.1**（没有 UPSERT / RETURNING / json1）
* `bash` + busybox（没有 python / node / timeout / nohup / setsid，`ps` 功能很弱）
* `LuaJIT 2.1` + `cjson` + `lsqlite3`（mimon 的 miIO 发现用）
* 持久分区只有 `/etc/mnt` 和 `/etc/log`；**根分区每次重启还原**，所以开机脚本要重打前端补丁

其它固件版本没有验证过；前端补丁是 fail-safe 的（锚点找不到就跳过，不会写坏菜单或静态资源）。

## 安装

从 [Releases](releases) 下载 zip，在 iKuai「高级应用 → 插件管理」里上传安装；或 SSH：

```bash
ikplugin install /root/devmon.zip
devmon status            # 或 /usr/ikuai/function/devmon show TYPE=data
```

卸载 `ikplugin remove devmon` 会把菜单/路由/语言文件从备份恢复。

> ⚠️ 这两个插件会**修改 iKuai 官方前端**（`json/menu.json`、`static/js/app.<hash>.js.gz`、
> 三份 i18n），不是纯插件卡片。改之前都会备份到插件自己的 `data/menu-backup/`，
> 补丁后自动 `openresty -s reload`（菜单在 openresty 启动时被缓存）。
> 浏览器侧还要关掉后台标签页重开 + Ctrl+F5，否则看到的是缓存的旧菜单。
> 自行评估风险；重启设备本身也会让根分区还原成固件原始状态。

## 构建

```bash
cd devmon && bash build.sh      # => dist/devmon.zip（需要 zip，或 PYTHON=/path/to/python3）
cd devmon && bash tests/smoke.sh   # 需要 jq + sqlite3；假 ARP/终端列表/ping，不碰系统路径
```

`devmon/tools/mp_test.sh` 用来在**隔离副本**上验证前端菜单补丁（三入口→单入口→幂等→完全还原），
需要把 `menu_patch.sh` 和它传到设备上跑，不会动真实前端。

## 已知平台约束（踩坑记录）

* `/Action/call` **只把 `show` 动作的 stdout 解析成 `Data`**，其它动作成功时输出被丢弃。
  所以「读」类接口必须挂 `show TYPE=xxx`，写动作成功时不要 `echo`。
* 后端参数值不能带空格（前端编码成 `+`，后端还原），中文可以正常传。
* `json_append __json_result__ key:json` 读的是**同名 shell 变量**。
* 详见 [devmon/README.md](devmon/README.md)。

## 基于 / 致谢

本仓库的插件是**基于 [deadash/ikuai-plugins](https://github.com/deadash/ikuai-plugins) 开发**的。
具体的模板与开发技能来自它的 [Releases](https://github.com/deadash/ikuai-plugins/releases)
（v0.0.9 那批示例插件包）以及仓库内的
`.codebuddy/skills/ikuai-plugin-dev/`（技能文档 + `assets/template/` 模板插件）。
沿用/改写的部分：

* 插件包结构与生命周期脚本：`Release` / `install.sh` / `boot.sh` / `uninstall.sh`，
  `bin/*`、`function/*` 挂到 `/usr/ikuai` 的安装方式，卸载即清理
* `function/<name>` 后端接口写法（`#!/bin/bash /etc/ikcommon`、`show` / `json_append` 约定）
* 改前端菜单/路由的思路与 `app.<hash>.js.gz` 解压-原地插入-重压-校验的做法
* `build.sh` + `tools/zip_pkg.py` 打包脚本骨架（保留 exec 位、`create_system=3`）

设备侧框架（`ikcommon`、`funcore`、插件管理器）属于 iKuai 固件本身，与上述两方无关。

> 上游仓库**没有附开源许可证**（版权归其作者）。因此：本仓库**只对自己编写/改写的那部分代码**
> 按 [MIT](LICENSE) 授权；从上游模板沿用或衍生的部分仍归原作者，若你要单独再分发这部分，
> 请先联系上游作者获得许可。感谢 deadash 把插件通道、接口约定和踩坑记录整理成技能。

## 隐私

两个插件都只在路由器本地运行：不上传任何数据、不请求外部服务、**不采集米家设备 token**、
不需要爱快云账号。设备清单存在 `/etc/mnt/plugins/devmon/data/devmon.db`。

## License

本仓库自行编写的代码按 MIT 授权，见 [LICENSE](LICENSE)；
从 [deadash/ikuai-plugins](https://github.com/deadash/ikuai-plugins) 模板沿用/衍生的部分
不在此授权范围内（上游未附许可证），详见上面「基于 / 致谢」。
