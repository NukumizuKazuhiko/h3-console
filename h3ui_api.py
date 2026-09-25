import os
import asyncio
from server import PromptServer
from aiohttp import web

OUT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "output"))

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
        return round(float(pynvml.nvmlDeviceGetUtilizationRates(h).gpu), 1)
    except Exception:
        pass
    try:
        import subprocess
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, timeout=3,
        )
        return float(out.stdout.decode().strip().splitlines()[0])
    except Exception:
        return None

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
    gpu = await asyncio.get_event_loop().run_in_executor(None, _gpu_util)
    return web.json_response({"cpu": cpu, "gpu": gpu})

@PromptServer.instance.routes.post("/h3ui/delete")
async def h3ui_delete(request):
    try:
        data = await request.json()
        names = data.get("delete") or []
    except Exception as e:
        return web.json_response({"error": "bad json: %s" % e}, status=400)
    removed, missing = [], []
    for n in names:
        if not isinstance(n, str) or not n:
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
