#!/usr/bin/env python3
"""Serve one generated comparison on loopback, with scripts disabled in document previews."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


class ReviewHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.safe_path():
            super().do_GET()

    def do_HEAD(self):
        if self.safe_path():
            super().do_HEAD()

    def safe_path(self):
        root = Path(self.directory).resolve()
        relative = unquote(urlsplit(self.path).path).lstrip("/") or "index.html"
        path = root / relative
        if (".." in Path(relative).parts or "\\" in relative
                or not path.resolve().is_relative_to(root)
                or any(parent.is_symlink() for parent in [path, *path.parents] if parent != root)):
            self.send_error(403)
            return False
        if path.is_dir() and path != root:
            self.send_error(403, "Directory listing disabled")
            return False
        return True

    def list_directory(self, path):
        self.send_error(403, "Directory listing disabled")
        return None

    def end_headers(self):
        shell = urlsplit(self.path).path in ("/", "/index.html")
        policy = ("default-src 'none'; img-src 'self'; style-src 'self' 'unsafe-inline'; "
                  "base-uri 'none'; object-src 'none'; form-action 'none'; ")
        policy += ("script-src 'self'; connect-src 'self'; frame-src 'self'; frame-ancestors 'none'"
                   if shell else "script-src 'none'; frame-ancestors 'self'")
        self.send_header("Content-Security-Policy", policy)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        if urlsplit(self.path).path.endswith(".pdf"):
            self.send_header("Content-Disposition", "attachment")
        super().end_headers()


def serve(directory, port=8765):
    directory = Path(directory).resolve(strict=True)
    if not (directory / "comparison.json").is_file() or not (directory / "index.html").is_file():
        raise ValueError("Not a completed comparison directory")
    with ThreadingHTTPServer(("127.0.0.1", port), partial(ReviewHandler, directory=str(directory))) as server:
        print(f"Review: http://127.0.0.1:{server.server_port}/ (Ctrl-C to stop)", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    serve(args.directory, args.port)
