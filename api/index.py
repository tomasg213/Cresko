import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "api", "src"))

from asgiref.wsgi import WsgiToAsgi  # noqa: E402
from cresko_api.main import app as cresko_app  # noqa: E402

wsgi_app = WsgiToAsgi(cresko_app)


def handler(environ, start_response):
    path = environ.get("PATH_INFO", "")
    if path.startswith("/api"):
        environ["PATH_INFO"] = path[len("/api"):] or "/"
    return wsgi_app(environ, start_response)