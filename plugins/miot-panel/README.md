# miot-panel · 爱快插件

把米家墙面板装进爱快「插件管理」，跑在路由器本机：设备控制、摄像头、音乐中心。
**1.1.4 起完整安装包内置音乐组件，装好不需要再联网下载 Songloft。**

## 安装

从 [Releases](../../releases) 下载 `miot-panel-v1.1.4-plugin.zip`：

```bash
ikplugin install /root/miot-panel-v1.1.4-plugin.zip
```

也可以在「高级应用 → 插件管理」上传。安装/升级只保留插件 `data/`（PIN、登录态、设备设置、音乐库和凭据），
其余程序文件会被新包替换。

- 面板目录：`/etc/mnt/plugins/miot-panel/app`
- 数据目录：`/etc/mnt/plugins/miot-panel/data`
- 默认端口：`8088`
- 访问：`http://<爱快局域网IP>:8088/`

## 1.1.4 修复内容

- 修正爱快作为路由器时 `get_lan_ip()` 取到 WAN 地址的问题：面板、Songloft、GoMusicDL 和转码白名单统一使用 LAN 地址。
- 面板同源代理增加 `/api/v1`：GoMusicDL、智能音箱插件的 CSS/JS 和接口不再 404。
- 首次启动自动安装内置音乐中心；已有音乐库时保留并重新拉起。
- 音乐目录默认建在 `data/music-stack/songloft/music`，covers 同目录；扫描不再报 `no valid scan directory`。
- 内置 `FFmpeg`/`FFprobe` 并注入 Songloft PATH，修复本地曲库元数据、FLAC/M4A 转 MP3 和在线播放的依赖问题。
- 升级时按实际进程清理旧 Songloft/go-music-dl，确保新 PATH 和配置生效。
- 修复完整包重新打包后 Python loader 执行位丢失、安装时报“缺少 glibc 兼容库”的问题。

## 内置音乐组件

完整包包含（第三方二进制只在 Release 资产里，不进源码仓库）：

| 组件 | 版本 |
| --- | --- |
| Songloft | v2.13.7 |
| go-music-dl | v1.1.3 |
| Songloft MIoT 插件 | 2026.10.29.0 |
| go-music-dl Songloft 插件 | 2026.10.16 |
| 面板免登录插件 | 1.1.0 |
| FFmpeg / FFprobe | 7.0.2 static |

首次打开面板后，后台会自动安装并启动音乐中心：

- Songloft：`127.0.0.1:58091`
- go-music-dl：`127.0.0.1:8081`
- 面板后台“音乐与 AI 音箱”里可查看状态、重新启动或打开音乐中心。
- 小米账号仍需在后台扫码绑定；绑定后音箱列表、TTS、语音和 AI 功能才能使用。

## 本地音乐

把音频文件放进：

```
/etc/mnt/plugins/miot-panel/data/music-stack/songloft/music
```

然后在 Songloft「音乐库管理」点扫描。默认排除 `@eaDir`、`tmp`；刚复制进去的文件需要等约 10 秒
（Songloft 会跳过正在写入的文件）。

## 数据与安全

- `data/` 保存 PIN 哈希、登录态、音乐库数据库和 Songloft 凭据，不会打进安装包。
- 面板和音乐中心都只应在家庭局域网访问；不要直接把 8088/58091/8081 映射到公网。
- 完整包里的 FFmpeg/FFprobe 为 GPLv3 静态构建，许可证随包放在 `payload/panel/music-stack/`。

## 源码与完整包

仓库只放集成层源码；`app/ payload/ site/ runtime/` 和音乐二进制在完整 Release 包里。
需要重新打完整包时，在已安装的路由器上执行：

```bash
bash tools/pack-on-device.sh miot-panel
```

然后按 `miot-panel-v<版本>-plugin.zip` 命名上传 Release。
