#!/bin/bash
# ============================================================================
# H3 Console · 实例侧组件自检 / 自更新                      v2.2
# ----------------------------------------------------------------------------
# 目的：开机时自动确认实例上的组件是否与仓库最新版一致，不一致就更新。
# 组件：h3ui_api.py            → ComfyUI 插件（含 /h3ui/v1/* 路由）
#       start_h3.sh            → 启动脚本（含无卡 --cpu 自动探测）
#       h3_models_download.sh  → 模型下载脚本
# 判定：与远端文件 **sha256 比对**，而不是只判「文件是否存在」——
#       旧版文件曾因只判存在而被当成"已就绪"、永不更新，导致 /h3ui/v1/* 路由
#       缺失，App 生成视频拿到 405（且无 CORS 头）被浏览器报成 Failed to fetch。
#
# ── 更新源策略（2026-09-28 在 bjb1 容器内实测后定为 v2.2）───────────────────
#   · 只用【官方 GitHub】，不经过任何第三方加速站。两条网络路径：
#       ① 直连   ② source /etc/network_turbo（学术加速）后重试
#     实测：api.github.com 直连 200/1.3s；raw.githubusercontent.com 直连
#     200/7.1s（有抖动，偶发 000 超时）；开学速后 raw 200/0.8~4.2s（3/3 成功）。
#     /etc/network_turbo 设 http(s)_proxy=http://172.32.52.144:12798，其
#     no_proxy 已含 localhost,127.0.0.1，故本机探测不受影响。
#   · 已弃用 ghfast.top / ghproxy.net / gh-proxy.com / jsDelivr：各自带独立 CDN
#     缓存，实测同一时刻同一文件分别返回 v1.2/v1.1/v1.0，会让"是否最新"的判断
#     失真（误判已最新 / 把新版降级覆盖——曾实际发生）。
#   · 注意：**官方 raw 自己也有分钟级 CDN 缓存**（实测 push 后 20 分钟仍返回
#     旧版）。所以不能拿 branch 名的内容当版本依据，改为：
#       ① 先问 GitHub API 取 main 的 commit sha（唯一、不可变、响应小）；
#       ② 用 commit sha pin 住文件 URL（/REPO/<sha>/path）——缓存键随 sha 变化，
#          天然绕开 branch 级缓存，取到的一定是该 commit 的内容。
#     若 API 不可用，则退回 branch URL，但此时**只补缺失文件、绝不覆盖已有文件**。
#   · 已实测排除的无效手段：给代理 URL 追加 ?t= 会破坏其原始 URL 解析（返回空）；
#     Cache-Control / Pragma: no-cache 头被忽略。
# ───────────────────────────────────────────────────────────────────────────
# 用法：h3_selfcheck.sh [--no-restart] [--no-selfupdate] [--quiet]
# 日志：/root/autodl-tmp/h3_selfcheck.log
# 幂等：可重复执行；并发时 flock 跳过；/etc/autodl.sh 缺挂载会自动补回；
#       自检脚本自身也自更新，且**只升不降**（ver_gt 版本比较）
# ============================================================================
set -u

SELF_VER="2.2"
REPO="NukumizuKazuhiko/h3-console"
BRANCH="main"
BASE="/root/autodl-tmp"
COMFY="$BASE/ComfyUI"
LOG="$BASE/h3_selfcheck.log"
SELFTEST="$BASE/h3_selfcheck.sh"
TMP="$BASE/.h3_dl.tmp"
PORT=6006
TURBO=/etc/network_turbo
GH_API="https://api.github.com/repos/$REPO/commits/$BRANCH"
RAW_ROOT="https://raw.githubusercontent.com/$REPO"

NO_RESTART=0
QUIET=0
ALLOW_SELF_UPDATE=1
for a in "$@"; do
  case "$a" in
    --no-restart)    NO_RESTART=1 ;;
    --quiet)         QUIET=1 ;;
    --no-selfupdate) ALLOW_SELF_UPDATE=0 ;;
  esac
done

ts(){ date '+%F %T'; }
log(){ echo "[$(ts)] $*" >> "$LOG"; [ "$QUIET" = "0" ] && echo "[$(ts)] $*"; }
# $1 > $2 ？（语义化版本比较）
ver_gt(){ [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]; }

# ---- 并发保护：开机脚本与手动执行不要撞车 ----------------------------------
if command -v flock >/dev/null 2>&1; then
  exec 9>/tmp/h3_selfcheck.lock
  flock -n 9 2>/dev/null || { log "另一次自检正在进行，跳过"; exit 0; }
fi

# ---- 网络路径：直连优先，不通再开学术加速 ----------------------------------
NET_MODE="none"
use_turbo(){
  [ -f "$TURBO" ] || return 1
  . "$TURBO" >/dev/null 2>&1 || return 1
  NET_MODE="turbo"
  return 0
}
reachable(){ curl -fsS -m 12 -o /dev/null "$1" 2>/dev/null; }

if reachable "https://api.github.com/rate_limit"; then
  NET_MODE="direct"
elif use_turbo && reachable "https://api.github.com/rate_limit"; then
  :
fi

# ---- 权威提交：commit sha（唯一标识，绕开 branch 级缓存）-------------------
gh_sha(){
  curl -fsSL -m 20 "$GH_API" 2>/dev/null \
    | grep -oE '"sha" *: *"[0-9a-f]{40}"' | head -1 | cut -d'"' -f4
}
COMMIT=""
[ "$NET_MODE" != "none" ] && COMMIT=$(gh_sha) || true
if [ -z "$COMMIT" ] && [ "$NET_MODE" = "direct" ] && use_turbo; then
  COMMIT=$(gh_sha)
fi
[ "${#COMMIT}" -eq 40 ] || COMMIT=""

if [ -n "$COMMIT" ]; then
  AUTH_SRC="$RAW_ROOT/$COMMIT"      # commit-pin，内容不可变、无 branch 缓存歧义
  AUTHORITATIVE=1
else
  AUTH_SRC="$RAW_ROOT/$BRANCH"      # 兜底：branch URL（可能带缓存）
  AUTHORITATIVE=0
fi

get_from(){ curl -fsSL -m 30 -o "$3" "$1/$2" 2>/dev/null && [ -s "$3" ]; }
# 取文件；直连失败时自动切学术加速重试一次（URL 不变，pin 语义不变）
fetch_file(){
  get_from "$1" "$2" "$3" && return 0
  if [ "$NET_MODE" = "direct" ] && use_turbo; then
    get_from "$1" "$2" "$3" && return 0
  fi
  return 1
}

TMPL="$BASE/.h3_self.new"
# ---- 自我更新（只升不降）--------------------------------------------------
if [ "$ALLOW_SELF_UPDATE" = "1" ] && [ "$AUTHORITATIVE" = "1" ]; then
  if fetch_file "$AUTH_SRC" boot/h3_selfcheck.sh "$TMPL" && [ -s "$TMPL" ]; then
    sed -i 's/\r$//' "$TMPL"
    nv=$(grep -m1 '^SELF_VER=' "$TMPL" | cut -d'"' -f2)
    if [ -n "$nv" ] && ver_gt "$nv" "$SELF_VER" && ! cmp -s "$TMPL" "$SELFTEST"; then
      cp -f "$TMPL" "$SELFTEST"
      chmod +x "$SELFTEST"
      rm -f "$TMPL"
      echo "[$(ts)] SELFUPD 自检脚本 $SELF_VER → $nv（commit ${COMMIT:0:12}），重新执行" >> "$LOG"
      exec bash "$SELFTEST" --no-selfupdate "$@"
    fi
  fi
  rm -f "$TMPL"
fi

if [ "$AUTHORITATIVE" = "1" ]; then
  log "源=官方 GitHub（网络=$NET_MODE）commit=${COMMIT:0:12} 已 pin，绕开 branch 级缓存"
else
  log "GitHub API 不可达（网络=$NET_MODE）→ 退回 branch URL：只补缺失、不覆盖已有文件"
fi

# ---- 组件清单：名称|目标路径|仓库相对路径 ----------------------------------
COMPONENTS=(
  "h3ui_api.py|$COMFY/custom_nodes/h3ui_api.py|h3ui_api.py"
  "start_h3.sh|$COMFY/start_h3.sh|boot/start_h3.sh"
  "h3_models_download.sh|$BASE/h3_models_download.sh|boot/h3_models_download.sh"
)
fixperm(){ case "$1" in *.sh) chmod +x "$1" ;; esac; }

api_changed=0
any_changed=0

if [ "$AUTHORITATIVE" = "1" ]; then
  # 权威路径：逐文件 sha256 比对，不一致即更新（pin 源就是真相，可升可降均安全）
  for row in "${COMPONENTS[@]}"; do
    IFS='|' read -r name target rel <<< "$row"
    if ! fetch_file "$AUTH_SRC" "$rel" "$TMP"; then
      log "FAIL  $name 下载失败（网络=$NET_MODE）"
      rm -f "$TMP"; continue
    fi
    new=$(sha256sum "$TMP" | cut -d' ' -f1)
    old=""
    [ -f "$target" ] && old=$(sha256sum "$target" | cut -d' ' -f1)
    if [ "$new" = "$old" ]; then
      log "OK    $name 已是最新 (${new:0:12})"
    else
      mkdir -p "$(dirname "$target")"
      cp -f "$TMP" "$target"
      fixperm "$target"
      log "UPD   $name ${old:0:12} -> ${new:0:12}"
      [ "$name" = "h3ui_api.py" ] && api_changed=1
      any_changed=1
    fi
    rm -f "$TMP"
  done
else
  # 兜底路径：只补缺失文件；已存在的文件不动（branch URL 可能返回旧版，覆盖会降级）
  for row in "${COMPONENTS[@]}"; do
    IFS='|' read -r name target rel <<< "$row"
    if [ -f "$target" ]; then
      log "SKIP  $name 已存在（无权威提交信息，不覆盖以防降级）"
      continue
    fi
    if fetch_file "$AUTH_SRC" "$rel" "$TMP"; then
      mkdir -p "$(dirname "$target")"
      cp -f "$TMP" "$target"
      fixperm "$target"
      log "FILL  $name 缺失已补齐（可能带缓存，下次权威源可用时校正）"
      any_changed=1
    else
      log "FAIL  $name 缺失且下载失败"
    fi
    rm -f "$TMP"
  done
fi

# ---- 系统盘副本站点同步（社区镜像可能从系统盘加载插件）--------------------
if [ -d /root/ComfyUI/custom_nodes ] && [ -f "$COMFY/custom_nodes/h3ui_api.py" ]; then
  if ! cmp -s "$COMFY/custom_nodes/h3ui_api.py" /root/ComfyUI/custom_nodes/h3ui_api.py; then
    cp -f "$COMFY/custom_nodes/h3ui_api.py" /root/ComfyUI/custom_nodes/h3ui_api.py \
      && log "SYNC  系统盘副本已同步"
  fi
fi

# ---- h3ui_api.py 变更后需重启 ComfyUI 才生效 -------------------------------
# --noproxy '*' 是双保险：学速的 no_proxy 已含 127.0.0.1，但显式声明更稳。
if [ "$api_changed" = "1" ]; then
  if curl -sf -m 5 --noproxy '*' "http://127.0.0.1:$PORT/system_stats" >/dev/null 2>&1; then
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
    echo "  curl -s -o /dev/null --max-time 3 --noproxy '*' http://127.0.0.1:$PORT/system_stats \\"
    echo "    || setsid bash $COMFY/start_h3.sh >> $BASE/comfyui_h3.log 2>&1 < /dev/null"
    echo ") &"
  } >> /etc/autodl.sh
  log "HOOK  /etc/autodl.sh 缺少自检挂载，已补回"
fi

log "DONE  v$SELF_VER changed=$any_changed api_changed=$api_changed"
exit 0
