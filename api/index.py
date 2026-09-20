import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "api", "src"))

from cresko_api.main import app as fastapi_app  # noqa: E402


class _StripApiPrefix:
    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            path = scope.get("path", "")
            if path.startswith("/api"):
                scope["path"] = path[len("/api"):] or "/"
                scope["raw_path"] = scope["path"].encode("latin-1")
        await self.inner(scope, receive, send)


app = _StripApiPrefix(fastapi_app)