import os
from server import PromptServer
from aiohttp import web

OUT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "output"))

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
