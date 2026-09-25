# 更新日志

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
