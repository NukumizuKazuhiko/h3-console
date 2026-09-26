# H3 Console 项目结构与功能文档

> 更新时间：2026-09-26 · 代码基线：v1.92（v1.35–v1.63 曾长期未提交，随 v1.64 一并入库）
> 逐版本变更见 [CHANGELOG.md](CHANGELOG.md)，本文只描述当前形态与设计。

## 1. 项目定位

H3 Console 是一个在租用 GPU（AutoDL 标准区 4090 等）上通过 ComfyUI 本地运行开源 MiniMax H3 模型、
生成 15s 内带音频短视频的**手机优先**控制台。三件套组成：

1. **单文件前端** `h3_console.html` —— 全部 UI 与业务逻辑（双主题、中英 i18n、零 CDN）
2. **Android WebView 壳** `apk/H3Console/` —— 提供原生桥（登录/外链/复制/文件选择/下载）
3. **实例侧脚本** —— ComfyUI custom node 端点 + 启动/开机自启脚本

关键背景：AutoDL 官方 API 管不了标准区实例的开关机，项目实际使用的是**网页控制台内部 API
（`https://www.autodl.com/api/v1/`）的重放**（逆向笔记见 `autodl-console-api-note/README.md`）。
ComfyUI 公网转发地址获取链见 §3「公网转发地址获取链」（v1.91 起三级优先级）。

**生成提交走实例侧官方风格 API**（v1.92）：App 不再本地组工作流图 POST `/prompt`，
改调 ComfyUI custom node `h3ui_api.py` 暴露的 MiniMax 文档风格端点——
`POST /h3ui/v1/video_generation`（业务参数：prompt/width/height/length/seed/turbo/strength/
first_frame/last_frame/client_id；服务端从 `/object_info` 实际枚举动态选模型文件并组装工作流，
内部自提交通进同一队列，返回 `task_id` 即 prompt_id，App 的 WS 进度与 `/history` 轮询不变）、
`GET /h3ui/v1/queries/video_generation?task_id=`（Queued/InProgress/Completed/Failed + file_id）、
`GET /h3ui/v1/files/retrieve?file_id=`（output 文件下载）、`GET /h3ui/v1/models`（就绪状态）。
响应统一 `base_resp{status_code,status_msg}`；模型缺失返回 2013。
模型文件（约 41.4 GiB：DiT int8 + Qwen3-VL nvfp4_awq + 双 VAE + Turbo LoRA）由
`boot/h3_models_download.sh` 从 ModelScope 魔搭（`Comfy-Org/MiniMax-H3`）下载，
幂等可续传。`boot/start_h3.sh` 无卡模式自动加 `--cpu`（ComfyUI 0.35 无 GPU 会硬崩溃）。

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
- **App 壳布局**：body 固定 100dvh 纵向 flex；三页为 `#pagesWrap > #pagesTrack > div` 横排 track
  结构（各页 `overflow-y:auto + overscroll-behavior:contain` 独立滚动，保留各自滚动位置）
- **滑动翻页 pager（v1.67）**：Pointer Events 驱动，横拖 track 实时跟手（`translate3d`），
  竖向手势让位原生滚动（`touch-action:pan-y` + 8px 轴向判定）；松手按位移 >30% 屏宽或
  甩动速度（>0.4px/ms 且移动 >4%）翻页，否则回弹；边缘 0.25 阻尼；输入框/按钮/下拉等
  交互元素不劫持手势。连续进度 `pageProgress` 驱动高亮药丸与图标缩放/文字透明度插值；
  页签点击与滑动走同一 pager，页面永不销毁重建
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

**开屏与引导**（v1.75–v1.77）
- 开屏登录页：仅未持有 AutoDL 令牌时全屏拦截一次（App 走原生 `openLogin`，浏览器提供粘贴令牌入口）
- 模式选择屏：新手/老手卡片（`localStorage h3_level`），设置页「使用模式」可重选
- **新手租机引导屏**（`#nbMask`）：仅 GPU 型号可选——并发查各地区 `machine/region/gpu_type`，
  只保留有空闲的型号并汇总空闲数；每型号在其空闲最多区查 `user/machine/list` 取最低按量价，
  下拉项标注「¥{p}/时起」并按最低价升序排列（Tom Select，查不到价沉底），**最便宜型号默认选中**；
  地区按空闲数量自动匹配（`nbBest`），镜像锁定 ComfyUI v18 社区镜像（image_id 799 / v18 字符串比较），
  机器自动选同型号最低价空闲机，下单走 `order/instance/create/payg`（与租用弹窗同款错误分支）；
  按钮区含「充值」ghost 按钮（`openExternal` 打开 `autodl.com/recharge`，余额不足时无需离开引导）；
  可「稍后再说」跳过
- **下单后自动部署**（v1.79 引入；v1.93 扩为「部署四连 + 无卡下载」）：下单成功 → 等实例入列并选中 →
  自动开机等 running → 解析实例卡 `ssh_command`（`-p PORT root@HOST`）与 `root_password` →
  原生桥 `H3App.sshExec`（JSch，MainActivity 后台线程，回调 `window.__sshDone`）执行部署四连
  （h3ui_api.py / start_h3.sh / autodl_boot.sh / h3_models_download.sh，先 `source /etc/network_turbo`）→
  `power_off` → **无卡模式开机**（`power_on` + `payload:"non_gpu"`，¥0.10/时）→ SSH `setsid` 后台启动
  模型下载（~41.4 GiB），每分钟轮询日志尾行 + `du -sh` 显示进度（提示行「模型下载中（已下载 x）」），
  出现 `===== done rc=0 miss=0` 即成功（上限 4 小时，脚本幂等可续传）→ `power_off` → 正常有卡开机 →
  SSH 内 `curl 127.0.0.1:6006/h3ui/stats` 验证；各阶段进度写在实例页电源提示行，失败提示按 README
  手动部署。浏览器端无原生桥自动跳过。
  部署期间对应实例卡右上角显示脉冲「自动配置中」角标（`nbDeployingUuid` + `cfgTag`，结束自动摘除）

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

### 3.5 API 适配层

ComfyUI 侧与 AutoDL 侧各有适配器注册表（v1.72）：`registerComfyAdapter`/`registerDlAdapter`
注册、`useComfyAdapter`/`useDlAdapter` 切换，默认实现即原有直连行为，行为不变。

- **ComfyUI 适配器接口**：`url(path)` / `nb(path)`（带防缓存）/ `wsUrl()`；
  `api()`、`nb()`、`openWs()` 均为适配器委托
- **AutoDL 适配器接口**：`base` / `headers()` / `request(method, path, body, params)`——
  POST/GET/PUT 统一走 `request`：基址 `https://www.autodl.com`，头 `Authorization: token`，
  响应统一 `{code:"Success"}` 校验，失败重试 1 次（间隔 2s），30s 超时；
  `dlCall`/`dlGet`/`dlPut`/`dlHeaders` 与租用下单均为适配器委托

**公网转发地址获取链**（v1.91 重写，`autoSetApi`，三级严格按优先级、任一级实测 `/system_stats`
通过即停；`autoSetApiBusy` 防轮询重入）：
① Web 数据——实例卡缓存 + `instance/detail` 接口的结构化字段（`fwdFromFields`，
`service_6006_domain` 可能指向 JupyterLab，必须实测）；② 转发地址寻找——全量 JSON 深度扫描
`*.seetacloud.com`（`fwdFromScan`，`u数字-` 前缀独立转发优先）；③ SSH 寻找——读实例内
proxy 进程环境变量自报地址（`fwdFromSsh`，`AutoDLService6006URL` 等为权威来源；ComfyUI
启动中暂未响应也先填入，由连接层重试）。全部失败清残留 `127.0.0.1` 地址并提示手动填写。
SSH 隧道数据通道已停用（`SSH_TUNNEL_ON=false`），SSH 仅用于读地址与部署端点脚本
（历史：v1.81 引入隧道、v1.83 PNA 预检代答、v1.86 实例侧端口探测，代码保留待复用）。
回环访问受 Chromium **PNA** 限制（v1.83 试以预检代答修复，v1.84 结构性修复）：
页面改经 **WebViewAssetLoader** 以 `https://appassets.androidplatform.net/assets/index.html`
正式源加载（file:// 的 null 源访问回环地址在预检之前即被拦截，代答无从生效；https 源
访问回环属「安全上下文访问可信回环」放行）；`shouldInterceptRequest` 对 127.0.0.1 的
OPTIONS 预检代答并补 `Access-Control-Allow-Private-Network: true` 兜底；建隧后页面侧
`fetch /system_stats` 健康检查，失败断开并冷却 60s（`sshTunnelFailAt`），提示行附最后
一次 fetch 真实错误。登录 token 同步存 SharedPreferences（`h3cfg/token`），换源/重装后
`onPageFinished` 自动注入；页面登出走 `H3App.clearToken()` 同步清除。

## 4. APK 壳（com.h3.console）

- `MainActivity`：全屏透明系统栏 + SHORT_EDGES 刘海；`windowSoftInputMode=adjustPan`（防导航栏上浮）；
  WebView 开 JS/DOM storage/自动播放媒体
- **原生桥 `H3App`**（`@JavascriptInterface`）：
  `openLogin()`（拉起 LoginActivity，onActivityResult 回传 token 经 `applyToken()` 注入页面）、
  `openUrl()`（外链三级回退：声明了具体 host 的原生 App → Chrome Custom Tabs → 系统浏览器，
  判据 `ri.filter.countDataAuthorities()>0`）、`setLightSystemBars(light)`（状态栏图标随主题）、
  `copyText()`（剪贴板 + toast）、`sshExec(id, host, port, user, password, cmd)`
  （JSch 单命令执行，完成后 evaluateJavascript 回注 `window.__sshDone(id, code, out)`）、
  `sshTunnelOpen(id, host, port, user, password, remotePort)` / `sshTunnelClose(id)`
  （JSch 本地端口转发 `setPortForwardingL("127.0.0.1", 0, "127.0.0.1", remote)`，
  回注 `window.__tunnelDone(id, "<localPort>")`，会话表 keepalive 15s）、
  `isDebug()`（FLAG_DEBUGGABLE；为 true 时设置页显示 DEBUG 虚线框：模拟新手 / 清除数据 / 打开开屏页，
  实例页显示「一键配置」= 对选中实例手动跑 `nbDeployFlow`；release 自动隐藏）
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
