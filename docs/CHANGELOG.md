# 更新日志

## v1.96（2026-09-26）
- **新手/老手模式选择改为下拉栏**（与其他选择器统一）：模式选择屏的双卡片改为
  Tom Select 下拉（选项「新手 — 描述」/「老手 — 描述」，当前模式预选中）+「确定」按钮提交；
  `showModePicker` 惰性初始化（隐藏元素上初始化不可靠），语言切换时若选择屏开着实时刷新选项文案；
  移除 `.modeCard` 样式与 `applyLevel` 的卡片选中逻辑；设置页「重新选择」入口行为不变

## v1.95（2026-09-26）
- **修复：无卡模式下创作页计费行仍按 GPU 原价累计**——`pollInstStatus` 现按
  `start_mode === "non_gpu"` 判定无卡运行态，计费行改按 ¥0.10/时 累计并在金额后追加
  「¥0.10/时（无卡）」标注，与实例卡单价显示一致（`instNonGpuNow` 全局标记 + `renderBill` 后缀）

## v1.94（2026-09-26）
- **自动部署全流程断点检测与步骤进度**（`nbDeployRun` 重构）：
  - **八步逻辑步骤号**：进度提示行统一带 `[n/8]` 前缀（等实例入列/开机/SSH/部署四连/无卡开机/
    模型下载/有卡开机/验证），部署四连内部再显示 `i/4` 子进度，模型下载显示
    「{size}/约41G，{pct}%，已用时 {min} 分钟」（按 `du` 实测大小折算百分比）
  - **断点检测（SSH 实例侧状态探测，权威续跑依据）**：进流程后先探测
    组件 4 项在位情况（h3ui_api.py / start_h3.sh / autodl.sh 钩子 / 下载脚本）、
    下载进程是否存活（`pgrep`，`[d]` 方括号防自匹配）、下载日志 done 标记（`done rc=0 miss=0`）、
    `/h3ui/stats` 端点可用性、models 目录实测大小，据此跳过已完成阶段：
    组件齐→跳过下发；已在无卡模式运行→跳过开关机直接续传；下载进程存活→不清日志直接续听；
    下载完成→跳过无卡阶段直达有卡开机；端点可用+模型齐+有卡运行→快路径直达验证
  - **localStorage 检查点** `h3_deploy_ckpt`：每步落盘 `{uuid, step, at}`，中断重跑（一键配置 /
    重新下单）时与实例侧探测共同触发「检测到上次部署进度，自动续跑」toast；仅在验证成功后清除
- 开关机阶段均按实例当前 `status`/`start_mode` 幂等跳过，不再盲目关机重开
- i18n 新增 `nbDeploySkip` / `nbDeployNoCardSkip` / `nbResume` / `nbAllReady`，
  `nbDeployDlWait` 增加 `{pct}` 占位

## v1.93（2026-09-26）
- **模型下载挂入首次自动部署流程**（`nbDeployRun`）：
  ① 部署三连扩为**四连**——新增下发 `boot/h3_models_download.sh` 到 `/root/autodl-tmp/`；
  ② 首次重启改为 **关机 → 无卡模式开机**（`power_on` + `payload:"non_gpu"`，¥0.10/时，
  模型下载不需要 GPU）；③ 无卡模式下 SSH `setsid` 后台启动模型下载（魔搭源，幂等可续传，
  先 `pkill` 防重跑冲突 + 清日志），每分钟轮询日志尾行与 `du -sh` 进度，提示行实时显示
  「模型下载中（已下载 x，已用时 y 分钟）」，出现 `===== done rc=0 miss=0` 判定成功
  （轮询上限 4 小时，超时/校验失败即中断提示，可重跑续传）；④ 下载完成 → 关机 →
  **正常有卡开机** → 接续原有 `/h3ui/stats` 端点验证
- i18n 新增 `nbDeployNoCard` / `nbDeployDlStart` / `nbDeployDlWait`（含 {size}/{min} 占位）/
  `nbDeployDlFail`；`nbDeployOk` 更新为「模型已下载」；`pkill` 模式用 `[d]` 方括号技巧避免误杀自身 shell
- 实例侧开机钩子 `autodl_boot.sh` 行为不变（每次开机刷新 h3ui_api.py + 拉起 ComfyUI），
  无卡下载期间其 `--cpu` ComfyUI 可能被 2GB cgroup OOM，不影响下载进程

## v1.92（2026-09-26）
- **生成提交改走实例侧官方文档风格 API**（`/h3ui/v1/video_generation`）：工作流图固化在服务端
  （`h3ui_api.py` custom node），App 只传业务参数（prompt/分辨率/时长/seed/turbo/首尾帧），
  彻底隔离 ComfyUI 版本、节点注册名、模型文件名差异。配套端点：
  `GET /h3ui/v1/queries/video_generation`（状态查询）、`GET /h3ui/v1/files/retrieve`（结果取回）、
  `GET /h3ui/v1/models`（模型就绪状态）；响应带 `base_resp{status_code,status_msg}` 对齐官方风格
- 服务端动态模型适配：从 `/object_info` 实际枚举按优先级挑选模型文件（int8→fp8→int4→bf16 等），
  模型缺失时返回 2013 明确报错而非 400 哑错；首尾帧支持已上传文件名 / base64 dataURL / URL
- App 端 `generate()` 改调新 API（task_id 即 prompt_id，WS 进度与历史轮询逻辑不变），
  删除客户端 `buildWorkflow()`；业务错误快速失败不重试，新增「模型未就绪」i18n
- **根因修复**：400 真因是新实例上没有任何 H3 模型文件（镜像仅含 ComfyUI 本体）。
  新增 `boot/h3_models_download.sh`：ModelScope 魔搭源（Comfy-Org/MiniMax-H3）下载
  DiT int8 + Qwen3-VL nvfp4_awq + 视频/音频 VAE + Turbo LoRA（约 41.4 GiB，幂等可续传）

## v1.91（2026-09-26）
- **重写公网转发地址获取链**（`autoSetApi`），三级严格按优先级，任一级实测可用即停：
  ① Web 数据——实例卡缓存 + detail 接口的结构化字段（`service_6006_domain` 等）逐个实测
  ② 转发地址寻找——全量 JSON 深度扫描 `*.seetacloud.com`（`u数字-` 前缀独立转发优先）逐个实测
  ③ SSH 寻找——读实例内 proxy 进程环境变量自报地址（`AutoDLService6006URL` 等），实测通过采用，
  ComfyUI 启动中暂未响应也先填入由连接层重试
- 探测/自报/扫描拆为独立函数（`fwdFromFields` / `fwdFromScan` / `fwdProbe` / `fwdPick` / `fwdFromSsh`），
  失败分支不再挂已停用的隧道调用；新增 `autoSetApiBusy` 防轮询重入
- 失败时清掉残留的 `http://127.0.0.1` 本地隧道地址；提示行显示获取进度与失败说明（中英文）

## v1.90（2026-09-26）

**公网转发地址自动获取（实例自报）**：经真机 SSH 实测确认——AutoDL 容器内 `proxy`
进程的环境变量 `AutoDLService6006URL` / `AutoDLServiceURL` 直接携带本机公网转发地址
（如 `https://uXXXXX-xxx.<区>.seetacloud.com:8443`），且该地址 `/system_stats` 实测 200。

- 新增 `sshFindForward`：经 SSH 读实例环境变量提取转发地址（正则校验 seetacloud 域名）
- `autoSetApi` 取址顺序：实例自报地址（实测通过）→ API 数据候选逐个实测 → 自报地址
  未实测通过也填入 → 数据候选首选兜底
- SSH 隧道数据通道保持停用（`SSH_TUNNEL_ON=false`）；SSH 仅用于读地址与部署端点

## v1.89（2026-09-26）

**修复启动后仍沿用 127.0.0.1 隧道地址**：本地存储里残留的隧道地址在隧道停用后不会被
替换。轮询的陈旧检测改为：隧道停用时任何 `http://127.0.0.1` API 地址一律视为陈旧，
实例运行中即自动触发 `autoSetApi` 换成实测可用的公网转发地址（轮询周期 4 秒内生效）。

## v1.88（2026-09-26）

**SSH 隧道路径暂时停用**：公网转发地址（seetacloud 独立转发 + 逐候选实测）可用后，
SSH 隧道回退不再需要。新增开关 `SSH_TUNNEL_ON = false`，`sshTunnelApi` 直接短路返回
null（无公网转发时回到「提示手动填写」的原行为）；隧道/探测代码全部保留，改回
`true` 即可恢复。新手引导的 SSH 自动部署（放端点脚本）不受影响，照常工作。

## v1.87（2026-09-26）

**修复公网转发地址选错**：实例数据里 `service_6006_domain` 可能指向 JupyterLab（6006 是
Lab 的端口），旧逻辑盲信该字段导致填错 ComfyUI 地址。真正有效的是
`https://uXXXXX-xxx.nmb1.seetacloud.com:8443` 这类独立转发。

- `findForwardUrl` 重构为 `forwardCandidates`：收集实例数据中全部 seetacloud 转发地址
  （无端口补 `:8443`），排序为 u 前缀独立转发 → 其余 seetacloud → `service_6006_domain`
- `autoSetApi` 逐候选实测 `GET /system_stats`（6s 超时），只用真正应答 ComfyUI 的地址；
  全部探测失败时仍回填首选让 connect 报具体错误
-隧道回退逻辑不变（v1.86 的实例侧端口探测对无公网转发的地区依然生效）

## v1.86（2026-09-26）

**修复隧道 HTTP 404**：404 说明隧道已通、请求已到实例并拿到 HTTP 响应，但 6006 上
应答的不是 ComfyUI（部分镜像的启动器/平台代理占 6006，ComfyUI 实际在 8188 等端口）。

- 建隧前先经 SSH 在实例侧探测：逐候选端口（6006、8188）`curl /system_stats`，哪个返回
  200 就转发哪个；探测失败回落 6006
- 自动部署验证（`/h3ui/stats`）同样改为逐端口探测（`curl -sf` + `break`）
- 提示文案去掉硬编码 6006（「本机 127.0.0.1 → 实例 ComfyUI 端口」）

## v1.85（2026-09-26）

**修复 v1.84 启动即 `net::ERR_INVALID_RESPONSE`**：WebViewAssetLoader 的加载 URL 写成了
`/assets/index.html`，但资产文件名是 `h3_console.html`，处理器找不到文件返回无效响应。
改为 `https://appassets.androidplatform.net/assets/h3_console.html`，其余同 v1.84。

## v1.84（2026-09-26）

**修复：SSH 隧道本地转发地址 `http://127.0.0.1:<port>` 页面侧 fetch 全部 Failed to fetch。**

- 根因：页面此前以 `file://`（null 源）加载，Chromium 对 null 源访问回环地址的 PNA/CORS 拦截发生在预检之前，v1.83 的预检代答无从生效
- 结构性修复：MainActivity 改用 **WebViewAssetLoader**，页面以 `https://appassets.androidplatform.net/assets/index.html` 正式源加载；https 源访问回环地址属「安全上下文访问可信回环」，fetch/ws 正常放行；PNA 预检代答保留兜底
- token 迁移：登录成功时同步存 SharedPreferences（`h3cfg/token`），换源后首次 `onPageFinished` 若页面无 token 自动注入（applyToken），无需重新登录；页面内登出经新增原生桥 `H3App.clearToken()` 同步清除持久化 token，避免重载后被自动登回
- 隧道健康检查失败时提示行附上最后一次 fetch 的真实错误（`[TypeError: ...]` / `[HTTP xxx]`），便于真机排查
- 新增依赖 `androidx.webkit:webkit:1.10.0`（首次构建需联网拉取）
- 注意：换源后 localStorage 域切换，语言/主题/新手等级等偏好会重置一次（token 已自动迁移）

## v1.83（2026-09-26）

- **修复 SSH 隧道访问本地转发地址 Failed to fetch**：`file://` 页面访问 `http://127.0.0.1` 触发 Chromium **Private Network Access** 预检（`Access-Control-Request-Private-Network`），ComfyUI 的 CORS 扩展不回 `Access-Control-Allow-Private-Network: true` 导致请求被拦——WebView `shouldInterceptRequest` 现在代答对 127.0.0.1/localhost 的 OPTIONS 预检（回显 Origin/Method/Headers + `ACAPN: true`）
- **隧道健康检查**：建隧后以页面侧真实 `fetch /system_stats` 验证（3 次 × 8s 超时），通过才写入 API 地址；失败则断开会话、提示具体错误并冷却 60 秒（避免 4s 轮询反复重连），冷却期内 staleTunnel 自愈同样挂起
- 隧道会话移除 socket 读超时（SO_TIMEOUT 会误杀空闲长连接），仅保留 15s keepalive 与 25s 连接超时
- APK versionCode 54

## v1.82（2026-09-26）

- **DEBUG 面板（仅 debug 签名的 APK 显示）**：新增原生桥 `H3App.isDebug()`（读 `FLAG_DEBUGGABLE`，release 构建自动隐藏全部调试入口）
  - 设置页「DEBUG」虚线框：**模拟新手**（清除使用模式记录，重载后重放模式选择屏 + 新手租机引导，保留登录态）、**清除数据**（`localStorage.clear()` 回到首次安装状态）、**打开开屏页**（重放开屏登录页，附 DEBUG 关闭按钮）
  - 实例页「一键配置」：对当前选中实例手动触发自动部署全流程（开机 → SSH 部署三连 → 重启 → 验证），部署脚本幂等可重复执行
- APK versionCode 53

## v1.81（2026-09-26）

- **无公网转发地区经 SSH 隧道调用 ComfyUI**：部分地区的实例不提供 `service_6006_domain` 公网转发地址——`autoSetApi` 找不到转发地址时自动改走 SSH 本地端口转发（JSch `setPortForwardingL`，手机 127.0.0.1 随机端口 → 实例侧 127.0.0.1:6006），REST 与 WebSocket 全部经隧道，提示「已通过 SSH 隧道连接」
- APK 新增原生桥 `H3App.sshTunnelOpen()/sshTunnelClose()`（会话表管理，15s keepalive）；Manifest 已有的 `usesCleartextTraffic` 使本地明文 http/ws 可用
- 自愈：App 重启后旧隧道端口失效，轮询检测到与现存隧道不一致的 `127.0.0.1` API 地址即自动重建；实例关机/切走公网实例时自动断开隧道；轮询期间加 busy 防重复建隧
- APK versionCode 52

## v1.80（2026-09-26）

- **自动部署期间实例卡显示「自动配置中」角标**：新手租机进入自动部署流程后，对应实例卡右上角挂电光青脉冲角标（`cfgTag`，与无卡模式角标同位互斥），配置完成/失败/跳过后自动摘除；部署阶段进度仍同步显示在实例页电源提示行
- APK versionCode 51

## v1.79（2026-09-26）

- **新手流程自动部署实例侧组件**：新手租机下单成功后全自动完成环境准备——等待实例进入列表并选中 → 自动开机并等 running → 解析实例卡 SSH 命令与 root 密码 → SSH 拉取部署三连（`h3ui_api.py` 入 custom_nodes、`start_h3.sh`、`autodl_boot.sh` 追加到 `/etc/autodl.sh`；GitHub 不通自动先走学术加速）→ 重启实例使 custom_nodes 端点加载 → SSH 内 `curl 127.0.0.1:6006/h3ui/stats` 验证端点，全程实例页电源提示行显示阶段进度
- APK 新增原生桥 `H3App.sshExec()`（JSch/`com.github.mwiede:jsch:0.2.17`，后台线程执行单命令，完成后回注 `window.__sshDone`）；浏览器端无桥时跳过自动部署并提示
- 部署任一步失败均给出输出尾部与「按 README 手动执行部署三连」提示，不影响实例本身可用
- APK versionCode 50

## v1.78（2026-09-26）

- **新手租机引导·充值入口**：确认租用与稍后再说之间新增「充值」按钮（ghost 样式，复用设置页同款 i18n 文案），点击经 `openExternal` 打开 AutoDL 充值页（App 内走三级回退外链）；余额不足报错时按钮就在错误提示旁，不必离开引导流程
- APK versionCode 49

## v1.77（2026-09-26）

- **新手租机引导·价格标注与自动选优**：GPU 型号下拉接入页面内 Tom Select 框架（支持输入过滤），每个型号在其自动匹配区查询按量单价，下拉项标注「¥{p}/时起」；型号列表按最低价升序排列（查不到价的沉底），**最便宜的型号自动排最上并默认选中**
- 地区行同步显示所选型号的匹配区、空闲数与单价（`{name} · 空闲 {idle} 张 · ¥{p}/时`）
- APK versionCode 48

## v1.76（2026-09-26）

- **开屏引导两屏化**：首屏仅保留原生登录（移除粘贴令牌入口）；登录成功后进入第二屏「选择使用模式」全屏页（标题 + 新手/老手纵向堆叠卡片），选定即持久记录（`localStorage h3_level`）并进入主界面；已登录但未选过的老用户升级后首开直接进第二屏补选
  - **新手第三屏·租机引导**：选「新手」后紧接全屏租机页（不弹内部租用弹窗）——仅 GPU 型号可选（只列当前有空闲的型号并汇总空闲数），地区按空闲数量自动匹配（取空闲最多区），镜像锁定 ComfyUI v18 社区镜像（image_id 799 / v18），机器自动选同型号最低价空闲机；可「稍后再说」跳过
  - 新手：实例页显示流程引导提示（租用 → 开机 → 选实例 → 生成 → 定时关机）
  - 老手：ComfyUI API 地址输入框常显，跳过引导
  - 设置页新增「使用模式」行，显示当前模式并可随时重新选择（同款全屏页）
  - 引导屏全部走主题变量与中英文 i18n

## v1.75（2026-09-26）

- **新增开屏登录页**：仅首次打开且未持有 AutoDL 令牌时全屏拦截，登录后才进入主界面；此后无论登录状态如何都不再显示（已登录首开也直接跳过）
  - App 内走原生登录（`H3App.openLogin()` → `applyToken` 回注），登录成功自动进入并拉取实例/账户
  - 浏览器端提供**粘贴令牌进入**入口（与原生登录同一条令牌通道，回车前后 trim）
  - 登录提示（未登录/已登录/过期等）同步显示在开屏页与设置页；主题与中英文随全局设置

## v1.74（2026-09-26）

- **性能监测面板折叠**：与「定时关机」「高级参数」同款折叠（Alpine x-collapse，默认收起），标题沿用面板小标题排版（电光青左侧条以箭头替代）；折叠不影响数据采集，CPU/GPU/显存/内存/队列监控在收起状态下照常更新

## v1.73（2026-09-26）

- 创作页**高级参数折叠**：Turbo 加速 / LoRA 强度 / 种子 / Turbo 提示收进与「定时关机」同款折叠（Alpine x-collapse 展开，默认收起），分辨率与时长保持常显；折叠不影响取值，生成时照常读取
- APK versionCode 44

## v1.72（2026-09-26）

- **API 层适配器化**：ComfyUI 生成侧与 AutoDL 控制台侧各自引入适配器注册表（`registerComfyAdapter`/`registerDlAdapter` + `useComfyAdapter`/`useDlAdapter` 切换，默认实现即现有直连行为，接口与重试/信封解包逻辑不变）
  - ComfyUI 适配器接口：`url(path)` / `nb(path)`（防缓存）/ `wsUrl()`；`api()/nb()/openWs` 全部走适配器
  - AutoDL 适配器接口：`base` / `headers()` / `request(method, path, body, params)`；`dlCall/dlGet/dlPut/dlHeaders` 及租用下单收敛为适配器委托
- 行为无任何变化；为将来接入其他生成后端 / 算力平台留出插槽
- APK versionCode 43

## v1.71（2026-09-26）

- **历史记录改版**：已生成视频列表改为真正的列表项（边框卡片行：时间 · 时长 · 提示词标签 | 播放/下载/删除 右对齐），新记录保存提示词标签
- **历史按实例分桶**：`h3_history` 改为 `{实例uuid: [记录]}` 结构（旧平铺数据自动迁移到「未选实例」桶），在实例页选中实例后创作页视频列表自动切换；实例开关机状态变化也会即时刷新列表
- **实例未开机时不提供播放/下载入口**：视频文件在实例的 ComfyUI 上，关机状态不可达——列表项只保留删除
- 创作页底部预留 12px 尾部内边距，最后一条记录不再贴着悬浮导航（此前滑到底部时被导航栏挡住点不到）
- APK versionCode 42

## v1.70（2026-09-26）

- **整理不规整留白**：移除三页各自 `padding-bottom:70px` 的尾部留白——body 已为悬浮导航预留 78px，两者叠加导致每页底部多出约 70px 空白（实例/设置等短页尤为明显）；现在内容统一收在导航上方 78px 处
- 实例页「连接」label 的 16px 上边距（残留的内联 `--gapPanel`）改为与其他 label 一致的 12px
- APK versionCode 41

## v1.69（2026-09-26）

- **修复触屏按钮焦点残留**：全部 `:hover` 悬停规则（按钮实色背景、ghost/imgBtn 描边、历史链接等 15 处）包进 `@media (hover:hover) and (pointer:fine)`——触屏长按/划走不再残留悬停态，视觉反馈只在按下瞬间（`:active`）与功能确认后出现
- 长按按钮/链接/可复制文本时拦截 `contextmenu`：Android WebView 长按弹出的上下文菜单会吞掉后续 click（表现为「焦点上去了但提示词没填充」）并造成按压态抽搐；同时为按钮加 `-webkit-touch-callout:none`
- 明确语义：点按抬起 → click 触发 → 功能执行；长按划走 → 不触发、不留痕
- APK versionCode 40

## v1.68（2026-09-26）

- 滑动翻页**页间间距**：track 加 `gap:var(--gapPanel)`（16px），左右滑动时相邻两页的框与框之间露出背景间隙，落定后页面仍精确对齐视口；位移步长同步改为「页宽 + 间距」
- APK versionCode 39

## v1.67（2026-09-26）

- 底部导航**同级页面滑动切换**（Interactive Swipe / Progress-driven）：三页改为 viewport > track 横排结构，横拖实时跟手（`translate3d` + Pointer Events），松手按位移 >30% 屏宽或甩动速度（>0.4 px/ms 且移动 >4%）翻页，否则回弹（250ms 缓动）
- 竖向手势让位原生滚动（`touch-action:pan-y` + 轴向判定 8px 阈值），在创作/设置页边缘拖动有 0.25 阻尼回弹；输入框/按钮/下拉等交互元素上不劫持手势
- 底部导航高亮药丸与图标缩放/文字透明度随连续进度 `pageProgress` 插值，落定后与页签同步；页签点击与滑动走同一 pager，页面不销毁重建（创作参数、实例滚动位置、设置状态均保留）
- APK versionCode 38

## v1.66（2026-09-26）

- 修复底部导航页签点按后残留**实色电光青背景**：触屏 tap 会触发并保留 hover 态，`button:hover` 的实色背景特异性压过 `.tabBtn` 的透明背景，观感割裂——新增 `.tabBtn:hover/:focus` 强制透明背景并去除 focus 描边（选中态仍由滑动高亮药丸表达）
- APK versionCode 37

## v1.65（2026-09-26）

- 实例页**滚动自适应锁定**：内容不足一屏时锁定滚动，超出才允许滑动——消除部分手机上「刚好多出一小段可滑但实际没有内容可看」的无效滚动；判定时扣除为悬浮导航预留的底部留白，仅留白导致的溢出同样视为不满一屏
- 内容高度变化（实例列表刷新、折叠展开、改名编辑）经 ResizeObserver 自动重新判定，窗口 resize 同步
- APK versionCode 36

## v1.64（2026-09-26）

- 修复实例卡「定时关机」：`shutdown_at` 统一为 `YYYY-MM-DD HH:mm` 字符串（与创作页一致；此前传毫秒时间戳会被服务端拒绝）
- 修复租用弹窗 GPU change 监听器的悬空引用 `rentLoadMachines()`（正确函数 `loadRentMachines`）
- APK versionCode 35

## v1.63（2026-09-25）

- 间距令牌化：`--gapPanel/--gapCol/--gapGrid/--gapInline` 统一定义在 :root（与色卡并排），面板间距、双列间距、网格与行内间距全部改用令牌
- 实例页「连接」与「实例管理」两个面板**合并为一个统一面板**，消除框与框之间的间隙
- 创作页双列改为等高拉伸，矮列下方不再出现不均匀空隙
- APK versionCode 34

## v1.62（2026-09-25）

- 修复胶囊导航栏不透明：body 底部留白移除，页面延伸到屏幕底边，滚动内容从玻璃胶囊**后方**经过，毛玻璃实时模糊透出（真正的液态玻璃效果）；内容自身仍保留 70px 底部内边距避免被遮挡
- APK versionCode 33

## v1.61（2026-09-25）

- 修复 v1.60 遗留问题：body 壳布局规则未生效（height/display/overflow 丢失），页面无法上下滚动——已补上，各页面滚动容器恢复正常
- APK versionCode 31

## v1.60（2026-09-25）

- 页面切换改为 **App 壳布局**：body 固定视口高度（100dvh）纵向 flex，三页改为**独立滚动容器**（`overflow-y:auto` + `overscroll-behavior:contain`），横向滑动不再牵动窗口滚动——彻底解决「先回顶再切换」和侧边原生滚动条灰条
- 每个页面保持自己的滚动位置（切换后原样保留）；页面滚动条隐藏，保留触摸滚动
- 页面底部预留浮动胶囊导航栏的空隙
- APK versionCode 30

## v1.59（2026-09-25）

- 页面切换不再强制回到顶部：**记住每个页面的滚动位置**，切走时保存、切回时恢复
- 修复设置页版本号重复显示
- APK versionCode 28

## v1.58（2026-09-25）

- **修复首次加载页面堆叠**：滑动系统的初始化调用 `go("create")` 此前未加入启动序列，导致加载后三个页面无 transform 全部堆叠在原点（点一次页签才恢复）；已在初始化末尾补上
- APK versionCode 27

## v1.57（2026-09-25）

- 页面切换改为**横向滑动**：三个页面（创作/实例/设置）横向排列在滑动容器中，切页时整页平滑滑动过渡
- 底部导航栏高亮药丸**滑动跟随**：点按页签时青色药丸平滑滑动到目标位置
- 滑动容器高度随活动页面内容自动同步（ResizeObserver），不会出现空白拖尾
- 无需引入外部框架，纯 CSS transform + ResizeObserver 实现
- APK versionCode 26

## v1.56（2026-09-25）

- 底部导航栏重设计为**长胶囊液态玻璃**风格：悬浮圆角胶囊、毛玻璃背景（blur + saturate）、高光描边、暗/亮主题各自配色
- 选中页签改为胶囊内高亮药丸（电光青底 + 描边 + 发光图标），按压有缩放反馈
- 页面底部留白与 toast 位置适配悬浮胶囊；避开安全区
- APK versionCode 25

## v1.55（2026-09-25）

- **修复改名失败**：官方接口字段为 `instance_name`（不是 `name`），请求体已纠正
- **改名改为文件夹式原地编辑**：点击实例名原地变为输入框（自动聚焦全选），Enter 或失焦提交，Esc 取消；移除独立输入行与保存/取消按钮
- APK versionCode 24

## v1.54（2026-09-25）

- **视频窗口内播放**：历史记录的跳转链接改为「▶ 播放」，点击在结果窗口内直接播放（`playsinline`），不再跳转到新页面；新生成的视频默认窗口内自动播放
- 实例卡片**移除「改名」按钮**：点击实例名（✎）即可修改，按钮一行放得下不再挤压
- **完成后关机修复**：开关状态持久保存（执行后不再自动关闭）；任务完成且队列清空后即使连接状态未同步也会执行关机；增加 toast 提示
- 键盘弹起时底部导航栏不再上浮（`windowSoftInputMode` 改为 `adjustPan`）
- APK versionCode 23

## v1.53（2026-09-25）

- 修复手机上下的黑边：MainActivity 启用全面屏（内容延伸至状态栏/导航栏/刘海区域），系统栏透明，刘海模式 SHORT_EDGES
- 新增 `H3App.setLightSystemBars()` 桥：状态栏图标颜色跟随明暗主题联动
- 页面 body 顶部增加 `env(safe-area-inset-top)` 安全区内边距
- APK versionCode 22

## v1.52（2026-09-25）

- 所有轮询间隔统一改为 **4 秒**：实例状态/列表（原 8s）、ComfyUI 状态（原 5s）、开机就绪等待探测（原 5s）
- APK versionCode 21

## v1.51（2026-09-25）

- 实例管理页移除「刷新」按钮与空白提示区，改为**自动轮询**（8 秒一次，与实例状态轮询共用请求）；编辑实例名称时暂停重渲染防误触
- 操作反馈（开关机/释放/改名等）改为底部浮动 toast 提示
- APK versionCode 20

## v1.50（2026-09-25）

- 「连接」面板（实例选择/租用/获取列表/电源控制/定时关机/API 地址）从创作页整体移至**实例**页，与实例管理列表合并；创作页专注生成相关功能
- APK versionCode 19

## v1.49（2026-09-25）

- 实例卡片的 SSH 命令与 root 密码改为**掩码显示**（`ssh ***` / `密码 ***`），点击即复制真实值，无需额外复制按钮
- 新增原生桥 `H3App.copyText()`（Android ClipboardManager）；浏览器环境降级 `execCommand` 复制；复制成功原地闪烁「已复制 ✓」
- APK versionCode 18

## v1.48（2026-09-25）

- 实例管理支持**无卡模式**：关机的按量计费实例新增「无卡开机」按钮（`power_on` + `payload:"non_gpu"`，与官方一致），确认框注明 ¥0.10/时（最低消费 ¥0.01）、无 GPU 不能跑 H3
- 无卡模式运行的实例卡片**右上角显示「无卡模式」角标**，单价显示 ¥0.10/时（依据 `start_mode:"non_gpu"`）
- APK versionCode 17

## v1.47（2026-09-25）

- **租用改为直接下单**（弃用调度排队模式）：选地区 → GPU 型号 → **机器**（`user/machine/list` 搜索当前有空闲的具体机器，显示空闲数/单价）→ 镜像 → 数量 → `machine/check_machine_online` → `order/instance/create/payg` 立即下单
- 请求体与官方网页下单抓包逐字段一致；`MachineGpuNumUpdateFailed`（库存变更）给出刷新重选提示
- 移除调度相关：CUDA 版本选择、单价上限、passcode 签名（SHA1/MD5）、实例页排队订单区块
- 实例页不再显示排队订单；下单成功后实例直接出现在列表中
- APK versionCode 16

## v1.46（2026-09-25）

- 修复 v1.45 引入的「获取列表失败」：误将算力市场机器列表（`user/machine/list`）的查询参数体套到了实例列表接口（`api/v1/instance` 只接受空 body `{}`）上，已回退
- APK versionCode 15

## v1.45（2026-09-25）

- 底部导航新增第三个页签「**实例**」：照搬官方控制台的实例管理功能
  - **调度排队订单**：展示 `schedule/wait/list` 排队中的预约创建订单（此前 App 租用成功后看不到订单即因订单在此队列），支持一键取消调度
  - **实例卡片**：地区/宿主机、规格（GPU × 卡数）、单价、状态、镜像、SSH 命令与 root 密码
  - **操作**：开机 / 关机 / 重启 / 定时关机（含取消）/ 改名（PUT `instance/name`）/ 释放（双重危险确认，POST `instance/release`）
- 实例列表查询改用官方 `findAll` 完整参数体
- 排查结论：此前「租用后未生成订单」实为订单进入调度排队（wait list），服务端已正常受理
- APK versionCode 14

## v1.44（2026-09-25）

- **修复「请求参数错误」**：官方创建页的 `cuda_v`（CUDA 版本支持，大于等于）为**必填**字段，之前传 undefined 被服务端拒绝。新增 CUDA 版本选择栏（官方编码表 13.0→130 … 11.1→111），按所选镜像的 CUDA 版本自动选中最低兼容档，可手动改选；passcode 签名串随之包含真实值
- 租用失败时显示请求 ID / 签名参数串 / passcode 便于排查（v1.43 引入，合并记于此）
- APK versionCode 13

## v1.42（2026-09-25）

- 修复：首次打开租用弹窗时出现两个镜像选择框——TomSelect wrapper 不继承原 select 的内联 `display:none`，`openRent` 打开时按当前镜像类型强制同步可见性
- APK versionCode 11

## v1.41（2026-09-25）

- 修复：基础镜像/社区镜像切换后两栏同时可见——TomSelect 的外壳不受原 select 的 display 控制，改用 `rentShowSel` 切换 wrapper 可见性
- 下拉列表不再显示「— 请选择 —」占位行：占位文案改走 TomSelect 原生 placeholder（`rentFill` 动态更新 settings.placeholder）
- APK versionCode 10

## v1.40（2026-09-25）

- 租用弹窗五个选择栏（地区/GPU/基础镜像/社区镜像/GPU 数量）接入页面内置的 Tom Select 框架：统一皮肤、支持输入过滤搜索（镜像与卡型列表长时好选）、下拉平滑展开
- 选项填充/禁用/取值全部走 TomSelect API（`rentFill`/`rentGetVal`），无实例时自动降级原生 select
- APK versionCode 9

## v1.39（2026-09-25）

- 租用弹窗 GPU 型号显示空闲数量：下拉项追加「（空闲 x/y）」，选中后型号下方显示「当前空闲 x / 共 y 台」（`machine/region/gpu_type` 的 `idle_gpu_num`/`total_gpu_num`，与官方创建页同源）
- 空闲为 0 时禁用「确认租用」按钮（补禁用态样式）并提示无卡；重新选择型号自动恢复
- APK versionCode 8

## v1.38（2026-09-25）

- 修复社区镜像「未找到」：真机抓包确认接口中 `version` 为**字符串**（`"18"` 而非 `18`），严格匹配改为字符串比较；确认项目 uuid 为三段式 `comfyanonymous/ComfyUI/ComfyUI_2024`，提交 `reproduction_uuid` 与官方页面完全一致
- 确认搜索 `comfyanonymous/ComfyUI` 会返回多个条目（tzwm_ComfyUI #468 含 v20/21/22、ComfyUI_2024 #799），image_id=799 + v18 严格过滤后仅剩目标一项
- APK versionCode 7

## v1.37（2026-09-25）

- 社区镜像严格锁定为用户指定版本：只匹配 `image_id=799` 且 `version=18` 的条目（对应链接 `autodl.art/i/comfyanonymous/ComfyUI/ComfyUI_2024/799/18`），同项目其他镜像/版本全部过滤；找不到时明确报错，不再回退最新版
- APK versionCode 6

## v1.36（2026-09-25）

- 租用弹窗镜像区改为「基础镜像 / 社区镜像」双页签
- 社区镜像走 CodeWithGPU 端点：`api/v1/image/codewithgpu/list` 拉取 ComfyUI（comfyanonymous/ComfyUI）版本列表（vN 降序、CUDA/体积展示），默认选中 v18；`api/v1/image/codewithgpu` 查询磁盘占用提示
- 提交参数与官方创建页一致：`reproduction_uuid = "项目:v版本"`、`reproduction_id = image_id`，`base_image_info` 留空，`cuda_v` 不传
- APK versionCode 5

## v1.35（2026-09-25）

- 设置页登录组件升级为账号卡片：登录后展示 AutoDL 用户名、可用余额与代金券（GET `api/v1/user/detail`、`api/v1/wallet`，余额按 assets/1000 元换算），新增充值跳转与退出登录
- 创作页新增「租用」入口：App 内直接租用新实例（AutoDL 控制台同款内部端点，预约创建通道）
  - 地区列表 GET `api/v1/region/list`（公开）→ GPU 型号 POST `api/v1/machine/region/gpu_type` → 基础镜像 POST `api/v1/image/all` → 价格预估 POST `api/v1/instance/schedule/order/price/preview` → 创建 POST `api/v1/instance/schedule/create`
  - 创建请求按官网前端 `encrypt.js` 重放 passcode 签名：`MD5_hex(SHA1_hex(排序参数串))`，SHA1/MD5 内嵌纯 JS 实现（Node crypto 对拍通过）
  - 单价上限默认按预估价自动填写，可手动改写；余额不足（InsufficientBalance）给出充值提示
  - 注意：新实例不含 H3/ComfyUI 环境，需按 README 部署后使用
- APK versionCode 4

## v1.34（2026-09-25）

- 外链打开策略：原生 App（App Links / Deep Links）→ Chrome Custom Tabs → 系统浏览器，逐级回退（`androidx.browser`，manifest 增加 `<queries>` 包可见性声明）
- 设置页新增爱发电赞助链接；`openGitHub` 泛化为 `openExternal`
- APK versionCode 3，`gradle.properties` 启用 AndroidX

## v1.33（2026-09-25）

- 底部导航双页签（创作 / 设置），设置页集中登录、语言、主题、GitHub 仓库与版本号
- APK 新增原生桥 `H3App.openUrl()`（WebView 中 `target="_blank"` 无效的解法）

## v1.32（2026-09-25）

- 修复：v1.31 重构遗留的 `gpuSubText()` 悬空调用导致监测面板全空（每次轮询 ReferenceError 被静默吞掉）
- 显存百分比取整显示

## v1.31（2026-09-25）

- GPU 温度独立卡片（按 100°C 刻度的进度条）

## v1.30（2026-09-25）

- 显存占用独立卡片；`/h3ui/stats` 新增 `temp` 字段（pynvml，nvidia-smi 降级）

## v1.29（2026-09-25）

- 监测面板自适应栅格（auto-fit）；标题/数值溢出省略，GPU 名字悬停可见全名

## v1.28（2026-09-25）

- 性能监测面板（CPU / GPU / 内存 / 排队），实例端新增 `GET /h3ui/stats`（/proc/stat 差分采样 CPU + pynvml GPU）
- 连接面板移除队列显示（移入监测面板）；`boot/autodl_boot.sh` 开机自动刷新 `h3ui_api.py`

## v1.19（2026-09-25）

- 恢复追踪提速与韧性：每轮轮询查 `/queue` 刷新进度提示；失败重试阈值提高；关机期间不再计入失败

## v1.17 – v1.27（2026-09-25）

- 控件高度统一（`--ctlH`）；实例名超长截断；点按高亮与长按选中关闭；Tom Select 下拉开合动画（纯 opacity）
- 提示词与参数合并为「创作」面板；电源按钮常驻 + 完成后关机开关；Alpine.js 折叠项

## v1.12 – v1.16（2026-09-25）

- 界面整体升级（环境光晕、面板圆角阴影、按钮按压反馈、自定义滑块等）；Tom Select / Alpine.js 框架内联；主题切换 + 中英 i18n

## v1.1 – v1.11（2026-09-24 ~ 09-25）

- i2v / 首尾帧工作流；完成后关机 + 自动下载；竖屏分辨率；实例选择与计费；自动开机链路修复
