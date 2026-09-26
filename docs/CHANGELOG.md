# 更新日志

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
