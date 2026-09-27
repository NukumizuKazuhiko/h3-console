# --- H3 Console: 开机组件自检 + ComfyUI 自启（本段被追加到 /etc/autodl.sh） ---
# AutoDL 容器开机由 supervisord 执行 /etc/autodl.sh，本段流程：
#   ① 先跑组件自检脚本：按 sha256 比对仓库最新版，不一致就更新
#      （旧版 h3ui_api.py 缺 /h3ui/v1/* 路由会让生成报 Failed to fetch）
#   ② 再确认 ComfyUI 在跑：6006 不通则用 setsid 拉起 start_h3.sh
#      （日志 /root/autodl-tmp/comfyui_h3.log）
# 更新源：只用官方 GitHub，两条网络路径——直连优先，不通再开学术加速
#       （source /etc/network_turbo）。不使用 gh-proxy 类第三方加速站，它们各自
#       带 CDN 缓存，同一文件会返回不同版本。自检脚本随后用 commit-sha pin 的
#       权威源校正版本。
# ComfyUI 本体可能在数据盘（/root/autodl-tmp/ComfyUI）或系统盘（/root/ComfyUI，社区镜像），
# 自检脚本会同步插件到两处。
(
sleep 5
SELF=/root/autodl-tmp/h3_selfcheck.sh
U=https://raw.githubusercontent.com/NukumizuKazuhiko/h3-console/main/boot/h3_selfcheck.sh
if [ ! -s "$SELF" ]; then
  curl -fsSL -m 25 -o "$SELF" "$U" 2>/dev/null || true
  if [ ! -s "$SELF" ] && [ -f /etc/network_turbo ]; then
    . /etc/network_turbo >/dev/null 2>&1
    curl -fsSL -m 25 -o "$SELF" "$U" 2>/dev/null || true
  fi
  sed -i 's/\r$//' "$SELF" 2>/dev/null
  chmod +x "$SELF" 2>/dev/null
fi
[ -s "$SELF" ] && bash "$SELF" >/dev/null 2>&1   # 日志由自检脚本自身写入 h3_selfcheck.log（勿再重定向，否则重复）
sleep 8
curl -s -o /dev/null --max-time 3 --noproxy '*' http://127.0.0.1:6006/system_stats \
  || setsid bash /root/autodl-tmp/ComfyUI/start_h3.sh >> /root/autodl-tmp/comfyui_h3.log 2>&1 < /dev/null
) &
