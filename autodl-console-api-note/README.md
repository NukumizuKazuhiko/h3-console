# AutoDL 实例控制 API 笔记

整理时间：2026-09-25。来源：抓取 autodl.com 网页控制台前端 JS bundle 并阅读调用点。**不含任何凭证**，文中地址均为占位符。

## 背景

AutoDL 官方开发者 API 有两套，都对标准区实例（普通 4090 等按量实例）无能为力：

| 官方 API | 能力 | 局限 |
|---|---|---|
| 常规 API（api.autodl.com） | 仅查余额、存储挂载 | 无开关机 |
| 容器实例 Pro API（`/docs/instance_pro_api/`） | power_on / power_off 等 | **只管 Pro 区实例**，标准区实例不在列表 |

标准区实例想要 API 化开关机，唯一出路是重放网页控制台的内部接口。

## 网页控制台内部 API（标准区可用）

### 基址与响应格式

- 基址：`https://www.autodl.com/api/v1/`
- 响应统一包装：`{"code": "Success" | "AuthorizeFailed" | ..., "data": ..., "msg": "...", "request_id": "..."}`
- `code === "Success"` 即成功；无有效凭证时返回 `{"code":"AuthorizeFailed","msg":"登录超时，请重新登录..."}`（HTTP 仍为 200）

### 鉴权

请求头携带网页登录态 token（**等同全账号凭证，注意保管，会过期，几小时~几天不等**）：

```
Authorization: <token>
```

token 获取：在已登录 autodl.com 的浏览器里，F12 → Console 执行 `localStorage.getItem("token")`。
（控制台前端源码：`getToken = () => localStorage.getItem("token")`，axios 拦截器注入 `headers: {Authorization: token}`。）

### CORS

`https://www.autodl.com/api/v1/*` 返回 `Access-Control-Allow-Origin: *`（实测确认），本地 HTML / 任意网页可直连，无需代理。

### 端点表（全部 POST）

| 功能 | 路径 | Body |
|---|---|---|
| 实例列表 | `api/v1/instance` | `{}` |
| 开机 | `api/v1/instance/power_on` | `{"instance_uuid": "<uuid>"}` |
| 关机 | `api/v1/instance/power_off` | `{"instance_uuid": "<uuid>"}` |
| 重启 | `api/v1/instance/restart` | `{"instance_uuid": "<uuid>"}` |
| 定时关机 | `api/v1/instance/timed/shutdown` | `{"instance_uuid": "<uuid>", "shutdown_at": <毫秒时间戳或 null>}` |

其余从前端 bundle 可见的端点（未逐一验证）：`detail`、`snapshot`、`release`、`recreate`、`name`（改名）、`ssh_pwd`（重置 SSH 密码）等。

### 端点来源依据（前端 bundle 调用点）

```js
// instance.<hash>.js 中的 API 定义
start:  async (e, n) => (await a.post("api/v1/instance/power_on", e, {interceptors: n})).data
stop:   async (e, n) => (await a.post("api/v1/instance/power_off", e, {interceptors: n})).data
timedShutdown: async (e, n) => (await a.post("api/v1/instance/timed/shutdown", e, {interceptors: n})).data
findAll:       async (e, n) => (await a.post("api/v1/instance", e, {interceptors: n})).data

// 调用点
ne.start({instance_uuid: e.uuid}, !1)
ne.stop({instance_uuid: e.uuid}, !1)
timedShutdown({instance_uuid: e.uuid, shutdown_at: ...}, !1)

// 定时关机时间格式（毫秒时间戳；null 表示取消定时）
shutdown_at: new Date(d.value.time).getTime() + 60 * ((new Date).getTimezoneOffset() + 480) * 1e3
```

注：`getTimezoneOffset()` 在 UTC+8 环境返回 -480，故上式即本地选择的时刻的毫秒时间戳；直接传 `Date.now() + 分钟数*60000` 即可。

### 实例列表返回

`data.list[]`，元素含 `uuid`、`name`、`status` 等字段；`status` 取值如 `running`（运行中计费）、`shutdown`（已关机）、`powering_on`、`creating`。定时关机生效时另有 `timed_shutdown_at` 字段（Go `sql.NullTime` 结构，`.Time` / `.Valid`）。

### curl 示例

```bash
TOKEN="<localStorage.getItem('token') 的值>"
UUID="<实例 uuid>"

# 列表
curl -s -X POST https://www.autodl.com/api/v1/instance \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" -d '{}'

# 开机（立即按 GPU 单价计费）
curl -s -X POST https://www.autodl.com/api/v1/instance/power_on \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"instance_uuid\": \"$UUID\"}"

# 关机
curl -s -X POST https://www.autodl.com/api/v1/instance/power_off \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"instance_uuid\": \"$UUID\"}"

# 30 分钟后自动关机
curl -s -X POST https://www.autodl.com/api/v1/instance/timed/shutdown \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"instance_uuid\": \"$UUID\", \"shutdown_at\": $(($(date +%s%3N) + 1800000))}"

# 取消定时关机
curl -s -X POST https://www.autodl.com/api/v1/instance/timed/shutdown \
  -H "Authorization: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"instance_uuid\": \"$UUID\", \"shutdown_at\": null}"
```

## 其他相关结论

- 实例内可执行官方提供的 `/usr/bin/shutdown` 自关机（见官方文档 save_money 篇）——适合"队列空闲自动关机"的守护脚本方案。
- 无卡模式开机 ¥0.1/h，可低成本保住数据盘。
- Pro API 的 power_on 支持 `start_command`（开机自动执行命令）与 `payload: "gpu" | "no_gpu"`，但仅限 Pro 区实例。

## 风险与注意

1. token 是**完整账号会话凭证**，泄露等同交出账号；不要写进代码仓库、日志或聊天记录。
2. 内部接口无兼容性承诺，AutoDL 改版可能失效。
3. 重放调用与官方 API 一样会计费，power_on 前确认计费单价。
