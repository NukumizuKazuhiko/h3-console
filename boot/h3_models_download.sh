#!/bin/bash
# MiniMax H3 模型下载（ModelScope 魔搭源，国内快；幂等可续传）
BASE=/root/autodl-tmp/ComfyUI
PY=/root/miniconda3/bin/python
LOG=/root/autodl-tmp/h3_models_download.log

mkdir -p $BASE/models   # 实体目录必须先在位（系统盘镜像经软链指向此处），否则 App 探测 du 取到空值
# 基线字节：镜像 models 目录自带其他模型（约 5.6G），App 进度按「当前 du - 基线」统计本次下载增量
echo "===== base bytes=$(du -sb $BASE/models 2>/dev/null | cut -f1) $(date +%s) =====" >> $LOG
echo "===== start epoch=$(date +%s) $(date) =====" >> $LOG
$PY -m pip install -q -U modelscope >> $LOG 2>&1

$PY - <<'EOF' >> $LOG 2>&1
from modelscope import snapshot_download
FILES = [
    "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors",
    "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors",
    "vae/minimax_h3_video_vae_fp16.safetensors",
    "vae/minimax_h3_audio_vae_fp32.safetensors",
    "loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors",
]
p = snapshot_download("Comfy-Org/MiniMax-H3",
                      local_dir="/root/autodl-tmp/ComfyUI/models",
                      allow_patterns=FILES)
print("downloaded to:", p)
EOF
RC=$?

MISS=0
for f in diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors \
         text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors \
         vae/minimax_h3_video_vae_fp16.safetensors \
         vae/minimax_h3_audio_vae_fp32.safetensors \
         loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors; do
  if [ -f $BASE/models/$f ]; then echo "OK $f" >> $LOG; else echo "MISSING $f" >> $LOG; MISS=1; fi
done
echo "===== done rc=$RC miss=$MISS epoch=$(date +%s) $(date) =====" >> $LOG
exit $(( RC || MISS ))
