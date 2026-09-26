# H3 Console 项目结构与功能文档

> 更新时间：2026-09-26 · 代码基线：v1.64（v1.35–v1.63 曾长期未提交，随 v1.64 一并入库）
> 逐版本变更见 [CHANGELOG.md](CHANGELOG.md)，本文只描述当前形态与设计。

## 1. 项目定位

H3 Console 是一个在租用 GPU（AutoDL 标准区 4090 等）上通过 ComfyUI 本地运行开源 MiniMax H3 模型、
生成 15s 内带音频短视频的**手机优先**控制台。三件套组成：

1. **单文件前端** `h3_console.html` —— 全部 UI 与业务逻辑（双主题、中英 i18n、零 CDN）
2. **Android WebView 壳** `apk/H3Console/` —— 提供原生桥（登录/外链/复制/文件选择/下载）
3. **实例侧脚本** —— ComfyUI custom node 端点 + 启动/开机自启脚本

关键背景：AutoDL 官方 API 管不了标准区实例的开关机，项目实际使用的是**网页控制台内部 API
（`https://www.autodl.com/api/v1/`）的重放**（逆向笔记见 `autodl-console-api-note/README.md`）。
ComfyUI 转发地址来自实例数据的 `service_6006_domain` 字段（仅在 running 后存在）。

## 2. 目录结构

```
h3_console.html            ★ 控制台前端（~2560 行：样式 + 内联 Tom Select/Alpine + 业务 JS）
apk/H3Console/             ★ Android WebView 壳工程
  app/src/main/assets/h3_console.html        与根目录前端逐字节同步（构建时打包进 APK）
  app/src/main/java/com/h3/console/          MainActivity（主 WebView + 桥） LoginActivity（token 抓取）
boot/start_h3.sh           ComfyUI 启动脚本（--enable-cors-header 必需）
boot/autodl_boot.sh        开机自启钩子（追加到实例 /etc/autodl.sh，开机自动刷新 h3ui_api.py）
h3ui_api.py                ComfyUI custom node：GET /h3ui/stats、POST /h3ui/delete
h3ui_router.py             （已永久搁置）把 h3_console.html 挂到 ComfyUI /h3ui 路由的 custom node
autodl-console-api-note/   AutoDL 网页控制台 API 逆向笔记（端点表/鉴权/curl 示例，不含凭证）
autodl_ssh.py              本地 SSH 辅助：凭据读 .env，`py autodl_ssh.py "<cmd>"` 远程执行
h3_progress.py             H3 权重 aria2 下载进度看板（轮询 SSH，解析 aria2 日志）
aria2_int8.txt             权重下载清单（modelscope 5 个文件，共 ~44GB）
h3_prompt_smoke.json       冒烟测试工作流（t2v 5s，与 buildWorkflow() 同构）
probe_api.py               探测本机 6006 各端点的临时脚本
gw.html                    抓取的第三方 webos 页面样本，非产品组件，可删
_fix3.js / _merge.js       一次性改码草稿（_merge 已完成 v1.63 面板合并；_fix3 为调试残留）
.env                       SSH 凭证（gitignored，勿外传）
H3控制台.apk                成品 APK（gitignored，用户自行发 Release）
docs/CHANGELOG.md          版本变更记录
```

## 3. 前端 h3_console.html

### 3.1 技术形态

- **零 CDN 单文件**：Tom Select 2.4.3 与 Alpine.js 3.14.9 整体内联（行 575–981），
  Tom Select 官方 default 皮肤之上用同特异性选择器覆盖为本页色卡皮肤（行 276–300）
- **主题**：`:root` 暗色 + `html[data-theme="light"]` 全套变量；色卡源自 codex AGENTS.md
  （曜石黑底 + 混凝土白 + 电光青 #26CDCB 等）。间距同样令牌化：`--gapPanel/--gapCol/--gapGrid/--gapInline`
- **App 壳布局**：body 固定 100dvh 纵向 flex；三页 `#pagesWrap > div` 为 grid 叠放的独立滚动容器
  （`overflow-y:auto + overscroll-behavior:contain`），切页纯 transform 横移 + 高亮药丸滑动，
  每页保留自己的滚动位置
- **底部导航**：悬浮胶囊液态玻璃（毛玻璃 blur+saturate），三个页签：创作 / 实例 / 设置

### 3.2 三页功能

**创作页**（`#pageCreate`）
- 创作面板：首帧/尾帧图片上传（留空 t2v、仅首帧 i2v、首尾 flf2v）、提示词（3 个英文预设）、
  分辨率（1344×768 默认 + 竖屏档）、时长滑杆（5–15s，帧数对齐 17 的倍数+5）、
  Turbo 8 步 LoRA 开关、LoRA 强度、种子
- 生成面板：生成按钮 / 已用时间 / 进度条 / 当前节点行 / 任务队列（中断、移除，页面内确认框）
- 性能监测：CPU/GPU/GPU 温度/显存/内存五卡片 + 队列行；CPU/GPU/温度来自 `/h3ui/stats`，
  显存/内存来自 `/system_stats`，端点缺失显示 `--`
- 结果面板：内嵌播放器（生成完成自动播放）+ 历史记录（播放/下载/删除，删除同步删云端文件与
  ComfyUI history，localStorage 保存最近 20 条）

**实例页**（`#pageInstance`）
- 统一面板（v1.63 把原「连接」与「实例管理」合并）：实例选择 + 租用/获取列表按钮、状态点
  （实例状态 / ComfyUI 连接 / 显存 / GPU）、电源控制（开机/关机/完成后关机开关/定时关机折叠项）、
  计费行（`payg_price` + `status_at` 本地折算本次开机费用）、实例卡片列表
- 实例卡片：名称（点击原地改名，PUT `instance/name`，字段 `instance_name`）、规格/单价/状态/镜像、
  SSH 命令与 root 密码掩码点击复制（`H3App.copyText`）、无卡模式角标（¥0.10/时）、
  操作按钮（开机/无卡开机/关机/重启/定时关机/释放，释放为双重危险确认）

**设置页**（`#pageSettings`）
- 账号：登录 AutoDL（走原生 LoginActivity）、用户名/余额/代金券（`user/detail` + `wallet`，
  ÷1000 换算）、充值跳转、退出登录
- 语言（zh/en）、主题切换（联动 `H3App.setLightSystemBars`）、GitHub 仓库、爱发电赞助（外链均走 `openExternal`）

**租用弹窗**（`#rentMask`，v1.47 起为直连下单流程）
地区 `region/list`（公开）→ GPU 型号 `machine/region/gpu_type`（显示空闲 x/y，0 空闲禁用）→
机器 `user/machine/list`（payg 按价排序，显示空闲数与单价）→ 镜像双页签（基础镜像 `image/all`
/ 社区镜像 `image/codewithgpu/list`，锁定 comfyanonymous/ComfyUI image_id=799 v18，
version 为字符串比较）→ 数量 → `order/price/preview` 估价 → `machine/check_machine_online` →
`order/instance/create/payg` 立即下单（基础镜像走 `base_image_uuid`，社区走
`reproduction_uuid:"uuid:v版本"` + `reproduction_id`）。`MachineGpuNumUpdateFailed` 提示刷新重选，
`InsufficientBalance` 提示充值（需覆盖 1 小时费用）。

### 3.3 数据层（localStorage）

| 键 | 内容 |
|---|---|
| `h3_dltoken` | AutoDL 网页 token（全账号凭证，`cleanToken()` 去引号） |
| `h3_api` | ComfyUI API 地址 |
| `h3_inst` | 选中的实例 uuid |
| `h3_lang` / `h3_theme` | 语言 / 主题 |
| `h3_autooff` | 完成后关机开关 |
| `h3_history` | 生成历史（≤20 条：pid/时间/耗时/URL/文件名） |
| `h3_active` | 进行中任务快照（pid/开始时间/标签/队列），刷新后恢复追踪 |

### 3.4 ComfyUI 交互

- REST：`/system_stats`、`/queue`、`/prompt`、`/interrupt`、`/history/{pid}`、`/upload/image`、`/view`；
  全部 GET 带 `_=Date.now()` cache-buster + `no-store`（穿透转发层时启动窗口期响应会被缓存）
- WebSocket `/ws?clientId=h3ui-*`：progress（采样步数）、executing（节点名，i18n 映射 15 个节点）、
  execution_interrupted
- 工作流 `buildWorkflow()`：15 节点固定图 —— UNETLoader(int8_convrot DiT) → LoraLoaderModelOnly
  (turbo 8 步，strength 可调) + CLIPLoader(qwen3vl 32B nvfp4_awq, type:minimax) + 双 VAE →
  MiniMaxH3ImageToVideo → RandomNoise/KSamplerSelect(res_multistep)/BasicScheduler(8 或 20 步)/
  BasicGuider/SamplerCustomAdvanced → VAEDecode + VAEDecodeAudio → CreateVideo(24fps) →
  SaveVideo(`video/H3_t2v`)。首帧/尾帧注入节点 16/17（LoadImage）
- **轮询节律**（v1.52 统一）：实例状态/列表 4s（`pollInstStatus`）、ComfyUI 状态+监测 4s
  （`pollStatus`）、任务结果 3s（`waitForResult`，2h 超时；resume 模式失败 20 次判 ComfyUI 不可达）
- **状态归一在权威数据源**：连接状态判断以 `pollInstStatus` 的实例状态为准（实例关机即显示"实例未开机"），
  外层 catch 只做降级展示；`running` 标志在 `startRun/finishRun` 中切换
- 断点恢复：`restoreOnLoad` 支持 `?pid=` 直连恢复、`h3_active` 快照恢复、`resumeFromQueue`
  从 `/queue` 里按 `client_id` 前缀 `h3ui-` 认领任务（最多重试 20 次）
- 完成后关机：队列清空后若开关打开 → 自动下载（App 内经 DownloadManager，浏览器端 blob 下载）
  → App 内等 15s / 浏览器 3s → `power_off`（一次性生效，开关状态持久化）

### 3.5 AutoDL API 封装

`dlCall`(POST) / `dlGet` / `dlPut`：基址 `https://www.autodl.com`，头 `Authorization: token`，
响应统一 `{code:"Success"}` 校验，失败重试 1 次（间隔 2s），30s 超时。
`findForwardUrl` 从实例数据提取 `service_6006_domain`（拼 `https://`，无端口补 `:8443`），
兜底匹配 `*.seetacloud.com`。

## 4. APK 壳（com.h3.console）

- `MainActivity`：全屏透明系统栏 + SHORT_EDGES 刘海；`windowSoftInputMode=adjustPan`（防导航栏上浮）；
  WebView 开 JS/DOM storage/自动播放媒体
- **原生桥 `H3App`**（`@JavascriptInterface`）：
  `openLogin()`（拉起 LoginActivity，onActivityResult 回传 token 经 `applyToken()` 注入页面）、
  `openUrl()`（外链三级回退：声明了具体 host 的原生 App → Chrome Custom Tabs → 系统浏览器，
  判据 `ri.filter.countDataAuthorities()>0`）、`setLightSystemBars(light)`（状态栏图标随主题）、
  `copyText()`（剪贴板 + toast）
- `WebChromeClient.onShowFileChooser`：`<input type=file>` 在 Android WebView 必须实现此回调才响应
- `DownloadListener`：下载存 `Pictures/product/时间戳.mp4`；Q 以下申请写存储权限
- `LoginActivity`：WebView 打开 `autodl.com/console/`，每 2s 轮询 `localStorage.getItem('token')`，
  取到（去引号）即 setResult 返回
- Manifest：`<queries>` ACTION_VIEW+https（Android 11+ 包可见性）；`androidx.browser:browser:1.8.0`
- 构建：`cd apk/H3Console && JAVA_HOME=<JDK17+> gradle assembleDebug`；minSdk 24 / targetSdk 34

## 5. 实例侧

**h3ui_api.py**（ComfyUI custom node）
- `GET /h3ui/stats`：`/proc/stat` 双采样 0.2s 差分算 CPU；pynvml 取 GPU 利用率+温度，
  无 pynvml 降级 nvidia-smi
- `POST /h3ui/delete`：删除 `output/` 下文件，realpath 前缀校验防路径穿越

**boot 脚本**
- `start_h3.sh`：`/root/LaunchTool311/startup.py` 拉起 ComfyUI，`--enable-cors-header` 必需
  （浏览器/APK 跨域），端口 6006，latent2rgb 预览
- `autodl_boot.sh`（追加到实例 `/etc/autodl.sh`，supervisord 开机执行）：sleep 15s →
  从 GitHub raw 刷新 h3ui_api.py（端点升级开机自动生效）→ 探测 6006 不通则
  `setsid bash start_h3.sh` 后台拉起（日志 `/root/autodl-tmp/comfyui_h3.log`）。
  注意：custom_nodes 端点只在 ComfyUI 启动时加载，更新脚本需重启（队列空闲时）

部署三连（README「实例侧配置」）：实例 SSH 里 curl 拉取上述两个脚本 + 追加开机钩子。

## 6. 辅助工具（PC 侧）

- `autodl_ssh.py`：paramiko 单命令执行，`.env` 提供凭证（host/port/user/password）
- `h3_progress.py`：每 30s 轮询 SSH，解析 aria2 日志（FILE: 行与状态行配对），
  渲染 5 个权重文件的进度条看板，aria2 退出但文件未齐时告警
- `aria2_int8.txt`：modelscope 下载清单（DiT 21G / TE 15.7G / video VAE 5.2G / audio VAE 0.6G / LoRA 2G）

## 7. 已知问题与待办

1. ~~版本号不同步~~ / ~~定时关机格式不一致~~ / ~~悬空引用 `rentLoadMachines`~~ / ~~README 落后~~ —— 已在 v1.64 修复（定时关机统一为 `YYYY-MM-DD HH:mm` 字符串；versionCode 35）
2. 实例页定时关机当前与创作页同为字符串格式；autodl-console-api-note 依据官方前端 bundle 记载毫秒时间戳可行，两种说法矛盾——如遇服务端拒绝可回看该笔记再试
3. 根目录 `_fix3.js`、`_merge.js`、`gw.html`、`probe_api.py` 为一次性草稿/参考残留，可清理

## 8. 安全与运维约束（持续有效）

- `.env`（SSH 凭证）gitignored；AutoDL token 是全账号会话凭证，只存 APK localStorage，会过期
- 开关机/释放等计费操作均带页面内确认框（Android WebView 无原生 confirm，故有 `uiConfirm`）
- 控制台不硬编码个人转发地址/单价/Token，可通用分发；生成区不显示 ¥ 成本，计价只在实例页 billLine
