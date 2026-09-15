#!/usr/bin/env python3
"""Open PDFReflowLib EPUB output in a local foliate-js reader, without importing into an app."""
import argparse
from functools import partial
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import re
import shutil
import tempfile
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

from compare_pdf import identity, unpack_epub
from serve_comparison import ReviewHandler

ASSETS = Path(__file__).resolve().parent / "epub-reader"
MARKUP = {".xml", ".xhtml", ".opf"}


def verify_assets():
    manifest = json.loads((ASSETS / "assets.json").read_text())
    actual = {p.relative_to(ASSETS).as_posix() for p in (ASSETS / "lib").rglob("*") if p.is_file()}
    if actual != set(manifest["files"]):
        raise ValueError("Reader vendor inventory differs from its pin")
    for name, expected in manifest["files"].items():
        if (ASSETS / name).is_symlink() or identity(ASSETS / name) != expected:
            raise ValueError(f"Reader vendor identity mismatch: {name}")


def validate_resources(directory):
    """Restrict the test viewer to PDFReflowLib's inert XHTML/CSS/PNG EPUB profile.

    Reject active content before the engine sees it, rather than accepting arbitrary EPUBs
    or modifying publisher content. The chapter iframe additionally disables scripts.
    Generated .html comparison previews are not exposed to the reader's resource loader.
    """
    resources = {}
    for path in directory.rglob("*"):
        if not path.is_file() or path.suffix == ".html":
            continue
        name = path.relative_to(directory).as_posix()
        suffix = path.suffix.lower()
        if suffix not in MARKUP | {".png", ".css"} and name != "mimetype":
            raise ValueError(f"Outside PDFReflowLib's test-reader profile: {name}")
        if suffix in MARKUP:
            text = path.read_text()
            if "<!DOCTYPE" in text.upper() or "<!ENTITY" in text.upper():
                raise ValueError(f"Document declarations are unsupported: {name}")
            tree = ET.fromstring(text)
            for node in tree.iter():
                tag = node.tag.split("}")[-1].lower()
                if tag in {"script", "iframe", "object", "embed", "form", "base", "svg", "math"}:
                    raise ValueError(f"Active/unsupported markup in {name}: {tag}")
                attrs = {key.split("}")[-1].lower(): value for key, value in node.attrib.items()}
                if any(key.startswith("on") for key in attrs) or "http-equiv" in attrs:
                    raise ValueError(f"Active attributes in {name}")
                if tag == "link" and attrs.get("rel") != "stylesheet":
                    raise ValueError(f"Unsupported link in {name}")
                for key in ("href", "src"):
                    value = unquote(attrs.get(key, ""))
                    url = urlsplit(value)
                    if url.scheme or url.netloc or "\\" in value or value.startswith("/"):
                        raise ValueError(f"External resource/link in {name}")
                if "srcset" in attrs or "style" in attrs:
                    raise ValueError(f"Unsupported resource-bearing attribute in {name}")
                if tag == "item":
                    href = attrs.get("href", "")
                    expected = {".xhtml": "application/xhtml+xml", ".png": "image/png", ".css": "text/css"}
                    if Path(href).suffix not in expected or attrs.get("media-type") != expected[Path(href).suffix]:
                        raise ValueError(f"Unsupported EPUB manifest media type in {name}")
        elif suffix == ".css":
            text = path.read_text()
            if re.search(r"url\s*\(|@import|\\", text, re.IGNORECASE):
                raise ValueError(f"Resource-loading CSS is unsupported: {name}")
        resources[name] = path.stat().st_size
    if (directory / "mimetype").read_text() != "application/epub+zip":
        raise ValueError("Not an EPUB archive")
    return resources


def prepare(book, output):
    verify_assets()
    if book.stat().st_size > 512 * 1024 * 1024:
        raise ValueError("EPUB exceeds the 512 MiB reader limit")
    output.mkdir(exist_ok=False)
    shutil.copyfile(book, output / "book.epub")
    pages = unpack_epub(output / "book.epub", output / "epub")
    resources = validate_resources(output / "epub")
    for file in ASSETS.iterdir():
        if file.is_dir():
            shutil.copytree(file, output / file.name)
        else:
            shutil.copyfile(file, output / file.name)
    manifest = {"filename": book.name, "identity": identity(output / "book.epub"),
                "resources": resources, "pages": {page: path.removeprefix("epub/").replace(".html#", ".xhtml#")
                                                    for page, path in pages.items()}}
    (output / "book.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


class ReaderHandler(ReviewHandler):
    def safe_path(self):
        host = self.headers.get("Host", "").split(":")[0]
        if host not in {"", "localhost", "127.0.0.1"}:
            self.send_error(403)
            return False
        return super().safe_path()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("epub", type=Path)
    parser.add_argument("--port", type=int, default=8768)
    args = parser.parse_args()
    try:
        with tempfile.TemporaryDirectory(prefix="pdfreflow-reader-") as temporary:
            output = Path(temporary) / "reader"
            manifest = prepare(args.epub.resolve(strict=True), output)
            print(f"EPUB SHA-256: {manifest['identity']['sha256']}", flush=True)
            with ThreadingHTTPServer(("127.0.0.1", args.port), partial(ReaderHandler, directory=str(output))) as server:
                print(f"Reader: http://127.0.0.1:{server.server_port}/ (Ctrl-C to stop)", flush=True)
                server.serve_forever()
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError, ET.ParseError) as error:
        parser.exit(1, f"Cannot open EPUB: {error}\n")


if __name__ == "__main__":
    main()
