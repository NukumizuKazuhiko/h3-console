import urllib.request, urllib.error
for p in ["/", "/system_stats", "/api/system_stats", "/queue", "/api/queue", "/object_info", "/api/object_info", "/prompt", "/api/prompt"]:
    try:
        r = urllib.request.urlopen("http://127.0.0.1:6006" + p, timeout=10)
        body = r.read(200)
        print(p, "->", r.status, body[:120])
    except urllib.error.HTTPError as e:
        print(p, "-> HTTP", e.code)
    except Exception as e:
        print(p, "-> ERR", e)
