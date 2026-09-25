# H3 Console

单文件网页控制台（打包为自包含 Android APK），用于在租用 GPU（如 AutoDL 4090）上通过 ComfyUI 本地运行开源 MiniMax H3 模型生成带音频的短视频，并提供实例电源与计费管理。

**请使用 APK 使用本工具，暂不支持网页端**——登录获取 token 等功能依赖 App 的原生桥接。仓库内不含任何实例凭证：SSH 连接信息通过 `.env` 提供，AutoDL 网页 token 只存放在 APK 的 localStorage。

## 功能

**界面**
- 底部导航双页签：**创作**（连接/创作/生成/性能监测/结果）与**设置**
- 设置页：AutoDL 登录、语言（中文/English）、主题（暗/亮）、GitHub 仓库、爱发电赞助
- 外链打开策略：原生 App（App Links / Deep Links）→ Chrome Custom Tabs → 系统浏览器，逐级回退
- 单文件 HTML，零 CDN（Tom Select / Alpine.js 内联），双主题全套色卡变量

**视频生成**
- 提示词旁可选上传首帧/尾帧图片：两个都留空即文生视频，只传首帧即图生视频（i2v），首尾都传即关键帧插值（flf2v）——同为官方 `MiniMaxH3ImageToVideo` 原生接线，权重通用、实例零额外配置
- 直连 ComfyUI API（WebSocket 进度 + 实时预览），分辨率/时长/种子/LoRA 强度可调
- 生成中再次提交自动进入原生 ComfyUI 队列，队列展示进度、支持中断/移除（页面内确认框，兼容 Android WebView）
- 历史记录持久化（localStorage），刷新自动恢复追踪（实时队列状态提示），结果内嵌播放
- 删除记录时同步删除云端文件与 ComfyUI 历史索引

**性能监测**
- CPU / GPU 利用率、GPU 温度、显存与内存占用、排队情况，五卡片自适应布局
- CPU/GPU/温度 来自实例端 `GET /h3ui/stats` 采样；显存/内存/排队 来自 ComfyUI `/system_stats` 与 `/queue`
- 端点缺失时相关卡片显示 `--`，不影响其余数据

**实例管理（AutoDL 标准区）**
- App 内登录 AutoDL 获取 token，自动列出实例并轮询状态
- 开机 / 关机 / 定时关机；「完成后关机」可在队列结束后自动下载视频再关机（一次性生效）
- 选中实例后自动从 `service_6006_domain` 提取 ComfyUI 转发地址并连接；实例开机后自动获取，无需手动刷新
- 本地计费：按实例列表返回的 `payg_price` 与 `status_at` 实时折算本次开机费用

## 实例侧配置（一行命令）

在 AutoDL 实例 SSH 终端中执行。若 GitHub 访问失败，先执行 `source /etc/network_turbo` 开启学术加速。

```bash
# 1) 自定义端点：删除视频 + 性能采样（重启 ComfyUI 后生效；路径不同请自行调整）
curl -fsSL https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/h3ui_api.py -o /root/autodl-tmp/ComfyUI/custom_nodes/h3ui_api.py

# 2) ComfyUI 启动脚本（AutoDL 社区镜像路径）
curl -fsSL https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/boot/start_h3.sh -o /root/autodl-tmp/ComfyUI/start_h3.sh && chmod +x /root/autodl-tmp/ComfyUI/start_h3.sh

# 3) 开机自启（追加到 /etc/autodl.sh，下次开机生效）
curl -fsSL https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/boot/autodl_boot.sh >> /etc/autodl.sh
```

说明：
- `start_h3.sh` 中的 `--enable-cors-header` 为浏览器/APK 跨域访问所必需，不可省略
- 开机自启原理：AutoDL 容器开机由 supervisord 执行 `/etc/autodl.sh`，脚本等 15s 后探测 6006 端口，已有服务则跳过，否则后台拉起 `start_h3.sh`（日志：`/root/autodl-tmp/comfyui_h3.log`）；开机到服务就绪约需 50~80s
- `h3ui_api.py` 提供 `POST /h3ui/delete`（删除 `output/` 下文件，带路径穿越防护），供控制台删除云端视频；`GET /h3ui/stats`（CPU/GPU 利用率采样）供控制台"性能监测"面板，缺失时面板显示 `--`
- 更新 `h3ui_api.py` 后需重启 ComfyUI 生效；custom_nodes 端点只在 ComfyUI 启动时加载

## APK 构建

```bash
cd apk/H3Console
JAVA_HOME=<JDK路径> gradle assembleDebug
# 产物: app/build/outputs/apk/debug/app-debug.apk
```

- 依赖 `androidx.browser:browser:1.8.0`（Chrome Custom Tabs）：首次构建需联网拉取，之后可加 `--offline` 离线构建
- `JAVA_HOME` 需指向 JDK 17+（Android Studio 自带 JBR 即可）

## 仓库结构

```
h3_console.html        控制台单文件前端（双主题 + 中英 i18n，零 CDN）
h3ui_api.py            ComfyUI custom node：/h3ui/delete、/h3ui/stats 端点
boot/start_h3.sh       ComfyUI 启动脚本（--enable-cors-header 必需）
boot/autodl_boot.sh    开机自启钩子（追加到 /etc/autodl.sh，开机自动刷新 h3ui_api.py）
apk/H3Console/         Android WebView 壳工程（原生桥接：登录、文件选择、下载、外链）
autodl_ssh.py          SSH 辅助脚本（凭据走 .env，不入库）
docs/CHANGELOG.md      版本变更记录
```

## SSH 工具配置（可选）

`autodl_ssh.py` / `h3_progress.py` 为辅助脚本。复制本仓库并创建 `.env`：

```
AUTODL_SSH_HOST=connect.xxx.seetacloud.com
AUTODL_SSH_PORT=22
AUTODL_SSH_USER=root
AUTODL_SSH_PASSWORD=...
```

## 许可

[GPL-3.0](LICENSE)
