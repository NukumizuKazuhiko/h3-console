# --- H3 Console: ComfyUI 开机自启（追加到 /etc/autodl.sh） ---
# AutoDL 容器开机由 supervisord 执行 /etc/autodl.sh；等 15s 后探测 6006，
# 已有服务则跳过，否则用 setsid 拉起 start_h3.sh（日志见 /root/autodl-tmp/comfyui_h3.log）
( sleep 15
  curl -sf http://127.0.0.1:6006/system_stats >/dev/null 2>&1 \
    || setsid bash /root/autodl-tmp/ComfyUI/start_h3.sh > /root/autodl-tmp/comfyui_h3.log 2>&1 < /dev/null &
) &
