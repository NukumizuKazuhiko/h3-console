import os
from server import PromptServer
from aiohttp import web

_dir = os.path.dirname(__file__)
with open(os.path.join(_dir, "h3_console.html"), encoding="utf-8") as f:
    _HTML = f.read()

routes = PromptServer.instance.routes

@routes.get("/h3ui")
async def h3ui_page(request):
    return web.Response(text=_HTML, content_type="text/html")

NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}
