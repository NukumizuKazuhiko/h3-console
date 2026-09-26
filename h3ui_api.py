import os
import sys
import re
import base64
import uuid
import time
import asyncio
import json as _json
import urllib.request
from server import PromptServer
from aiohttp import web

OUT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "output"))
INP = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "input"))

# ---------------- 监控（原有能力） ----------------

def _cpu_sample():
    with open("/proc/stat") as f:
        parts = f.readline().split()[1:]
    vals = list(map(int, parts))
    return sum(vals), vals[0]  # (total, idle)

def _gpu_util():
    try:
        import pynvml
        pynvml.nvmlInit()
        h = pynvml.nvmlDeviceGetHandleByIndex(0)
        util = round(float(pynvml.nvmlDeviceGetUtilizationRates(h).gpu), 1)
        try:
            temp = round(float(pynvml.nvmlDeviceGetTemperature(h, pynvml.NVML_TEMPERATURE_GPU)), 1)
        except Exception:
            temp = None
        return util, temp
    except Exception:
        pass
    try:
        import subprocess
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, timeout=3,
        )
        vals = [float(x) for x in out.stdout.decode().strip().splitlines()[0].split(",")]
        return vals[0], vals[1]
    except Exception:
        return None, None

@PromptServer.instance.routes.get("/h3ui/stats")
async def h3ui_stats(request):
    cpu = None
    try:
        t0, i0 = _cpu_sample()
        await asyncio.sleep(0.2)
        t1, i1 = _cpu_sample()
        dt, di = t1 - t0, i1 - i0
        if dt > 0:
            cpu = round(100.0 * (1.0 - di / dt), 1)
    except Exception:
        pass
    gpu, temp = await asyncio.get_event_loop().run_in_executor(None, _gpu_util)
    return web.json_response({"cpu": cpu, "gpu": gpu, "temp": temp})

@PromptServer.instance.routes.post("/h3ui/delete")
async def h3ui_delete(request):
    try:
        data = await request.json()
        names = data.get("delete") or []
    except Exception as e:
        return web.json_response({"error": "bad json: %s" % e}, status=400)
    removed, missing = [], []
    for n in names:
        if not isinstance(n, str) or n == "":
            continue
        p = os.path.realpath(os.path.join(OUT, n))
        if p == OUT or not p.startswith(OUT + os.sep):
            missing.append(n)
            continue
        if os.path.isfile(p):
            try:
                os.remove(p)
                removed.append(n)
            except Exception as e:
                missing.append("%s (%s)" % (n, e))
        else:
            missing.append(n)
    return web.json_response({"deleted": removed, "missing": missing})

# ================= MiniMax H3 官方文档风格 API（v1.92） =================
# 工作流图固化在服务端：客户端只传业务参数，彻底隔离 ComfyUI 版本/节点/模型差异。
#   POST /h3ui/v1/video_generation            提交生成任务（对齐 MiniMax video_generation 语义）
#   GET  /h3ui/v1/queries/video_generation    查询任务状态（对齐 queries 语义）
#   GET  /h3ui/v1/files/retrieve              取回结果文件（对齐 files/retrieve 语义）
#   GET  /h3ui/v1/models                      模型就绪状态
# 响应统一带 base_resp: {status_code, status_msg}（0 = 成功），对齐官方风格。

def _ok(**kw):
    kw.setdefault("base_resp", {"status_code": 0, "status_msg": "success"})
    return web.json_response(kw)

def _err(code, msg, status=400):
    return web.json_response({"base_resp": {"status_code": code, "status_msg": msg}}, status=status)

def _port():
    a = sys.argv
    try:
        return int(a[a.index("--port") + 1])
    except Exception:
        return 8188

async def _self_http(method, path, payload=None, timeout=60):
    """进程内自调 ComfyUI 原生 HTTP（提交/历史/对象信息），避免依赖内部 API 变动。"""
    import aiohttp
    url = "http://127.0.0.1:%d%s" % (_port(), path)
    to = aiohttp.ClientTimeout(total=timeout)
    async with aiohttp.ClientSession(timeout=to) as ses:
        if payload is None:
            async with ses.request(method, url) as r:
                return r.status, await r.json(content_type=None)
        async with ses.request(method, url, json=payload) as r:
            return r.status, await r.json(content_type=None)

# ---- 模型文件动态适配：从 /object_info 的实际枚举里按优先级挑选 ----
_OBJINFO = None
_OBJINFO_AT = 0.0

async def _objinfo(force=False):
    global _OBJINFO, _OBJINFO_AT
    if not force and _OBJINFO and time.time() - _OBJINFO_AT < 300:
        return _OBJINFO
    try:
        s, d = await _self_http("GET", "/object_info", timeout=60)
        if s == 200:
            _OBJINFO = d
            _OBJINFO_AT = time.time()
    except Exception:
        pass
    return _OBJINFO or {}

def _names(oi, node, field):
    try:
        v = oi[node]["input"]["required"][field][0]
        return v if isinstance(v, list) else []
    except Exception:
        return []

def _pick(names, prefs):
    for p in prefs:
        for n in names:
            if p in n:
                return n
    return names[0] if names else None

REQUIRED_MODELS = {
    "diffusion": "minimax_h3_fl2va(DiT)",
    "text_encoder": "qwen3vl_32b_minimax_h3(text encoder)",
    "video_vae": "minimax_h3_video_vae",
    "audio_vae": "minimax_h3_audio_vae",
}

async def _resolve_models(oi):
    """返回 (选中的模型文件 dict, 缺失清单)。缺失时不猜文件名。"""
    missing = []
    m = {}
    unet = _names(oi, "UNETLoader", "unet_name")
    clip = _names(oi, "CLIPLoader", "clip_name")
    lora = _names(oi, "LoraLoaderModelOnly", "lora_name")
    vae = _names(oi, "VAELoader", "vae_name")
    m["diffusion"] = _pick(unet, ["fl2va_pruned_int8_convrot", "fl2va_int8_convrot", "fl2va_pruned_fp8", "fl2va_pruned_int4", "fl2va_bf16", "fl2va"])
    m["text_encoder"] = _pick(clip, ["nvfp4_awq", "int8_convrot", "int4_convrot", "bf16"])
    m["turbo_lora"] = _pick(lora, ["fl2v_turbo_8step", "fl2v_turbo_4step"])
    m["video_vae"] = _pick(vae, ["minimax_h3_video_vae"])
    m["audio_vae"] = _pick(vae, ["minimax_h3_audio_vae"])
    for k in ("diffusion", "text_encoder", "video_vae", "audio_vae"):
        if not m.get(k):
            missing.append(REQUIRED_MODELS.get(k, k))
    return m, missing

def _build_graph(m, p):
    """组装 t2v / i2v / flf2v 工作流（节点拓扑与官方模板一致）。"""
    turbo = bool(p.get("turbo", True))
    steps = 8 if turbo else 20
    model_src = ["2", 0] if (turbo and m.get("turbo_lora")) else ["1", 0]
    wf = {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": m["diffusion"], "weight_dtype": "default"}},
        "3": {"class_type": "CLIPLoader", "inputs": {"clip_name": m["text_encoder"], "type": "minimax", "device": "default"}},
        "4": {"class_type": "VAELoader", "inputs": {"vae_name": m["video_vae"]}},
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": m["audio_vae"]}},
        "6": {"class_type": "MiniMaxH3ImageToVideo", "inputs": {
            "clip": ["3", 0], "vae": ["4", 0], "prompt": p["prompt"],
            "width": p["width"], "height": p["height"], "length": p["length"]}},
        "7": {"class_type": "RandomNoise", "inputs": {"noise_seed": p["seed"]}},
        "8": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "res_multistep"}},
        "9": {"class_type": "BasicScheduler", "inputs": {"scheduler": "simple", "steps": steps, "denoise": 1.0, "model": model_src}},
        "10": {"class_type": "BasicGuider", "inputs": {"model": model_src, "conditioning": ["6", 0]}},
        "11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["7", 0], "guider": ["10", 0], "sampler": ["8", 0], "sigmas": ["9", 0], "latent_image": ["6", 1]}},
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["4", 0]}},
        "13": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["11", 0], "vae": ["5", 0]}},
        "14": {"class_type": "CreateVideo", "inputs": {"images": ["12", 0], "audio": ["13", 0], "fps": 24}},
        "15": {"class_type": "SaveVideo", "inputs": {"video": ["14", 0], "filename_prefix": p["prefix"], "format": "auto", "codec": "auto"}},
    }
    if turbo and m.get("turbo_lora"):
        wf["2"] = {"class_type": "LoraLoaderModelOnly", "inputs": {"lora_name": m["turbo_lora"], "strength_model": p["strength"], "model": ["1", 0]}}
    if p.get("first_frame"):
        wf["16"] = {"class_type": "LoadImage", "inputs": {"image": p["first_frame"]}}
        wf["6"]["inputs"]["first_frame"] = ["16", 0]
    if p.get("last_frame"):
        wf["17"] = {"class_type": "LoadImage", "inputs": {"image": p["last_frame"]}}
        wf["6"]["inputs"]["last_frame"] = ["17", 0]
    return wf

def _save_input_image(v):
    """first/last_frame 支持：已上传文件名 | dataURL(base64) | http(s) URL。返回 ComfyUI input 文件名。"""
    if not v or not isinstance(v, str):
        return None
    v = v.strip()
    if v.startswith("data:"):
        b = v.split(",", 1)[1] if "," in v else ""
        raw = base64.b64decode(b)
        ext = ".png" if "image/png" in v[:64] else (".webp" if "image/webp" in v[:64] else ".jpg")
        name = "h3api_%d%s" % (int(time.time() * 1000), ext)
        with open(os.path.join(INP, name), "wb") as f:
            f.write(raw)
        return name
    if v.startswith("http://") or v.startswith("https://"):
        raw = urllib.request.urlopen(v, timeout=30).read()
        name = "h3api_%d.jpg" % int(time.time() * 1000)
        with open(os.path.join(INP, name), "wb") as f:
            f.write(raw)
        return name
    # 已上传的 ComfyUI input 文件名（可含子目录）
    p = os.path.realpath(os.path.join(INP, v))
    if p.startswith(INP + os.sep) and os.path.isfile(p):
        return v
    return None

@PromptServer.instance.routes.post("/h3ui/v1/video_generation")
async def h3ui_generate(request):
    try:
        p = await request.json()
    except Exception as e:
        return _err(1001, "bad json: %s" % e)
    prompt = (p.get("prompt") or "").strip()
    if not prompt:
        return _err(1002, "prompt is required")
    oi = await _objinfo()
    m, missing = await _resolve_models(oi)
    if missing:
        return _err(2013, "models not ready, missing: %s (run model download on instance)" % ",".join(missing), status=409)
    try:
        p["width"] = max(256, min(1536, int(p.get("width") or 832)))
        p["height"] = max(256, min(1536, int(p.get("height") or 480)))
        p["length"] = max(5, min(361, int(p.get("length") or 121)))
        p["seed"] = int(p.get("seed") or 0)
        p["strength"] = max(0.0, min(2.0, float(p.get("strength") or 1.0)))
    except Exception:
        return _err(1003, "invalid numeric params")
    p["prefix"] = "video/H3_api"
    for k in ("first_frame", "last_frame"):
        if p.get(k):
            fn = _save_input_image(p[k])
            if not fn:
                return _err(1004, "%s: image not found or failed to store" % k)
            p[k] = fn
    p["client_id"] = (p.get("client_id") or "").strip()
    wf = _build_graph(m, p)
    payload = {"prompt": wf}
    if p["client_id"]:
        payload["client_id"] = p["client_id"]
    try:
        s, d = await _self_http("POST", "/prompt", payload, timeout=60)
    except Exception as e:
        return _err(2001, "comfyui submit failed: %s" % e, status=502)
    if s != 200:
        msg = ""
        try:
            if isinstance(d, dict) and d.get("node_errors"):
                msg = _json.dumps(d["node_errors"], ensure_ascii=False)[:800]
            elif isinstance(d, dict) and d.get("error"):
                msg = _json.dumps(d["error"], ensure_ascii=False)[:800]
            else:
                msg = str(d)[:800]
        except Exception:
            msg = str(d)[:800]
        return _err(2002, "comfyui rejected prompt (HTTP %s): %s" % (s, msg), status=502)
    task_id = d.get("prompt_id") or str(uuid.uuid4())
    return _ok(task_id=task_id, status="Queued")

def _file_from_history(item):
    try:
        for o in (item.get("outputs") or {}).values():
            for key in ("videos", "gifs", "images"):
                arr = o.get(key)
                if arr:
                    f = arr[0]
                    sub = f.get("subfolder") or ""
                    return (sub + "/" + f["filename"]) if sub else f["filename"]
    except Exception:
        pass
    return None

@PromptServer.instance.routes.get("/h3ui/v1/queries/video_generation")
async def h3ui_query(request):
    task_id = request.query.get("task_id", "").strip()
    if not task_id:
        return _err(1005, "task_id is required")
    try:
        s, d = await _self_http("GET", "/history/%s" % task_id, timeout=30)
        if s != 200:
            return _err(2003, "history query failed (HTTP %s)" % s, status=502)
    except Exception as e:
        return _err(2003, "history query failed: %s" % e, status=502)
    item = d.get(task_id)
    if not item:
        return _ok(task_id=task_id, status="Queued", file_id=None)
    st = item.get("status") or {}
    if st.get("status_str") == "error":
        detail = ""
        try:
            for m in (st.get("messages") or []):
                if m[0] == "execution_error":
                    detail = str(m[1].get("exception_message") or m[1])[:600]
                    break
        except Exception:
            pass
        return _ok(task_id=task_id, status="Failed", file_id=None, error=detail)
    if st.get("completed"):
        fid = _file_from_history(item)
        return _ok(task_id=task_id, status="Completed", file_id=fid)
    return _ok(task_id=task_id, status="InProgress", file_id=None)

@PromptServer.instance.routes.get("/h3ui/v1/files/retrieve")
async def h3ui_file(request):
    fid = request.query.get("file_id", "").strip()
    if not fid:
        return _err(1006, "file_id is required")
    p = os.path.realpath(os.path.join(OUT, fid))
    if not p.startswith(OUT + os.sep) or not os.path.isfile(p):
        return _err(2004, "file not found: %s" % fid, status=404)
    ct = "video/mp4"
    if p.endswith(".webp"):
        ct = "image/webp"
    elif p.endswith(".png"):
        ct = "image/png"
    return web.FileResponse(p, headers={"Content-Type": ct, "Cache-Control": "no-store"})

@PromptServer.instance.routes.get("/h3ui/v1/models")
async def h3ui_models(request):
    oi = await _objinfo(force=True)
    m, missing = await _resolve_models(oi)
    return _ok(ready=(len(missing) == 0), missing=missing, selected=m)
