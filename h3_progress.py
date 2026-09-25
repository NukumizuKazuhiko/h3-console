import os
import re
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SSH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'autodl_ssh.py')
INTERVAL = int(sys.argv[1]) if len(sys.argv) > 1 else 30

FILES = [
    ("int8 DiT  ", "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors", 20970379616),
    ("nvfp4 TE  ", "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors", 15687142551),
    ("video VAE ", "vae/minimax_h3_video_vae_fp16.safetensors", 5207808496),
    ("audio VAE ", "vae/minimax_h3_audio_vae_fp32.safetensors", 605254808),
    ("turbo LoRA", "loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors", 1956193000),
]


def ssh(cmd, timeout=60):
    import subprocess
    r = subprocess.run(["py", SSH, cmd, str(timeout)], capture_output=True, text=True)
    return r.stdout


def gib(n):
    return f"{n / 1024**3:.2f}GiB"


def bar(pct, width=28):
    filled = round(pct / 100 * width)
    return "█" * filled + "░" * (width - filled)


def main():
    while True:
        alive = ssh(
            'pgrep -c aria2c || echo 0; '
            'cd /root/autodl-tmp/H3 && '
            'for f in diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors '
            'text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors '
            'vae/minimax_h3_video_vae_fp16.safetensors '
            'vae/minimax_h3_audio_vae_fp32.safetensors '
            'loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors; do '
            'if [ -e "$f.aria2" ]; then echo "IP $f"; elif [ -f "$f" ]; then echo "DN $f"; else echo "MS $f"; fi; done; '
            'echo ---LOG---; '
            'grep -E "FILE:|\\[#[0-9a-f]{6} " /root/autodl-tmp/aria2_ms.log | tail -60'
        )
        first, _, rest = alive.partition("\n")
        alive = first.strip() if first.strip().isdigit() else "0"
        state_part, log = rest.split("---LOG---", 1) if "---LOG---" in rest else ("", rest)
        state = {}
        for ln in state_part.splitlines():
            parts = ln.strip().split(" ", 1)
            if len(parts) == 2:
                state[parts[1]] = parts[0]

        # aria2 writes status and FILE: on separate lines; pair them up
        last_status = None
        progress = {}   # path -> (done_str, done_unit, pct)
        completed = set()
        status_re = re.compile(r"\[#[0-9a-f]+ ([0-9.]+)([KMG])iB/([0-9.]+)([KMG])iB\((\d+)%\)[^\]]*DL:([0-9.]+)([KM])iB")
        for line in log.splitlines():
            m = status_re.search(line)
            if m:
                last_status = m
                continue
            fm = re.search(r"FILE: (\S+)", line)
            if fm and last_status:
                progress[fm.group(1)] = last_status
                last_status = None
            cm = re.search(r"Download complete: (\S+)", line)
            if cm:
                completed.add(cm.group(1))

        lines = []
        total_done = total_size = 0.0
        total_speed = 0.0
        all_done = True

        for name, path, size in FILES:
            remote_path = "/root/autodl-tmp/H3/" + path
            st = state.get(path, "MS")
            if st == "DN":
                pct, done, note = 100.0, float(size), ""
            elif st == "IP":
                all_done = False
                m = progress.get(remote_path)
                if m:
                    unit = {"K": 2**10, "M": 2**20, "G": 2**30}[m.group(2)]
                    done = float(m.group(1)) * unit
                    pct = float(m.group(5))
                    note = ""
                else:
                    done, pct, note = 0.0, 0.0, ""
            else:
                all_done = False
                done, pct, note = 0.0, 0.0, "  (未开始)"
            total_done += done
            total_size += size
            lines.append(f"{name} {bar(pct)} {pct:5.1f}%  {gib(done)}/{gib(size)}{note}")

        # global speed: sum DL of currently active files (progress dict holds latest per file)
        total_speed = 0.0
        for p in progress.values():
            total_speed += float(p.group(6)) * {"K": 1 / 1024, "M": 1}[p.group(7)]
        remaining = (total_size - total_done) / 2**20
        eta_min = remaining / max(total_speed, 0.1) / 60

        frame = [
            "======== MiniMax H3 权重下载进度 ========",
            *lines,
            "-" * 60,
            f"总体: {bar(total_done / total_size * 100, 34)} "
            f"{total_done / total_size * 100:5.1f}%   剩余 {gib(total_size - total_done)}",
            f"速度: {total_speed:.1f} MiB/s   预计剩余: {eta_min:.0f} 分钟",
            f"aria2 进程: {'运行中' if alive.isdigit() and int(alive) > 0 else '已退出'}",
            f"刷新时间: {time.strftime('%H:%M:%S')}   (Ctrl+C 退出)",
        ]

        if not os.environ.get("NO_CLEAR"):
            os.system("cls" if os.name == "nt" else "clear")
        print("\n".join(frame), flush=True)

        if "--once" in sys.argv:
            break
        if all_done:
            print("\n全部下载完成！可以做最终校验并切有卡了。")
            break
        if not (alive.isdigit() and int(alive) > 0) and not all_done:
            print("\n[警告] aria2 已退出但文件未齐 —— 下载可能中断，需要重启 aria2！")
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
