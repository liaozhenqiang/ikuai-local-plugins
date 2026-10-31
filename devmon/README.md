# devmon —— 本地设备监控

> 基于 [deadash/ikuai-plugins](https://github.com/deadash/ikuai-plugins) 的插件模板与开发技能
> （v0.0.9 那批 [Releases](https://github.com/deadash/ikuai-plugins/releases) 里的示例插件包 +
> `.codebuddy/skills/ikuai-plugin-dev/assets/template/`）开发；归属与授权范围见[仓库根 README](../README.md)。

iKuai「状态监控」下的 **摄像头监控 / 交换机监控 / 周边设备监控** 三个页面原本被云平台绑定拦住，
本插件把它们**合并成一个本地「周边设备监控」入口**（菜单位置不变，另两项从菜单里去掉）：
一个页面看全部设备，类别（摄像头/交换机/周边设备）作为页内筛选和每台设备的属性保留。

点开后是本地页面：设备清单、在线/离线、类别、品牌/型号、位置、备注、
Web/RTSP 链接、扫描发现、增删改、暂停监控。数据全部在本地，不需要绑定爱快云。
**终端列表里新出现的设备会自动收进清单**（类别=周边设备，可在页面关掉）。

> 能做的是**本地清单 + 在线监控 + 管理/编辑**。摄像头 PTZ/录像、交换机端口开关这类
> 厂商级控制需要具体品牌的 API/协议/账号，通用插件不内置；页面提供「打开」设备自己的
> Web/RTSP/SSH 链接。

## 菜单是怎么改的

`share/menu_patch.sh` 做三件事（幂等、可回退）：

1. 在 `app.<hash>.js.gz` 里加一条 iframe 路由 `devmon-peripheral` → `/plugins/app/devmon.html`
   （打补丁前会先删掉历史版本插入的 `devmon-camera` / `devmon-switch` / 带 `?cat=` 的旧路由，
   所以从 1.0.0 升级不需要重启）
2. `menu.json` 里**删掉**摄像头监控、交换机监控两个叶子，把「周边设备监控」
   （`tools.instrumented`）的 `linkTo` 改成 `devmon-peripheral`
3. 给三份 i18n 加页面标题 `page-title.devmon.*`

改前的 `menu.json` / `app.js.gz` / i18n 备份在插件 `data/menu-backup/`（**只写一次**，
保证里面永远是没有 devmon 痕迹的那份），卸载时 `uninstall.sh` 自动恢复；
根分区重启本身也会还原。备份缺失时的兜底只能把链接改回云页面，被删掉的两个叶子
要等重启才回来。

iKuai 的菜单由 `funcore.lua` 在 openresty 启动时缓存，所以补丁后会自动
`openresty -s reload`；浏览器还需要关闭后台标签页重开 + Ctrl+F5（菜单/JS 有缓存）。

老云平台页面本身没有删除，只是从菜单不再进入；直接访问旧路由仍会看到原页面。

## 自动收录

守护进程每轮检测都会对比 iKuai 终端列表和本地清单：

* 终端列表里出现、清单里没有的 MAC → 自动作为**周边设备**入库，名称取「终端备注 → 型号 →
  hostname → MAC」，同时带上品牌/型号/hostname/IP，事件表记一条 `新增 / 自动收录`。
* 已经在清单里的设备只**补空字段**（品牌/型号/hostname/名称为空时才填），不会覆盖你改过的值，
  也不会改类别。
* 手动**删除过的设备记进 `hidden` 表**，自动收录不会把它加回来；再手动添加一次即解除。
* 只收终端列表里的设备，不收纯 ARP 条目（避免把组播/网关这类噪音收进来）。
* 开关：页面「监控设置 → 自动收录」，或 `devmon set auto_add 0|1`（默认开）。

## 发现与在线判定

* **发现**：ARP + iKuai 本机终端列表（`/usr/ikuai/function/monitor_lanip`）+ ping。
  终端列表提供 `client_model` / `hostname` / `client_device` / `client_typeid` / 备注，
  随机 MAC 的手机/平板也能看到。扫描结果里选设备、选类别，批量导入。
* **在线**：ping 通或出现在 iKuai 终端列表中（摄像头/交换机不一定回 ping）；
  连续 N 轮都没有任何信号才离线。守护进程每 60 秒检测一轮。
* **数据**：`/etc/mnt/plugins/devmon/data/devmon.db`（sqlite3，重启不丢），
  日志 `/etc/log/devmon.log`。

## 安装

把 `dist/devmon.zip` 上传到 iKuai「高级应用 → 插件管理」，或 SSH：

```bash
ikplugin install /root/devmon.zip
ikplugin list
```

安装后：

1. 关闭后台标签页重开 + Ctrl+F5；「状态监控」里的三个菜单项点开就是本地页面。
2. 进入某个类别 → 「扫描发现」→ 勾选设备 → 导入当前类别。
3. 导入后点「立即检测」刷新在线状态；之后守护进程每 60 秒自动检测。

## 操作

* 类别：摄像头 / 交换机 / 周边设备；卡片页（插件管理）显示全部，可筛选。
* 设备字段：名称、IP、MAC、品牌、型号、hostname、位置、备注、链接、端口、监控开关。
* 列表操作：编辑、暂停/启用监控、删除；「打开」按链接打开设备 Web（RTSP 会复制链接）。
* 设置：检测间隔（10~3600 秒）、离线判定轮数（2~20）。
* 事件：上线/离线/新增，最近 30 条。

## CLI / 后端接口

```bash
devmon status
devmon devices [camera|switch|peripheral|all]
devmon scan                      # 发现候选（JSON）
devmon save <mac> <ip> <cat> <name> <vendor> <model> <hostname> <location> <note> <url> <ports> <enabled>
devmon toggle <mac> 0|1
devmon forget <mac>
devmon observe                   # 立即检测一轮（含自动收录）
devmon set interval 60
devmon set auto_add 0|1          # 新上线设备自动收录开关
devmon daemon-start|daemon-stop
```

Web 后端 `function/devmon`：`show`（`TYPE=data` 清单 / `TYPE=scan` 发现）/ `save` / `toggle` / `forget` / `seting` / `refresh`。

> **框架约定（踩过的坑）**：iKuai 的 `/Action/call` 只把 **`show` 动作**的 stdout 解析成 `Data`，
> 其它动作成功时 stdout 一律丢弃（失败时 stdout 才是 `ErrMsg`）。所以局域网发现不能做成
> `scan` 动作，只能挂在 `show TYPE=scan` 上；写动作成功时也不要 `echo`。
> 参数值不能带空格（前端把空格编码成 `+`，后端 `tr '+' ' '` 还原），中文可以正常传。
> 同一台机器上 ttyd 插件的注释里也记录了这条约束。

## 真机验证（iKuai 3.7.16 x64 Build202411141700）

1.0.0（三个入口）：

* 扫描发现 30 台候选，型号来自 iKuai 终端识别（摄像头 / 智能插座 / 音箱 / 投影仪 / 手机 /
  平板 / NAS 等，具体取决于你的网络），带 hostname 与终端备注。
* 导入、编辑（改位置为「客厅」）、暂停/启用、删除（带确认框）、立即检测、监控设置保存均通过；
  中文名称/备注可作为参数保存，回读正常（UTF-8 全链路）。

1.1.0（合并单入口 + 自动收录）：

* 菜单只剩「周边设备监控」，页面标题与浏览器标签页标题（`home-周边设备监控`）正确，
  一个页面显示全部设备，类别作为页内筛选。
* 升级路径已在隔离副本上验证：三入口现状 → apply 后路由 `cam=0 sw=0 per=1`、菜单叶子 9→7、
  再 apply 一次字节级一致（幂等）、remove 后 app.js 与 menu.json 与改前完全一致。
* 打补丁后的 `app.js` 用 Node `--check` 校验语法通过。
* 自动收录：新设备进清单（类别=周边设备、来源 auto、事件「新增/自动收录」），
  删除过的设备不复活，关掉开关后不再进；空的品牌/名称由终端列表补全。
* 本地 `tests/smoke.sh` 34 项全通过。

## 已知限制

* 只做本地监控/管理，不做厂商级设备控制（PTZ、端口开关、重启摄像头等）。
* 型号/品牌/hostname 来自 iKuai 终端识别；个别机型可能识别成相近型号，页面可手动改名称/型号/类别
  （设备字段以本地库为准，只补空值、不会被终端列表覆盖）。
* 端口字段目前只记录/展示，不做 TCP 探测；在线状态由 ping + 终端列表判定。
* 自动收录只认 iKuai 终端列表；只在 ARP 表里出现、终端列表没有的设备不会自动进清单
  （可以用「扫描发现」手动导入）。
* 菜单改动是改 iKuai 官方前端实现的；换固件版本后如果锚点/菜单结构变了，
  补丁会 fail-safe 跳过（菜单不接管，插件卡片仍可用），需要重新适配。
* 「状态监控 → 终端监控 → IPv4/IPv6 终端详情」里的「终端类型/设备厂商 Unknown/Unknown」
  是另一个页面/字段，本插件不修改那个详情页。

## 本地验证

需要 `sqlite3`、`jq`：

```bash
export PATH="/path/to/jq-and-sqlite3:$PATH"
bash tests/smoke.sh        # 34 项：清单、发现、导入、在线/离线、暂停、删除、自动收录、守护进程
```

菜单补丁要在设备上验证（本地 Windows jq 会输出 CRLF，比较结果不可信）：
把 `pkg/share/menu_patch.sh` 和 `tools/mp_test.sh` 传到设备 `/tmp`，跑
`bash /tmp/mp_test.sh`。它把设备当前的 `app.js.gz / menu.json / i18n / index.html`
复制到一个隔离目录（`IK_WWW=/tmp/mp/ikwww`），依次检查
「三入口现状 → apply 变单入口 → 再 apply 幂等 → remove 完全还原 → 备份里无 devmon 痕迹」，
不碰真实前端。补丁后的 app.js 可以再拉回本地用 `node --check` 验语法。

## 构建

```bash
bash build.sh
# => dist/devmon.zip
```

有 `zip` 时直接用；没有时用 Python 兜底（保留 install.sh/bin/function 的执行位）：

```bash
PYTHON=/path/to/python3 bash build.sh
```
