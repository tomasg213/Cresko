import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "api", "src"))

from cresko_api.main import app  # noqa: E402


async def handler(scope, receive, send):
    if scope["type"] == "http":
        path = scope.get("path", "")
        if path.startswith("/api"):
            scope["path"] = path[len("/api"):] or "/"
            scope["raw_path"] = scope["path"].encode("latin-1")
        else:
            scope["path"] = "/"
            scope["raw_path"] = b"/"
    await app(scope, receive, send)