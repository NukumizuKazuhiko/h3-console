# --- H3 Console: 开机组件自检 + ComfyUI 自启（本段被追加到 /etc/autodl.sh） ---
# AutoDL 容器开机由 supervisord 执行 /etc/autodl.sh，本段流程：
#   ① 先跑组件自检脚本：按 sha256 比对仓库最新版，不一致就更新
#      （旧版 h3ui_api.py 缺 /h3ui/v1/* 路由会让生成报 Failed to fetch）
#   ② 再确认 ComfyUI 在跑：6006 不通则用 setsid 拉起 start_h3.sh
#      （日志 /root/autodl-tmp/comfyui_h3.log）
# 注意：容器内 raw.githubusercontent.com 通常不可达，故一律走多源回退：
#       gh-proxy.com → ghproxy.net → [学术加速] raw → jsDelivr
# ComfyUI 本体可能在数据盘（/root/autodl-tmp/ComfyUI）或系统盘（/root/ComfyUI，社区镜像），
# 自检脚本会同步插件到两处。
(
sleep 5
SELF=/root/autodl-tmp/h3_selfcheck.sh
if [ ! -s "$SELF" ]; then
  for U in \
    "https://gh-proxy.com/https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/boot/h3_selfcheck.sh" \
    "https://ghproxy.net/https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/boot/h3_selfcheck.sh" \
    "https://cdn.jsdelivr.net/gh/NukumizuKazuhiko/h3-console@main/boot/h3_selfcheck.sh" ; do
    curl -fsSL -m 25 -o "$SELF" "$U" 2>/dev/null && [ -s "$SELF" ] && break
  done
  chmod +x "$SELF" 2>/dev/null
fi
[ -s "$SELF" ] && bash "$SELF" >/dev/null 2>&1   # 日志由自检脚本自身写入 h3_selfcheck.log（勿再重定向，否则重复）
sleep 8
curl -s -o /dev/null --max-time 3 http://127.0.0.1:6006/system_stats \
  || setsid bash /root/autodl-tmp/ComfyUI/start_h3.sh >> /root/autodl-tmp/comfyui_h3.log 2>&1 < /dev/null
) &
