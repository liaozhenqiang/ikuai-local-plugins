# devmon —— 本地周边设备监控

> 基于 [deadash/ikuai-plugins](https://github.com/deadash/ikuai-plugins) 的插件模板与开发技能
> （v0.0.9 那批 [Releases](https://github.com/deadash/ikuai-plugins/releases) 里的示例插件包 +
> `.codebuddy/skills/ikuai-plugin-dev/assets/template/`）开发；归属与授权范围见[仓库根 README](../README.md)。

iKuai「状态监控」下的 **摄像头监控 / 交换机监控 / 周边设备监控** 三个页面原本要绑云平台才能用。
本插件把它们**合并成一个本地「周边设备监控」入口**（菜单位置不变，另两项从菜单里去掉），
数据、在线状态、管理全在路由器本地。

## 功能

* **设备清单**：名称、IP、MAC、类别（摄像头 / 交换机 / 周边设备）、品牌、型号、hostname、
  位置、备注、端口、Web/RTSP/SSH 链接；按名称/IP/MAC/型号/备注搜索，按在线状态筛选
* **在线监控**：ping + iKuai 终端列表双判定（摄像头/交换机不一定回 ping），连续 N 轮都没信号才离线；
  守护进程每轮自动检测，上下线写事件流水
* **新设备自动收录**：终端列表里出现、清单里没有的 MAC 自动按「周边设备」入库，
  名称取「终端备注 → 型号 → hostname → MAC」，同时带品牌/型号/hostname/IP；
  **手动删除过的设备进忽略名单，不会被自动加回来**（再手动添加一次即解除）
* **字段自愈**：清单里空着的品牌/型号/hostname/名称由终端列表补全；**不覆盖你改过的值**，也不改类别
* **局域网发现**：扫描 ARP + iKuai 终端列表，显示品牌/型号/备注/在线状态，勾选后批量导入并指定类别
* **管理**：新增、编辑、暂停/启用（暂停后不检测，保留记录）、删除（带确认）、立即检测
* **设置**：检测间隔（10–3600 秒）、离线判定（连续 2–20 轮）、自动收录开关
* **零外部依赖**：只用设备自带的 bash + jq + sqlite3；不采集设备 token、不联网上报

**不做的**：摄像头 PTZ/录像、交换机端口开关等厂商级控制 —— 需要具体品牌的 API/协议/账号，
通用插件不内置；页面提供「打开」设备自己的 Web/RTSP/SSH 链接。

## 页面结构

一个页面（iframe 指向 `/plugins/app/devmon.html`，不再按类别分页）：

| 区块 | 内容 |
| --- | --- |
| 顶部 | 「周边设备监控」标题、状态徽标、刷新 / 立即检测 / 扫描发现 / 添加设备 |
| 统计卡 | 设备总数、在线、离线、已暂停 |
| 设备清单 | 类别单选（全部/摄像头/交换机/周边设备）+ 搜索 + 状态筛选 + 表格（编辑 / 暂停 / 删除） |
| 监控设置 | 检测间隔、离线判定、自动收录开关、保存 |
| 最近事件 | 时间、设备、事件（新增/上线/离线）、详情（手动添加 / 自动收录 / iKuai 终端 / ping 响应） |
| 说明折叠区 | 能做什么、不做什么、发现原理 |

「扫描发现」弹窗：勾选要导入的设备（已管理的不可重复选），选导入到哪个类别，批量导入。

## 菜单是怎么改的

`share/menu_patch.sh` 做三件事（幂等、可回退）：

1. 在 `app.<hash>.js.gz` 里加一条 iframe 路由 `devmon-peripheral` → `/plugins/app/devmon.html`
   （打补丁前会先删掉历史版本插入的 `devmon-camera` / `devmon-switch` / 带 `?cat=` 的旧路由，
   所以从 1.0.0 升级不需要重启）
2. `menu.json` 里**删掉**摄像头监控、交换机监控两个叶子，把「周边设备监控」
   （`tools.instrumented`）的 `linkTo` 改成 `devmon-peripheral`
3. 给三份 i18n 加页面标题 `page-title.devmon.*`

改前的 `menu.json` / `app.js.gz` / i18n 备份在插件 `data/menu-backup/`（**只写一次**，
保证里面永远是没有 devmon 痕迹的那份），卸载时 `uninstall.sh` 自动恢复；根分区重启本身也会还原。
备份缺失时的兜底只能把链接改回云页面，被删掉的两个叶子要等重启才回来。

iKuai 的菜单由 `funcore.lua` 在 openresty 启动时缓存，所以补丁后会自动 `openresty -s reload`；
浏览器还要关闭后台标签页重开 + Ctrl+F5（菜单/JS 有缓存）。老云平台页面没删，直接访问旧路由仍能打开。

## 发现的三个数据源

1. **iKuai 终端列表**（`/usr/ikuai/function/monitor_lanip show TYPE=data`）：主要来源，
   提供 `client_model` / `hostname` / `client_device` / `client_type` / `comment`，
   随机 MAC 的手机/平板也能识别出型号
2. **ARP**（`/proc/net/arp`）：补 IP、发现没有终端记录的设备（只作发现来源，不用于在线判定）
3. **ping**：对已知 IP 探测一次，弥补终端列表的延迟

在线判定 = 出现在终端列表 **或** ping 通；自动收录只收终端列表里的设备（不收纯 ARP 条目，
避免把组播/网关这类噪音收进来）。

## 数据

| 路径 | 内容 |
| --- | --- |
| `/etc/mnt/plugins/devmon/data/devmon.db` | sqlite3：`devices`（清单）、`events`（事件）、`config`（间隔/阈值/开关）、`hidden`（删除忽略名单） |
| `data/menu-backup/` | 前端补丁前的原始文件 |
| `/etc/log/devmon.log` | 运行日志 |

`devices` 主要字段：`mac`(主键) / `ip` / `name` / `category` / `vendor` / `model` / `hostname` /
`location` / `note` / `url` / `ports` / `enabled` / `online` / `miss` / `source`(manual|auto) /
`first_seen` / `last_seen` / `last_online` / `last_offline`。

## 命令行

```bash
devmon status
devmon devices [camera|switch|peripheral|all]
devmon scan                      # 发现候选（JSON）
devmon save <mac> <ip> <cat> <name> <vendor> <model> <hostname> <location> <note> <url> <ports> <enabled>
devmon toggle <mac> 0|1
devmon forget <mac>              # 删除并记入忽略名单
devmon observe                   # 立即检测一轮（含自动收录）
devmon set interval 60
devmon set auto_add 0|1
devmon daemon-start|daemon-stop
```

## Web 后端（function/devmon）

`show`（`TYPE=data` 清单 / `TYPE=scan` 发现）、`save`、`toggle`、`forget`、`seting`、`refresh`。

> **框架约定（踩过的坑）**：iKuai 的 `/Action/call` 只把 **`show` 动作**的 stdout 解析成 `Data`，
> 其它动作成功时 stdout 一律丢弃（失败时 stdout 才是 `ErrMsg`）。所以局域网发现不能做成
> `scan` 动作，只能挂在 `show TYPE=scan` 上；写动作成功时也不要 `echo`。
> 参数值不能带空格（前端把空格编码成 `+`，后端 `tr '+' ' '` 还原），中文可以正常传。
> 同一台设备上 ttyd 插件的注释里也记录了这条约束。

## 安装 / 升级 / 卸载

```bash
ikplugin install /root/devmon-v1.1.0-plugin.zip   # 或插件管理页面上传
ikplugin remove devmon                            # 恢复菜单/路由/语言文件
```

升级到新版本后如果菜单没变，关掉后台标签页重开 + Ctrl+F5。
在线升级见[根 README 的「插件在线升级」](../README.md#插件在线升级ikupd)。

## 构建与测试

```bash
bash build.sh                    # => dist/devmon-v<version>-plugin.zip（需 python3 或 zip）
bash tests/smoke.sh              # 34 项：清单、发现、导入、在线/离线、暂停、删除、自动收录、守护进程
```

冒烟测试用假 ARP / 假终端列表 / 假 ping，不碰系统路径，本机有 jq + sqlite3 即可跑。
有 `zip` 时直接用；没有时用 Python 兜底（保留 `install.sh`/`bin`/`function` 的执行位），
`PYTHON=/path/to/python3 bash build.sh` 可显式指定解释器。

`tools/mp_test.sh` 在**隔离副本**上验证前端菜单补丁（单入口 → 幂等 → 完全还原）：
把 `pkg/share/menu_patch.sh` 和它传到设备 `/tmp` 跑，不会动真实前端
（本地 Windows jq 会输出 CRLF，比较结果不可信，所以放设备上跑）。

## 已知限制

* 只做本地监控/管理，不做厂商级设备控制（PTZ、端口开关、重启摄像头等）
* 型号/品牌来自 iKuai 终端识别，个别机型可能识别成相近型号，可在页面手动改（只补空值、不覆盖）
* 端口字段只记录/展示，不做 TCP 探测；在线由 ping + 终端列表判定
* 自动收录只认终端列表；只在 ARP 里出现、终端列表没有的设备需要用「扫描发现」手动导入
* 菜单改动作用于 iKuai 官方前端；换固件版本后若锚点/菜单结构变了，补丁会 fail-safe 跳过
  （菜单不接管，插件卡片仍可用），需要重新适配
* 「状态监控 → 终端监控 → IPv4/IPv6 终端详情」里的「终端类型/设备厂商 Unknown/Unknown」
  是另一个页面/字段，本插件不修改那个详情页

## 真机验证记录（iKuai 3.7.16 x64 Build202411141700）

* 菜单只剩「周边设备监控」，页面与标签页标题正确，一页显示全部设备，类别作为页内筛选
* 单入口补丁：三入口现状 → apply 后路由 `cam=0 sw=0 per=1`、菜单叶子 9→7 → 再 apply 字节级一致 →
  remove 后 app.js/menu.json 与改前完全一致；打补丁后的 app.js 过 `node --check`
* 扫描发现 30 台候选，带型号/hostname/备注；导入、编辑、暂停/启用、删除、立即检测、设置保存均通过
* 自动收录在真实终端数据上验证：空库一轮收 28 台（类别=周边设备、来源 auto），
  删除后不再复活，关掉开关后不再进；中文名称/备注全链路正常
* 设备重启后 `/root` 被清空但 `/etc/mnt` 保留：清单、菜单补丁（boot.sh 重打）、守护进程都正常
