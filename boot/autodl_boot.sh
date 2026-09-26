# --- H3 Console: ComfyUI 开机自启（追加到 /etc/autodl.sh） ---
# AutoDL 容器开机由 supervisord 执行 /etc/autodl.sh；等 15s 后探测 6006，
# 已有服务则跳过，否则用 setsid 拉起 start_h3.sh（日志见 /root/autodl-tmp/comfyui_h3.log）
# 拉起前先从 GitHub 刷新 h3ui_api.py（端点升级随开机自动生效，无需手动部署）。
# ComfyUI 本体可能位于数据盘（/root/autodl-tmp/ComfyUI）或系统盘（/root/ComfyUI，社区镜像），
# 双位置都刷新，无论启动器使用哪个都生效。
( sleep 15
  source /etc/network_turbo >/dev/null 2>&1
  for CN in /root/autodl-tmp/ComfyUI/custom_nodes /root/ComfyUI/custom_nodes; do
    [ -d "$CN" ] && curl -sf -m 20 -o "$CN/h3ui_api.py" \
      https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/h3ui_api.py
  done
  curl -sf http://127.0.0.1:6006/system_stats >/dev/null 2>&1 \
    || setsid bash /root/autodl-tmp/ComfyUI/start_h3.sh > /root/autodl-tmp/comfyui_h3.log 2>&1 < /dev/null &
) &
