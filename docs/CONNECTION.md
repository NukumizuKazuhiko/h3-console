# H3 Console 远端实例连接逻辑（审计 + v2.11 重构）

> 审计时间：2026-09-27　适用版本：v2.10 及以前 / 重构后 v2.11
> 目的：把「App ↔ AutoDL 实例 ↔ ComfyUI」这条链路上所有状态与写入者列清楚，消除重复与死角。

---

## 一、链路全景（v2.10 及以前）

链路分四层，每层各自维护状态，层间靠全局变量和 DOM 文本传递：

```
┌─ 第 4 层：UI 渲染 ────────────────────────────────────────┐
│  dotConn / connText / statusBox / pwrHint / gpuText …    │
└───────────────▲──────────────────────────▲───────────────┘
                │ 直接改 DOM（5 个写入者）  │
┌─ 第 3 层：ComfyUI 连接 ─────────┬─ 第 2 层：地址发现 ─────┐
│ connect()      一次性校验       │ autoSetApi() 三级链   │
│ pollStatus()   4s 循环          │  ①detail/实例卡字段   │
│ waitComfyReady 生成前 60×4s     │  ②seetacloud 扫描     │
│ comfyOnline 布尔                │  ③SSH 实例自报        │
│                                 │ apiBase + h3_api      │
└───────────────▲─────────────────┴──────────▲────────────┘
                │                            │
┌─ 第 1 层：实例状态（AutoDL 控制台 API）──────┴────────────┐
│ pollInstStatus()  1s 循环 → instListCache / instOn /      │
│                   instNonGpuNow / instPrice               │
│ loadInstances()   启动 + 登录 + 手动                      │
│ 触发 autoSetApi 的条件（唯一的自动刷新入口）              │
└───────────────────────────────────────────────────────────┘
```

### 1.1 地址层（apiBase）
| 项 | 位置 | 说明 |
|---|---|---|
| 持久化 | `localStorage["h3_api"]` | **单一全局值，不与实例 uuid 绑定** |
| 初始装载 | `1536` | `$("apiBase").value = localStorage.getItem("h3_api") || ""` |
| 写入者 ① | `autoSetApi()` 1760-1765 | 三级发现成功后写入 + `saveApi()` + `connect()` |
| 写入者 ② | `#apiBase` change 事件 1590 | 用户手填，`saveApi()` + `connect()` |
| 写入者 ③ | `autoSetApi()` 1768 | 三级链全失败时清空 `127.0.0.1` 残留 |
| 读者 | `comfy().url/nb/wsUrl` 1583-1585 | 拼 `/system_stats`、`/queue`、`/h3ui/*`、`/ws` |

### 1.2 实例状态层
`pollInstStatus()`（每 1s）→ 全局 `instListCache` / `instOn` / `instNonGpuNow` / `instPrice` / `instBootAt`；
其中**唯一会主动刷新地址**的地方是 2655 行：

```js
if(on && it.start_mode !== "non_gpu" && (lastInstOn === false || !$("apiBase").value.trim() || staleTunnel)) autoSetApi();
```

`loadInstances()` 2725 行也调一次 `autoSetApi()`（启动/登录/手动刷新时）。

### 1.3 ComfyUI 连接层
| 函数 | 触发 | 行为 |
|---|---|---|
| `connect()` | apiBase change、autoSetApi 成功、powerOnAndWait 末尾、启动 | 单次 `/system_stats` |
| `pollStatus()` | 启动 + 自循环（4s） | `/system_stats` + `/queue` + `/h3ui/stats` |
| `waitComfyReady()` | `powerOnAndWait()` 内 | 60 次 × 4s |

### 1.4 SSH 层
`sshExec()`（原生桥）用于：地址自报 `fwdFromSsh`、部署探测 `nbProbe`、部署执行、下载监测。
`sshTunnelApi()` / `sshTunnelReq()` / `sshTunnelCloseCur()`：**SSH 隧道，`SSH_TUNNEL_ON = false`，全为死代码**，
但仍被 `staleTunnel` 判断与两处 `sshTunnelCloseCur()` 调用引用。

---

## 二、发现的问题（按严重度）

### P0-1　公网转发地址过期后永不自愈 ★本次故障根因
- AutoDL 每次开机都会换转发域名/端口，`h3_api` 里存的是**上次会话的地址**。
- 启动瞬间 `connect()` + `pollStatus()` 直接打这个陈旧地址 → `Failed to fetch`。
- 之后 `pollInstStatus` 的判断里：`lastInstOn` 初值 `null`（不是 `false`）→ 首次不触发；
  实例一直 running → `lastInstOn` 永远为 `true` → **再也不会触发 `autoSetApi()`**；
  `staleTunnel` 因 `SSH_TUNNEL_ON=false` 退化成「apiBase 是否以 `http://127.0.0.1` 开头」，
  公网地址过期完全不满足。→ 结果：**永久停在「连接失败: Failed to fetch」**，与实例是否健康无关。

### P0-2　用 UI 文本当状态机
`3122` 行 `$("connText").textContent.startsWith(t("connected"))`、`3118` 行 `!== t("instOff")`——
把显示文案当作连接状态判断，**切换语言后条件全部失效**（i18n 一改就退化）。

### P1-1　连接文案有 5 个写入者
`connect()` 3020/3030/3034、`pollStatus()` 3082/3118/3126、`pollInstStatus()` 2661/2670。
彼此靠字符串比较互不覆盖，语义不清（`comfyOnline=false` 时而配 `statusBox` 显示、时而配隐藏）。

### P1-2　启动时序竞争
脚本末尾 `connect(); pollStatus(); pollInstStatus();` 同时起跑，而 `instNonGpuNow` / `instOn`
要等 1s 轮询才赋值。启动瞬间两个守卫都是默认值（`instOn=null`、`instNonGpuNow=false`），
于是必然先对旧地址空发一轮请求；且 `instOn === null` 时 `pollStatus` 的 catch 两个分支都不命中，
**失败文案不会被任何后续逻辑覆盖**。

### P1-3　无卡判定四处各写一遍
`autoSetApi()` 1745、`connect()` 3013、`pollStatus()` 3078 用全局 `instNonGpuNow`；
`pollInstStatus()` 2655 用局部 `it.start_mode`。条件不完全一致（有无 `status === "running"` 混合）。

### P1-4　地址与实例未绑定
`h3_api` 是全局单值。切实例时若新实例地址发现失败，旧实例地址仍被沿用，请求打到错误的实例上。

### P2-1　隧道死代码污染判断
`SSH_TUNNEL_ON=false` 后，`sshTunnelApi`/`sshTunnelReq`/`sshTunnelCloseCur`、`noForwardSsh`/`tunnelFail`
文案全部失去作用，却仍在 `staleTunnel` 和两处调用点出现，读者无法分辨哪条链路是活的。

### P2-2　`pwrHint` 多路复用
部署进度（`nbHint`）、地址发现（`fwdSearching`/`noForward`）、开关机提示共用同一行，互相覆盖
（v2.00 已加守卫，仍是隐患）。

---

## 三、v2.11 重构

### 3.1 新增：单一连接状态机
```js
// connState ∈ init | connecting | online | offline | instOff | nonGpu | noApi
setConnState(state, detail)   // 唯一允许改 dotConn/connText/statusBox 的函数
```
所有写入者改为调用 `setConnState()`；`comfyOnline` 由它统一维护；**不再有任何读取 UI 文本的判断**。

### 3.2 新增：地址失效即自动重新发现
```js
connFailStreak            // 连续连接失败次数，成功清零
apiDiscoveredAt           // 最近一次成功发现地址的时间
autoSetApi({force})       // force 绕过节流与实例态守卫
```
- `pollStatus()` 连续失败 ≥ 2 次（约 8s）→ `autoSetApi({force:true})`；
- `autoSetApi` 内部 15s 节流，避免轮询打爆三级链（SSH 探测最慢）；
- 触发条件补充「地址陈旧」通道，不再依赖 `lastInstOn` 的边沿。

### 3.3 新增：地址与实例绑定
`localStorage["h3_api_bind"] = {uuid, url, at}`；选择实例与绑定 uuid 不一致 → 视为陈旧，自动重发现。
手填地址时也写入绑定（并清除旧绑定）。

### 3.4 统一无卡判定
```js
function instIsNonGpu(){ const it = curInst(); return !!(it && it.status === "running" && it.start_mode === "non_gpu"); }
```
`connect` / `pollStatus` / `autoSetApi` / `pollInstStatus` 全部改用它。

### 3.5 启动顺序
启动不再盲发连接请求：先 `pollInstStatus()`，`pollStatus()` 在 `instOn === null`（实例态未知）时
仅等待不请求，等实例态确定后再决定「连接 / 显示实例未开机 / 显示无卡暂停」。

### 3.6 清理隧道死代码
删除 `SSH_TUNNEL_ON` / `sshTunnelReq` / `sshTunnelApi` / `sshTunnelCloseCur` / `sshTunnel*` 变量与
`staleTunnel` 判断，以及两处调用点；保留原生桥方法（未调用即无害）。
