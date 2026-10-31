#!/usr/bin/env python3
"""Local preview for devmon.html: serves page + ikui and mocks /Action/call."""
import json
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2])
HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "mock_data.json"), encoding="utf-8") as fh:
    DATA = json.load(fh)
with open(os.path.join(HERE, "mock_candidates.json"), encoding="utf-8") as fh:
    CANDIDATES = json.load(fh)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def do_POST(self):
        if self.path != "/Action/call":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            body = {}
        action = body.get("action")
        if action == "show":
            data = DATA
        elif action == "scan":
            data = {"candidates": CANDIDATES}
        else:
            data = {}
        raw = json.dumps({"Result": 30000, "ErrMsg": "Success", "Data": data}, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
