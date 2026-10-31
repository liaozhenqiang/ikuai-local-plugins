# ikuai-local-plugins

给 iKuai（爱快）软路由用的第三方插件集合：**一个自己写的本地设备监控插件（devmon）**，
以及**我这台路由器上实际在跑的 13 个社区插件的 iKuai 集成层**。
全部是纯 shell + 前端补丁 + 现成二进制包装，不依赖 Docker、不需要额外主机、不绑定爱快云。

| 目录 | 内容 | 发布形态 |
| --- | --- | --- |
| [devmon/](devmon/README.md) | 本地「周边设备监控」（替代云平台的摄像头/交换机/周边设备三个页面） | 源码 + 完整安装包 |
| [plugins/](plugins/README.md) | 13 个社区插件的集成层源码（AdGuard Home、AList、OpenClash、FRP…） | 源码 + 含二进制的完整安装包 |

所有安装包都在 [Releases](releases)，命名统一为 `<插件名>-v<版本>-plugin.zip`，
**含程序本体、可直接安装，也能被「插件在线升级」(ikupd) 直接升级**。

---

## 快速开始

```bash
# 安装（也可以在「高级应用 → 插件管理」里上传 zip）
ikplugin install /root/devmon-v1.1.0-plugin.zip

# 卸载（会把菜单/路由/语言文件从备份恢复）
ikplugin remove devmon
```

**在线升级**：装好 `ikupd`（第三方在线升级插件，本仓库不包含，用上游的包）后，在它的「仓库列表」里加

```
https://github.com/liaozhenqiang/ikuai-local-plugins/releases
```

点「检查更新」即可看到本仓库的 14 个包。首次使用建议在「代理 → GitHub Token」填一个
只读 Token —— 匿名调 GitHub API 每小时只有 60 次，很容易 `API rate limit exceeded`。

---

## 功能总览

### devmon — 本地周边设备监控（自研，1.1.0）

把「状态监控」下被云平台拦住的 **摄像头监控 / 交换机监控 / 周边设备监控** 三个页面
**合并成一个本地入口**（菜单位置不变），数据和管理全在路由器本地。

* **设备清单**：名称、IP、MAC、类别（摄像头/交换机/周边设备）、品牌、型号、hostname、
  位置、备注、端口、Web/RTSP/SSH 链接
* **在线监控**：ping + iKuai 终端列表双判定，连续 N 轮无响应才离线；上下线事件流水
* **自动收录**：终端列表里新出现的设备自动进清单（类别=周边设备），带品牌/型号/hostname/IP；
  **手动删除的设备进忽略名单，不会被自动加回来**；可在「监控设置」里关掉
* **局域网发现**：扫描 ARP + iKuai 终端列表，显示品牌/型号/备注，勾选后批量导入并指定类别
* **管理**：新增、编辑、暂停/启用、删除（带确认）、立即检测、检测间隔与离线阈值可调
* **字段自愈**：清单里空着的品牌/型号/hostname 会由终端列表补全，**不覆盖你改过的值**
* **零依赖**：只用设备自带的 bash + jq + sqlite3，不采集任何设备 token、不联网上报

细节（菜单怎么改、数据表结构、CLI、已知限制）见 [devmon/README.md](devmon/README.md)。

### plugins/ — 13 个在用的社区插件

| 插件 | 能做什么 |
| --- | --- |
| **AdGuard Home** 0.107.79.3 | 局域网 DNS 广告/追踪拦截：启停、重启、改监听端口、上游 DNS 设置、运行日志查看与清空 |
| **AList** 3.65.0 | 网盘聚合（阿里云盘/115/天翼云盘/夸克/OneDrive…）统一 Web 与 WebDAV：装好即自启，卡片一键打开管理界面，端口可改 |
| **aria2** 1.0.4 | 多协议下载器（HTTP/FTP/BT/磁力）+ AriaNg 网页界面：RPC 密钥、下载目录（落在数据盘）、启停、日志 |
| **bnfix** 1.0.0 | 修系统 `libcrypto.so.1.0.0` 里 `BN_mod_sqrt()` 的死循环（1 字节补丁，`je`→`jle`）：状态查询、单点校验、完整校验、重启 |
| **ddns-go** 6.17.7 | 动态域名解析客户端：启停、重启、监听端口、运行日志 |
| **frpc** 0.71.1 | FRP 内网穿透客户端：服务端地址与 token、多条 tcp/udp/http/https 代理规则增删、启停、日志 |
| **frps** 0.71.1 | FRP 内网穿透服务端：通信端口、仪表盘端口、认证 Token 自动生成、启停、日志 |
| **集客AC (gecoos)** 2.2 | 集中管理集客 AP：启停、管理端口、AP 通信端口、公网访问开关（默认仅内网）、Web 管理密码 |
| **米家面板 (miot-panel)** 1.1.1 | 跑在路由器本机的米家墙面板（设备控制/摄像头/音乐中心）：启停、端口、日志、一键打开面板 |
| **npc** 0.26.39 | 内网穿透客户端：装好即开机自启，卡片直达其自身管理界面 |
| **nps** 0.26.39 | 内网穿透服务端：默认端口 81，装好即自启，卡片直达 Web 管理 |
| **OpenClash** 0.48.003 | mihomo(Meta) 内核 + 订阅导入/转换 + 透明代理（redirect/tproxy/tun）+ 原生 Web 控制台：配置/订阅/规则/节点/延迟测试/旁路/自检/日志 |
| **TTYD** 1.7.7 | 浏览器里的 root 终端：启停、自定义端口、访问口令 |

三个插件是「装好即用、页面只做入口」的形态：AList、npc、nps 没有自定义后端，
页面负责打开它们自己的管理界面；其余插件都有 `function/<名字>` 后端，
可以在卡片页里直接启停/改配置/看日志。

---

## 插件在线升级（ikupd）

### 资源命名规则

ikupd 只扫 release 里的 `.zip`（自动排除 GitHub 生成的 Source code 包），
并按 **`<插件名>-v<版本>-plugin.zip`** 解析插件名和版本。

### 怎么判断"有没有更新"

不看版本号，而是比对 **release 资源自带的 sha256**（GitHub API 的 `digest`）和
**本地同前缀包的 sha256**：

* 本地哈希优先取 ikupd 自己的安装记录 `ikupd/data/installed.conf`，
* 其次取框架归档 `/etc/mnt/plugins/.installed/<插件名>*.zip`，
* 两者都没有时只能按版本号比（显示「同版本」并给提示）。

所以：**发布哪个包就必须装哪个包**。改了包名/重新打包导致哈希变化，会被判成有更新。

### 打包（本地 / 设备上）

```bash
# 本地：只打源码完整的 devmon
bash build-all.sh                 # => dist/devmon-v1.1.0-plugin.zip
bash build-all.sh --all           # 连 plugins/ 一起打（只有集成层，不完整）

# 设备上：把已安装插件打回「含二进制」的完整包（自动排除 data/、日志、旧签名清单）
bash tools/pack-on-device.sh ttyd # => /tmp/ttyd-v1.7.7-plugin.zip + sha256
```

* `tools/pack_plugin.py`：通用打包器。所有条目用 `Release` 的 mtime 做固定时间戳，
  同一份源码在哪台机器上打，zip 字节都一样（sha256 稳定），避免"重新打包就被判成有新版本"。
* `tools/pack-on-device.sh`：在路由器上打包，排除 `data/`（证书、token、清单都在里面）、
  日志和过期的 `MANIFEST.MF`/`SIGNATURE.RSA`（文件哈希对不上会让 `plugin_verify` 拒绝安装）。
* 执行位：`install.sh` / `boot.sh` / `uninstall.sh` / `*.sh` / `bin/*` / `function/*` 一律 0755。

### 发新版本

1. 改 `Release` 里的 `version=`；
2. 重新打包（`build-all.sh` 或 `pack-on-device.sh`）；
3. `gh release upload <tag> <新包>`（文件名不要改）；
4. 设备上「检查更新」→ 下载 → 安装。

---

## 目录结构

```
devmon/              自研插件：本地周边设备监控
  pkg/               插件包本体（Release / install.sh / boot.sh / bin / function / share / www）
  tests/smoke.sh     34 项本地冒烟（假 ARP / 终端列表 / ping）
  tools/mp_test.sh   前端菜单补丁的隔离副本验证脚本
plugins/             13 个社区插件的集成层源码
tools/               pack_plugin.py（本地打包）、pack-on-device.sh（设备上打完整包）
build-all.sh         打包入口
```

---

## 运行环境

在 **iKuai 3.7.16 x64 Build202411141700** 上开发并真机验证。设备侧只有这些可用，代码都按此约束写：

* `jq` **1.4**（没有 `--argjson` / `--indent` / 组合 `-cn`）
* `sqlite3` **3.8.11.1**（没有 UPSERT / RETURNING / json1）
* `bash` + busybox（没有 python / node / timeout / nohup / setsid，`ps` 功能很弱）
* `zip` / `unzip` / `sha256sum` / `base64` 都有
* 持久分区只有 `/etc/mnt` 和 `/etc/log`；**根分区每次重启还原**，所以插件靠 `boot.sh`
  每次开机重新铺开（devmon 的菜单补丁也是每次开机重打）

其它固件版本没有验证过。前端补丁是 fail-safe 的：锚点找不到就跳过，不会写坏菜单或静态资源。

---

## 安装 / 升级 / 卸载

* **安装**：插件管理页面上传 zip，或 `ikplugin install /root/<包>.zip`
* **升级**：ikupd 在线升级，或上传新 zip 覆盖安装。
  安装会**替换整个插件目录**，只保留 `data/`（数据库、证书、配置），所以升级前别手改插件目录里的文件
* **卸载**：`ikplugin remove <插件名>`，插件的 `uninstall.sh` 会清理它加的服务、软链和前端改动

> ⚠️ 这些插件都以 **root** 权限运行，并且会修改 `/usr/ikuai`（菜单 `menu.json`、
> SPA 路由 `app.<hash>.js.gz`、i18n 语言文件）或启动常驻进程。
> **装之前先读 `install.sh` 和 `function/*`**，确认它在你机器上要做什么。
> 前端补丁改前都会备份到插件自己的 `data/menu-backup/`，补丁后自动 `openresty -s reload`；
> 浏览器侧要关掉后台标签页重开 + Ctrl+F5，否则看到的是缓存的旧菜单。

---

## 测试

```bash
cd devmon && bash tests/smoke.sh     # 34 项：清单、发现、导入、在线/离线、暂停、删除、自动收录、守护进程
```

`devmon/tools/mp_test.sh` 用来在**隔离副本**上验证前端菜单补丁（单入口 → 幂等 → 完全还原），
把它和 `menu_patch.sh` 传到设备上跑，不会动真实前端。

---

## 隐私

* devmon 和所有 `function/*` 后端都**只在路由器本地运行**：不上传数据、不请求外部服务、
  不采集设备 token、不需要爱快云账号。设备清单存在 `/etc/mnt/plugins/devmon/data/devmon.db`。
* 本仓库的安装包**不含各插件的 `data/`**（证书、token、配置、数据库都在那里，不随包分发）；
  只有 `ikupd` 安装时会把下载的包暂存后再删。
* 唯一会主动联网的是 `ikupd`（检查/下载 GitHub Release）和 `ddns-go` / `frp` / `nps` 这类
  本来就联网的插件，行为由你在它们页面里配置。

---

## 来源与授权

插件的包结构、`ikcommon` 后端约定与前端补丁思路来自
[deadash/ikuai-plugins](https://github.com/deadash/ikuai-plugins) 的插件开发技能与模板
（v0.0.9 那批 releases 里的示例插件包 + `.codebuddy/skills/ikuai-plugin-dev/assets/template/`）。
设备侧框架（`ikcommon`、`funcore`、插件管理器）属于 iKuai 固件本身。

> 上游仓库**没有附开源许可证**（版权归其作者）。本仓库**只对自己编写/改写的那部分代码**
> 按 [MIT](LICENSE) 授权；从上游模板沿用/衍生的部分仍归原作者，单独再分发前请先联系上游作者。
> `plugins/` 里各插件包装的第三方程序（AdGuard Home、AList、mihomo、frp、nps/npc、ttyd、
> ddns-go、AriaNg、aria2、Gecoos AC 等）版权归各自项目所有，发布包仅作个人设备使用。
