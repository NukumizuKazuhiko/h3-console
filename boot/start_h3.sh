#!/bin/bash
# ComfyUI + H3 启动脚本（AutoDL 社区镜像路径，其他环境请自行调整）
# --enable-cors-header 为浏览器/APK 跨域访问所必需
cd /root/LaunchTool311 && env PATH=/root/miniconda3/bin:/usr/local/bin:/usr/bin:/bin \
  python startup.py --hf-mirror --proxy-on --port=6006 --enable-cors-header \
  --preview-method=latent2rgb --preview-size=256
