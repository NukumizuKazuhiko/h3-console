#!/bin/bash
# ComfyUI + H3 启动脚本（AutoDL 社区镜像路径，其他环境请自行调整）
# --enable-cors-header 为浏览器/APK 跨域访问所必需
# 无卡模式下 ComfyUI 0.35 会在 model_management 硬崩溃（No CUDA GPUs are available），
# 自动探测：无 GPU 时追加 --cpu（界面/API 可用，仅生成不可用）
cd /root/LaunchTool311
GPU_N=$(nvidia-smi -L 2>/dev/null | grep -c GPU)
EXTRA=""
if [ "$GPU_N" = "0" ]; then EXTRA="--cpu"; echo "[start_h3] no GPU detected -> --cpu"; fi
env PATH=/root/miniconda3/bin:/usr/local/bin:/usr/bin:/bin \
  python startup.py --hf-mirror --proxy-on --port=6006 --enable-cors-header \
  --preview-method=latent2rgb --preview-size=256 $EXTRA
