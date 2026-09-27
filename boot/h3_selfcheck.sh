#!/bin/bash
# ============================================================================
# H3 Console · 实例侧组件自检 / 自更新
# ----------------------------------------------------------------------------
# 目的：开机时自动确认实例上的组件是否与仓库最新版一致，不一致就更新；
#       不依赖单一外网源（AutoDL 容器普遍访问不了 raw.githubusercontent.com）。
# 源顺序：上次成功的源 → gh-proxy.com → ghproxy.net → [开学术加速] raw → jsDelivr
# 判定：与远端文件 **sha256 比对**（不是只判文件是否存在——旧版文件曾因此
#       被当成"已就绪"而永不更新，导致 /h3ui/v1/* 路由缺失、生成报 Failed to fetch）
# 组件：h3ui_api.py（ComfyUI 插件，含 /h3ui/v1/* 路由）
#       start_h3.sh（启动脚本，含无卡 --cpu 自动探测）
#       h3_models_download.sh（模型下载）
# 副作用：h3ui_api.py 有更新且 ComfyUI 正在运行 → 自动重启以加载新插件
# 用法：h3_selfcheck.sh [--no-restart] [--quiet]
# 日志：/root/autodl-tmp/h3_selfcheck.log
# 幂等：可重复执行；并发时 flock 跳过；/etc/autodl.sh 缺挂载会自动补回
# ============================================================================
set -u

SELF_VER="1.2"
REPO="NukumizuKazuhiko/h3-console"
BRANCH="main"
BASE="/root/autodl-tmp"
COMFY="$BASE/ComfyUI"
LOG="$BASE/h3_selfcheck.log"
SELFTEST="$BASE/h3_selfcheck.sh"
SRC_OK="$BASE/.h3_src_ok"
PORT=6006

NO_RESTART=0
QUIET=0
for a in "$@"; do
  case "$a" in
    --no-restart) NO_RESTART=1 ;;
    --quiet)      QUIET=1 ;;
  esac
done

ts(){ date '+%F %T'; }
log(){ echo "[$(ts)] $*" >> "$LOG"; [ "$QUIET" = "0" ] && echo "[$(ts)] $*"; }

# ---- 并发保护：开机脚本与手动执行不要撞车 ----------------------------------
if command -v flock >/dev/null 2>&1; then
  exec 9>/tmp/h3_selfcheck.lock
  flock -n 9 2>/dev/null || { log "另一次自检正在进行，跳过"; exit 0; }
fi

# ---- 源候选：前缀 + /相对路径（与 raw 的目录结构一致）----------------------
# 实测（2026-09-28，bjb1 容器内）：
#   ghproxy.net   实时，0.9s  ................. 首选
#   raw（需学术加速 /etc/network_turbo）实时，7s
#   gh-proxy.com  同一 URL 命中 CDN 缓存，会返回旧版（曾导致自检恒报「已是最新」）
#   jsDelivr      对分支有小时级缓存
#   ※ 不可靠技巧：给这类代理 URL 加 ?t= 会破坏其原始 URL 解析（返回空内容）；
#     Cache-Control: no-cache 头无效。只能靠「实时源在前」+ 缓存源兜底并标注。
SRC_FAST=(
  "https://ghproxy.net/https://raw.githubusercontent.com/$REPO/$BRANCH"
  "https://gh-proxy.com/https://raw.githubusercontent.com/$REPO/$BRANCH"
)
SRC_TURBO=(
  "https://raw.githubusercontent.com/$REPO/$BRANCH"
  "https://cdn.jsdelivr.net/gh/$REPO@$BRANCH"
)
# 已知带 CDN 缓存、可能滞后的源
is_cached_src(){ case "$1" in *"gh-proxy.com"*|*"jsdelivr.net"*) return 0 ;; *) return 1 ;; esac; }

probe(){ curl -fsS -m 12 -o /dev/null "$1/h3ui_api.py" 2>/dev/null; }

try_sources(){
  local u last=""
  [ -f "$SRC_OK" ] && last=$(cat "$SRC_OK" 2>/dev/null || true)
  if [ -n "$last" ] && ! is_cached_src "$last" && probe "$last"; then echo "$last"; return 0; fi
  for u in "${SRC_FAST[@]}"; do probe "$u" && { echo "$u"; return 0; }; done
  source /etc/network_turbo >/dev/null 2>&1
  for u in "${SRC_TURBO[@]}"; do probe "$u" && { echo "$u"; return 0; }; done
  return 1
}

# ---- 自我更新：脚本自身也会演进，远端有新版则替换后重新执行 ----------------
# 避免重蹈「组件部署了却永不更新」的覆辙；此处尚在脚本前段、未读到后续内容，替换安全。
ALLOW_SELF_UPDATE=1
for a in "$@"; do [ "$a" = "--no-selfupdate" ] && ALLOW_SELF_UPDATE=0; done
if [ "$ALLOW_SELF_UPDATE" = "1" ]; then
  U=""
  [ -f "$SRC_OK" ] && U=$(cat "$SRC_OK" 2>/dev/null || true)
  [ -n "$U" ] && is_cached_src "$U" && U=""      # 缓存源不可信，改走实时源重新探测
  [ -n "$U" ] || U=$(try_sources || true)
  if [ -n "$U" ]; then
    N="$BASE/.h3_self.new"
    if curl -fsSL -m 25 -o "$N" "$U/boot/h3_selfcheck.sh" 2>/dev/null && [ -s "$N" ] && ! cmp -s "$N" "$SELFTEST"; then
      sed -i 's/\r$//' "$N"
      cp -f "$N" "$SELFTEST"
      chmod +x "$SELFTEST"
      rm -f "$N"
      echo "[$(ts)] SELFUPD 自检脚本已更新到远端版本，重新执行" >> "$LOG"
      exec bash "$SELFTEST" --no-selfupdate "$@"
    fi
    rm -f "$N"
  fi
fi

PREFIX=$(try_sources) || {
  log "所有更新源均不可达，本次跳过（保留现有组件）"
  exit 0
}
if is_cached_src "$PREFIX"; then
  rm -f "$SRC_OK"   # 不记住缓存源，下次开机重新探测实时源
  log "更新源：$PREFIX（该源带 CDN 缓存，可能滞后；实时源均不可达时的兜底）"
else
  echo "$PREFIX" > "$SRC_OK"
  log "更新源：$PREFIX"
fi

# ---- 组件清单：名称|目标路径|仓库相对路径 ----------------------------------
COMPONENTS=(
  "h3ui_api.py|$COMFY/custom_nodes/h3ui_api.py|h3ui_api.py"
  "start_h3.sh|$COMFY/start_h3.sh|boot/start_h3.sh"
  "h3_models_download.sh|$BASE/h3_models_download.sh|boot/h3_models_download.sh"
)

api_changed=0
any_changed=0

for row in "${COMPONENTS[@]}"; do
  IFS='|' read -r name target rel <<< "$row"
  tmp="$BASE/.h3_dl.$name"
  if ! curl -fsSL -m 30 -o "$tmp" "$PREFIX/$rel" 2>/dev/null || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    if [ -f "$target" ]; then log "SKIP  $name 下载失败，保留现有版本"
    else log "FAIL  $name 下载失败且本地缺失"; fi
    continue
  fi
  new=$(sha256sum "$tmp" | cut -d' ' -f1)
  old=""
  [ -f "$target" ] && old=$(sha256sum "$target" | cut -d' ' -f1)
  if [ "$new" = "$old" ]; then
    log "OK    $name 已是最新 (${new:0:12})"
  else
    mkdir -p "$(dirname "$target")"
    cp -f "$tmp" "$target"
    case "$name" in
      start_h3.sh|h3_models_download.sh) chmod +x "$target" ;;
    esac
    log "UPD   $name ${old:0:12} -> ${new:0:12}"
    [ "$name" = "h3ui_api.py" ] && api_changed=1
    any_changed=1
  fi
  rm -f "$tmp"
done

# ---- 系统盘副本站点同步（社区镜像可能从系统盘加载插件）--------------------
if [ -d /root/ComfyUI/custom_nodes ] && [ -f "$COMFY/custom_nodes/h3ui_api.py" ]; then
  if ! cmp -s "$COMFY/custom_nodes/h3ui_api.py" /root/ComfyUI/custom_nodes/h3ui_api.py; then
    cp -f "$COMFY/custom_nodes/h3ui_api.py" /root/ComfyUI/custom_nodes/h3ui_api.py && log "SYNC  系统盘副本已同步"
  fi
fi

# ---- h3ui_api.py 变更后需重启 ComfyUI 才生效 -------------------------------
if [ "$api_changed" = "1" ]; then
  if curl -sf -m 5 "http://127.0.0.1:$PORT/system_stats" >/dev/null 2>&1; then
    if [ "$NO_RESTART" = "1" ]; then
      log "NOTE  h3ui_api.py 已更新，按 --no-restart 未重启（新端点尚未生效）"
    else
      log "RESTART h3ui_api.py 有更新，重启 ComfyUI 以加载新插件"
      pkill -f '[m]ain.py --port=' >/dev/null 2>&1
      for i in $(seq 1 20); do
        pgrep -f '[m]ain.py --port=' >/dev/null 2>&1 || break
        sleep 1
      done
      pkill -9 -f '[m]ain.py --port=' >/dev/null 2>&1
      sleep 2
      setsid bash "$COMFY/start_h3.sh" >> "$BASE/comfyui_h3.log" 2>&1 < /dev/null &
      sleep 3
      log "RESTART 已重新拉起：$(pgrep -fc '[m]ain.py --port=' 2>/dev/null || echo 0) 个进程"
    fi
  else
    log "NOTE  h3ui_api.py 已更新，ComfyUI 未运行（开机场景），启动时自然加载新版"
  fi
fi

# ---- 自愈：确保 /etc/autodl.sh 里有本次自检的挂载（防被镜像更新覆盖）-------
if ! grep -q 'h3_selfcheck.sh' /etc/autodl.sh 2>/dev/null; then
  {
    echo ""
    echo "# H3 Console: 开机组件自检 + ComfyUI autostart"
    echo "( sleep 5"
    echo "  bash $SELFTEST >/dev/null 2>&1   # 日志由脚本自身写入 $LOG"
    echo "  sleep 8"
    echo "  curl -s -o /dev/null --max-time 3 http://127.0.0.1:$PORT/system_stats \\"
    echo "    || setsid bash $COMFY/start_h3.sh >> $BASE/comfyui_h3.log 2>&1 < /dev/null"
    echo ") &"
  } >> /etc/autodl.sh
  log "HOOK  /etc/autodl.sh 缺少自检挂载，已补回"
fi

log "DONE  v$SELF_VER changed=$any_changed api_changed=$api_changed"
exit 0
