# H3 Console

单文件网页控制台，用于在租用 GPU（如 AutoDL 4090）上通过 ComfyUI 本地运行开源 MiniMax H3 模型生成带音频的短视频，并提供实例电源与计费管理。附带自包含 Android WebView APK。

仓库内不含任何实例凭证——SSH 连接信息通过 `.env` 提供（见下），AutoDL 网页 token 只存放在浏览器/APK 的 localStorage。

## 功能

**视频生成**
- 直连 ComfyUI API（WebSocket 进度 + 实时预览），分辨率/时长/种子/LoRA 强度可调，内置官方 t2v 工作流
- 生成中再次提交自动进入原生 ComfyUI 队列，队列展示进度、支持中断/移除（页面内确认框，兼容 Android WebView）
- 历史记录持久化（localStorage），刷新自动恢复追踪，结果内嵌播放

**实例管理（AutoDL 标准区）**
- 登录获取 token，自动列出实例并轮询状态
- 开机 / 关机 / 定时关机（App 内登录，无需手动抓 token）
- 选中实例后自动从 `service_6006_domain` 提取 ComfyUI 转发地址并连接
- 本地计费：按实例列表返回的 `payg_price` 与 `status_at` 实时折算本次开机费用
- 弱网容错：API 调用 30s 超时 + 自动重试

**辅助工具**
- `h3ui_api.py`：部署到 ComfyUI `custom_nodes/` 的小型端点，`POST /h3ui/delete` 删除 `output/` 下文件（带路径穿越防护），供控制台删除云端视频
- `autodl_ssh.py`：SSH 命令行工具（凭证读自环境变量或 `.env`）
- `h3_progress.py`：模型下载进度监控面板

## 使用

1. 实例侧：ComfyUI 启动需带 `--enable-cors-header`（浏览器跨域必需）；可选部署 `h3ui_api.py` 以支持删除云端文件
2. 网页侧：浏览器直接打开 `h3_console.html`（或安装 APK），登录 AutoDL → 选择实例 → 开机后自动连接
3. 生成：输入提示词 → 生成视频；生成中再点即加入队列

### APK 构建

```bash
cd apk/H3Console
JAVA_HOME=<JDK路径> gradle assembleDebug --offline
# 产物: app/build/outputs/apk/debug/app-debug.apk
```

### SSH 工具配置

复制 `.env` 并填入实例的 SSH 信息：

```
AUTODL_SSH_HOST=connect.xxx.seetacloud.com
AUTODL_SSH_PORT=22
AUTODL_SSH_USER=root
AUTODL_SSH_PASSWORD=...
```

## 许可

[GPL-3.0](LICENSE)
