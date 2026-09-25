# --- H3 Console: ComfyUI 开机自启（追加到 /etc/autodl.sh） ---
# AutoDL 容器开机由 supervisord 执行 /etc/autodl.sh；等 15s 后探测 6006，
# 已有服务则跳过，否则用 setsid 拉起 start_h3.sh（日志见 /root/autodl-tmp/comfyui_h3.log）
# 拉起前先从 GitHub 刷新 h3ui_api.py（端点升级随开机自动生效，无需手动部署）
( sleep 15
  source /etc/network_turbo >/dev/null 2>&1
  curl -sf -m 20 -o /root/autodl-tmp/ComfyUI/custom_nodes/h3ui_api.py \
    https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/h3ui_api.py
  curl -sf http://127.0.0.1:6006/system_stats >/dev/null 2>&1 \
    || setsid bash /root/autodl-tmp/ComfyUI/start_h3.sh > /root/autodl-tmp/comfyui_h3.log 2>&1 < /dev/null &
) &
