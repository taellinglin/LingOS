#!/usr/bin/env python3
"""Minimal HTTP server for the horizon redirect+image test: serves
test.html and logo.png directly, and 302-redirects /redirect.html ->
/test.html and /redir-logo.png -> /logo.png so the guest's fetch_raw has
something real to follow."""

import http.server

REDIRECTS = {
    "/redirect.html": "/test.html",
    "/redir-logo.png": "/logo.png",
}
FILES = {
    "/test.html": ("text/html", "test.html"),
    "/logo.png": ("image/png", "logo.png"),
}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in REDIRECTS:
            self.send_response(302)
            self.send_header("Location", REDIRECTS[self.path])
            self.end_headers()
            return
        if self.path in FILES:
            ctype, fname = FILES[self.path]
            with open(fname, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", 80), Handler).serve_forever()
