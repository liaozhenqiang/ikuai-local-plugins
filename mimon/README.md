# mimon —— 小米设备接入

> **已废弃（archived）**：这个插件是按当时的一个误解开发的（以为要的是「小米设备清单」），
> 实际需求后来变成了别的东西，插件已从设备上完整卸载、前端恢复原状，**当前没有任何设备在安装它，
> 也不会再更新**。源码留在这里只作 miIO 发现 / OUI 识别 / iKuai 终端列表取型号这几段实现的参考。
> 需要本地设备监控请用同仓库的 [devmon](../devmon/README.md)。

给 iKuai（爱快）路由用的第三方插件：**发现局域网里的小米/米家设备、小米路由器、小米终端，
并持续监控在线状态**。只做发现和监控，不控制设备，也不需要米家账号或设备 token。

## 功能

* **发现**：ARP + IEEE OUI（343 个小米前缀）、miIO 广播（UDP/54321，DID）、以及 **iKuai 本机终端列表**
  （`monitor_lanip`，能补上随机 MAC 的手机/平板）。
* **型号识别**：每个扫描周期读取 iKuai 终端列表的 `client_model` / `hostname` / `client_device` /
  `comment` / `client_typeid`，得到**具体型号和备注**（例如「小米AI音箱 LX04」「米家台式净饮机」
  「小米14」「红米Note 13」这类手机型号），并按 typeid + 型号关键词自动分类为
  「米家设备 / 小米路由器 / 小米终端」。
* **监控**：ping 已知 IP、miIO 应答、iKuai 终端列表里的在线条目都算在线；连续 N 轮无响应才记离线。
* **扫描**：手动「网段扫描」；也可在页面里开启周期性 /24 扫描（默认关，避免装完就扫全网段）。
* **持久**：设备、事件、配置存 sqlite3（`/etc/mnt/plugins/mimon/data/`），重启不丢；
  守护进程由 `boot.sh` 每次开机重新拉起。
* **入口**：除了「高级应用 → 插件管理」的卡片，还会在 **「状态监控」→「小米设备」** 加一个菜单项，
  点开直接是插件页（前端集成，见下文）。

## 包结构

```
pkg/
├── Release                         plugin=mimon / version / comment
├── install.sh                      建库 + 拉起守护进程（幂等）
├── boot.sh                         每次开机重新拉起
├── uninstall.sh                    停进程
├── bin/mimon                       CLI / 守护进程 / 扫描
├── function/mimon                  Web 后端（show/scan/sweep/seting/rename/add/forget）
├── share/discover.lua              miIO 广播发现（LuaJIT + FFI，无需 token）
├── share/ikuai_terminals.sh        读取 iKuai 终端列表（具体型号/品牌/备注/hostname）
├── share/xiaomi_oui.txt            IEEE OUI 清单里的小米前缀
├── share/menu_patch.sh             状态监控菜单/SPA 路由集成（失败不影响卡片）
└── www/plugins/
    ├── mimon/mimon.json            卡片元数据
    └── app/mimon.html/.png         页面与图标
```

## 安装

插件包不需要签名。在 iKuai「高级应用 → 插件管理」上传 `dist/mimon.zip` 即可；
也可以 SSH 到设备：

```bash
ikplugin install /root/mimon.zip
ikplugin list
```

安装后会同时做两件事：
1. 在「高级应用 → 插件管理」保留卡片「小米设备接入」；
2. 尝试在「状态监控 → 小米设备」加一个菜单项（前端集成，失败则只保留卡片）。

**如果菜单没出现**：iKuai 后台把菜单缓存在 `sessionStorage`，请**关闭后台标签页重新打开**
（或浏览器控制台执行 `sessionStorage.removeItem('allFirstMenu')` 后刷新），并 Ctrl+F5 强刷一次
（app 分包文件名没变，浏览器可能还在用旧缓存）。首次扫描会建库、识别现有设备，并在后台跑一轮扫描。

## 状态监控菜单入口（前端集成）

插件安装/每次开机会调用 `share/menu_patch.sh`，在 iKuai 前端做几处**幂等、可回退**的修改：

| 文件 | 改动 |
| --- | --- |
| `/usr/ikuai/www/json/menu.json` | 在「状态监控」组追加叶子：`小米设备` |
| `/usr/ikuai/www/json/menu-i18n.json` | 权限页按 `func_name` 显示的三语菜单名 |
| `/usr/ikuai/www/static/i18n/{zh-CN,zh-TW,en-US}.json` | 加菜单文案/页面标题 |
| `/usr/ikuai/www/static/js/app.<hash>.js.gz` | 加一个 iframe 路由 `system-setting-mimon`，指向 `/plugins/app/mimon.html` |

做法与框架自己的前端补丁一致：解压 → 精确锚点插入 → 重新压缩 → 校验通过才原子替换；
**锚点找不到就跳过，不写任何前端文件**（例如 iKuai 升级后路由结构变了），此时插件卡片仍然可用。
根分区每次重启还原，所以 `boot.sh` 每次开机重打；同一个文件重复执行不会产生重复菜单/路由。

iKuai 的 `/json/menu.json` 由 `funcore.lua` 在 openresty 启动时生成并缓存，所以补丁完成后会自动执行
`openresty -s reload`（与 `funcore.sh` 改权限后的做法一致）刷新菜单缓存；浏览器侧还会把菜单缓存在
`sessionStorage.allFirstMenu`，需要关闭后台标签页重开（或清掉该 key）并 Ctrl+F5。

> 风险提示：这是在改 iKuai 官方前端，不是纯插件卡片。已在 iKuai **3.7.16 x64 Build202411141700**
> 真机安装验证：菜单「状态监控 → 小米设备」、iframe 页面、后端接口均正常；插入后的 `app.js`
> 过 Node 语法检查，叠加框架自身前端补丁后仍有效。未在其他固件版本上验证。
> 失败是 fail-safe 的：不会破坏菜单/静态资源，只是菜单项不出现。

手动控制：

```bash
mimon menu-apply     # 重新打菜单/路由补丁（幂等）
mimon menu-remove    # 移除菜单项（路由与语言键在重启后随根分区还原）
```

卸载时 `uninstall.sh` 会自动移除菜单项；路由/语言键会在重启后随根分区还原。

## 命令行

```bash
mimon status                    # 运行状态 / 计数 / 配置（JSON）
mimon devices                   # 设备列表（JSON）
mimon events [N]                # 最近 N 条事件（JSON）
mimon scan                      # 立即扫描一轮（ARP + ping + miIO）
mimon scan --sweep              # 先扫一遍 LAN 网段再扫描
mimon sweep-start               # 后台启动网段扫描（Web 按钮用）
mimon probe                     # 只跑 miIO 广播，打印原始应答（排障）
mimon set <key> <value>         # 改配置
mimon edit <mac> <name> <kind>  # 改名 / 改类型（kind: auto|iot|router|terminal|other）
mimon add <mac> [name] [kind]   # 手动登记设备
mimon forget <mac>              # 删除设备及其事件
mimon daemon-start|daemon-stop  # 启停守护进程
mimon daemon                    # 前台运行（调试用）
mimon menu-apply                # 打「状态监控 → 小米设备」菜单/路由补丁
mimon menu-remove               # 移除菜单项
```

示例：

```bash
mimon edit 34:ce:00:11:22:33 客厅路由器 router
mimon add 12:34:56:78:9a:bc 我的手机 terminal
mimon set interval 30
mimon set sweep_cidr 192.168.9.0/24
```

## 配置

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `interval` | 60 | 采集间隔（秒，10~3600） |
| `offline_after` | 3 | 连续多少轮无响应才离线（2~20） |
| `miio` | 1 | 是否做 miIO 广播探测（失败会自动降级为纯 ARP） |
| `sweep_enabled` | 0 | 是否周期扫描 LAN（默认关，页面里可开；手动「网段扫描」始终可用） |
| `sweep_every` | 600 | 网段扫描周期（秒，60~86400） |
| `sweep_cidr` | auto | `auto` = 从路由表取直连 /24；也可写 `192.168.9` 或 `192.168.9.0/24` |
| `retain_events` | 300 | 事件保留条数（50~2000） |

> 参数值不能带空格/引号（Web 请求的统一限制）；自由文本里的空格前端用 `+` 传。

## 数据与日志

| 路径 | 说明 |
| --- | --- |
| `/etc/mnt/plugins/mimon/data/mimon.db` | 设备、事件、配置（sqlite3/WAL，升级保留） |
| `/etc/log/mimon.log` | 安装、开机、扫描、错误日志 |

不要在根分区（`/`、`/usr/ikuai/...`）写任何持久文件 —— 每次重启都会还原。

## 发现原理

1. **ARP + OUI**：读 `/proc/net/arp`，用 IEEE OUI 清单里的 343 个小米前缀过滤。
   这一步不依赖任何外部服务，能覆盖大部分米家 IoT 设备和小米路由器。
2. **iKuai 终端列表（型号主来源）**：直接调用本机函数
   `/usr/ikuai/function/monitor_lanip show TYPE=data`（与「状态监控 → 终端列表」同一份数据，
   不需要 Web 登录/设备 token），取：
   * `client_model`：具体型号，如「小米AI音箱 LX04」「米家台式净饮机」「小米14」
   * `hostname`：设备自报主机名，如 `chuangmi-plug-212a01`、`MiAiSoundbox-LX04`
   * `client_device` / `client_typeid` / `client_type`：品牌与设备类型
   * `comment`：iKuai 终端列表里你填的备注（如「冰箱」「小爱触屏音箱」）
   插件把型号/主机名写库，备注在名称为空时作为显示名，并按 typeid/型号关键词自动分类；
   随机 MAC 的小米/红米手机、平板也会从这里补进来。
3. **miIO 广播**：`share/discover.lua` 向各 LAN 广播地址/ARP 地址的 UDP/54321 发送 32 字节握手包，
   解析应答里的 `did`（**不需要 token**）；很多固件只回 32 字节 header（无型号），
   这时型号以 iKuai 终端列表为准。设备没有 luasocket，脚本用 LuaJIT FFI 直接调 libc；
   失败只记 `last_error`，不影响主流程。
4. **在线判定**：每轮 ping 已知 IP、miIO 应答、iKuai 终端列表里的在线条目都算在线；
   ARP 只用来发现/修正 IP，不会因为“ARP 里还有条目”就误判在线。
5. **网段扫描**：默认从 `/proc/net/route` 取直连的 /24，一次扫 254 个地址（32 并发、1 秒超时）；
   也可手动指定 /24。发现手机、电视等不回应 miIO 的设备。

## 本地验证（无真机）

需要 `sqlite3`、`jq`；测试自带假 ARP、假 ping、假 miIO/终端列表 JSON，不会碰系统路径：

```bash
export PATH="/path/to/jq-and-sqlite3:$PATH"   # 需要 jq、sqlite3
bash tests/smoke.sh
```

`tests/smoke.sh`（32 项）会验证：首次发现、OUI 过滤、miIO DID/型号解析（含空字段）、
iKuai 终端列表的型号/备注/hostname 合并、按型号自动分类与手动类型保护、离线阈值、重新上线、
手动添加/改名/删除、状态 JSON、事件落库、网段扫描、守护进程启停。

## 真机验证清单

当前版本已在 iKuai **3.7.16 x64 Build202411141700** 真机安装并验证：菜单入口、iframe 页面、
状态接口、miIO DID 发现、**iKuai 终端列表型号同步**（小米AI音箱 LX04 / 米家台式净饮机 /
小米摄像头 等，手机/平板则显示为对应机型）、按型号自动分类、被动扫描（周期扫描关闭）。
**重启后的自启/菜单重打尚未执行**（避免断网），`boot.sh` 会在重启时重新打补丁；
可自行安排窗口验证。复核清单：

```bash
# 1) 安装
ikplugin install /root/mimon.zip
/usr/sbin/mimon status
/usr/ikuai/function/mimon show TYPE=data
grep '\[menu\]' /etc/log/mimon.log
#   应看到「已加 SPA 路由 / 已加菜单项」
#   然后在浏览器：关闭 iKuai 后台标签页重新打开 + Ctrl+F5
#   左侧应出现「状态监控 -> 小米设备」，点开就是插件页

# 2) miIO 是否可用（重点）
/usr/sbin/mimon probe
#   有 devices 数组 => FFI UDP 正常；error 字段会说明原因
# 3) 触发一轮扫描，看具体型号/主机名
/usr/sbin/mimon scan
/usr/sbin/mimon devices | jq -c '.[] | {name,model,hostname,kind}'
# 4) 重启验证自启 + 菜单补丁重打
reboot
#   SSH 回来后:
/usr/sbin/mimon status          # daemon_running=true
grep '\[menu\]' /etc/log/mimon.log | tail -5   # 有 boot 时重打记录
# 5) 卸载
ikplugin remove mimon
#   菜单项立即移除；SPA 路由/语言键重启后随根分区还原
```

## 已知限制

* 不控制设备（开关/模式等需要设备 token，本插件不收集 token）。
* 型号/备注来自 iKuai 的终端识别（`monitor_lanip`）；个别机型可能被识别成相近型号/品牌，
  名称/类型可在页面里编辑（`manual=1` 后不被自动覆盖）；型号本身随下一次扫描按 iKuai 数据刷新。
* 部分智能插座的 `client_model` 是产品系列名（如「小米智能插座」），精确到型号要看 hostname
  里的代号（如 `cuco-plug-cp1m`、`chuangmi-plug-212a01`）。
* 不在 iKuai 终端列表里的设备（跨 VLAN、未关联的 IoT 等）只能靠 ARP/OUI/miIO DID 识别，
  型号可能为空；miIO 精确型号仍需要设备 token（本插件不收集）。
* 小米手机/平板使用随机 MAC 时 OUI 识别不到，但会从 iKuai 终端列表补进来（含型号）；
  若终端列表功能不可用，仍可手动「添加设备」。
* miIO 广播只对同一广播域有效；跨 VLAN/路由的设备靠 iKuai 终端列表或手动登记。
* 网段扫描只处理 /24；大网段请在 `sweep_cidr` 里指定具体 /24，避免一次 ping 太多地址。
* 「状态监控 → 小米设备」菜单是改 iKuai 官方前端实现的；换固件版本后如果路由锚点变了，
  补丁会 fail-safe 跳过（菜单不出现，插件卡片仍可用），需要重新适配锚点。

## 构建

```bash
bash build.sh
# => dist/mimon.zip
```

有 `zip` 时直接用；没有时用 Python 兜底（会保留 install.sh、bin/*、function/* 的执行位）：

```bash
PYTHON=/path/to/python3 bash build.sh
```
