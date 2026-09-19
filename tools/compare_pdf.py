#!/usr/bin/env python3
"""Build a local, page-aligned PDFReflowLib/Poppler review bundle (Python standard library only)."""
import argparse
import json
import math
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zipfile

from pdfreflow_tools import epub
from pdfreflow_tools.corpus import identity

TOOLS = Path(__file__).resolve().parent


def html_preview(root):
    """HTML serialization of XHTML for browsers that suppress XML in sandboxed iframes.

    Expand non-void self-closing tags (notably inline page markers), keep text/tails and styles.
    The original XHTML and EPUB remain available unchanged.
    """
    for element in root.iter():
        element.tag = element.tag.removeprefix("{http://www.w3.org/1999/xhtml}")
        element.attrib = {name.replace(epub.OPS, "epub:").replace(
            "{http://www.w3.org/XML/1998/namespace}", "xml:"): value
            for name, value in element.attrib.items()}
    head = root.find("head")
    if head is None:
        raise ValueError("XHTML chapter has no head")
    head.insert(0, ET.Element("meta", {"charset": "utf-8"}))
    return "<!doctype html>\n" + ET.tostring(root, encoding="unicode", method="html")


def select_pages(spec, count):
    if spec == "all":
        return list(range(1, count + 1))
    pages = set()
    for part in spec.split(","):
        if not re.fullmatch(r"[1-9]\d*(?:-[1-9]\d*)?", part):
            raise ValueError("pages must be 'all' or physical page numbers/ranges, e.g. 1,16,90-92")
        ends = [int(n) for n in part.split("-")]
        first, last = ends[0], ends[-1]
        if first > last or last > count:
            raise ValueError(f"page range {part} is outside 1–{count}")
        pages.update(range(first, last + 1))
    return sorted(pages)


def unpack_epub(path, output, maximum_bytes=512 * 1024 * 1024):
    """Extract our converter's EPUB, rejecting unsafe/ambiguous or oversized archives first."""
    with epub.open_archive(path, max_entries=10_000, max_uncompressed_bytes=maximum_bytes) as archive:
        entries = archive.infolist()
        seen = set()
        for entry in entries:
            name = entry.filename
            parts = PurePosixPath(name).parts
            if (not parts or name.startswith("/") or ".." in parts or "\\" in name
                    or name.rstrip("/") != "/".join(parts) or ":" in name
                    or name.casefold() in seen or stat.S_ISLNK(entry.external_attr >> 16)
                    or entry.flag_bits & 1):
                raise ValueError(f"Unsafe EPUB entry: {name!r}")
            seen.add(name.casefold())
        output.mkdir()
        for entry in entries:
            destination = output / entry.filename
            if entry.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, destination.open("xb") as target:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
    # Use actual pagebreak markers, including markers inside styled words/paragraphs.
    # Do not split XHTML at page boundaries: that would change the reconstruction under review.
    pages = {}
    for chapter in sorted(output.rglob("*.xhtml")):
        root = ET.parse(chapter).getroot()
        for element in root.iter():
            page = epub.page_boundary(element)
            if page is None:
                continue
            if page in pages:
                raise ValueError(f"Duplicate EPUB source page {page}")
            pages[page] = "epub/" + chapter.with_suffix(".html").relative_to(output).as_posix() + f"#page-{page}"
        preview = chapter.with_suffix(".html")
        with preview.open("x") as stream:
            stream.write(html_preview(root))
    if not pages:
        raise ValueError("EPUB contains no source-page markers")
    return pages


def run(command, output, log, timeout, *, echo=False, cwd=None):
    """Keep exact commands, status and durations; relay the converter's own progress unchanged."""
    started = time.monotonic()
    with output.open("wb") as stdout, log.open("wb") as stderr:
        child = subprocess.Popen(command, stdout=stdout, stderr=stderr, cwd=cwd)
        try:
            with log.open("rb") as progress:
                while child.poll() is None:
                    if time.monotonic() - started > timeout:
                        raise TimeoutError(f"Command timed out: {command[0]}")
                    if echo:
                        sys.stderr.buffer.write(progress.read())
                        sys.stderr.flush()
                    time.sleep(0.1)
                if echo:
                    sys.stderr.buffer.write(progress.read())
                    sys.stderr.flush()
        finally:
            if child.poll() is None:
                child.kill()
            child.wait()
    result = {"command": command, "seconds": time.monotonic() - started,
              "exitCode": child.returncode}
    if cwd is not None:
        result["cwd"] = str(Path(cwd).resolve())
    if child.returncode:
        raise RuntimeError(f"Command failed ({child.returncode}); see {log} and {output}")
    return result


def executable(value):
    path = shutil.which(str(value))
    if path is None:
        raise ValueError(f"Executable not found: {value}")
    return str(Path(path).resolve())


def build(args):
    converter = executable(args.converter)
    poppler = executable(args.pdftohtml)
    renderer = executable(args.pdftoppm)
    source = args.pdf.resolve(strict=True)
    if source.stat().st_size > 256 * 1024 * 1024:
        raise ValueError("PDF exceeds the converter's default 256 MiB input ceiling")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = {"schemaVersion": 1, "status": "building", "sourceName": source.name,
                "commands": [], "pages": []}

    def save():
        (output / "comparison.json").write_text(json.dumps(manifest, indent=2) + "\n")

    try:
        manifest["platform"] = platform.platform()
        # Both programs consume the same snapshot even if the original file changes during review.
        snapshot = output / "input.pdf"
        shutil.copyfile(source, snapshot)
        manifest["source"] = identity(snapshot)
        manifest["converter"] = {"path": converter, **identity(Path(converter))}
        manifest["harness"] = {str(path.relative_to(TOOLS)): identity(path) for path in [
            TOOLS / "compare_pdf.py", TOOLS / "serve_comparison.py",
            *sorted((TOOLS / "comparison").iterdir())] if path.is_file()}
        manifest["popplerVersion"] = subprocess.run(
            [poppler, "-v"], capture_output=True, text=True, check=True, timeout=10
        ).stderr.strip()
        save()
        command = [converter, str(snapshot), str(output / "pdfreflow.epub")]
        if args.no_ocr:
            command.append("--no-ocr")
        print("Converting the complete PDF with PDFReflowLib…", file=sys.stderr, flush=True)
        manifest["commands"].append(run(command, output / "conversion-report.json",
                                         output / "progress.log", args.timeout, echo=True))
        report = json.loads((output / "conversion-report.json").read_text())
        count = report["pageCount"]
        if not isinstance(count, int) or not 1 <= count <= 2000:
            raise ValueError("Invalid converter page count")
        pages = select_pages(args.pages, count)
        anchors = unpack_epub(output / "pdfreflow.epub", output / "epub")
        if set(anchors) != set(range(1, count + 1)):
            raise ValueError("EPUB source pages do not match the conversion report")
        manifest.update({"pageCount": count, "report": report,
                         "epub": identity(output / "pdfreflow.epub")})
        for index, page in enumerate(pages, 1):
            print(f"Preparing comparison {index}/{len(pages)} · source page {page}/{count}",
                  file=sys.stderr, flush=True)
            directory = output / "pages" / str(page)
            directory.mkdir(parents=True)
            common = [poppler, "-f", str(page), "-l", str(page), "-noframes", "-enc", "UTF-8"]
            for mode, flags in (("simple", []), ("positioned", ["-c", "-s"])):
                # A relative output basename keeps Poppler's image URLs bundle-relative.
                # Record cwd alongside the exact command; raw HTML is never rewritten.
                command = common + flags + [str(snapshot), f"{mode}.html"]
                manifest["commands"].append(run(command, directory / f"{mode}.stdout.log",
                                                 directory / f"{mode}.stderr.log", args.timeout, cwd=directory))
                if not (directory / f"{mode}.html").is_file():
                    raise ValueError(f"Poppler did not produce {mode}.html")
            command = [renderer, "-f", str(page), "-l", str(page), "-singlefile",
                       "-scale-to", "1400", "-png", str(snapshot), str(directory / "source")]
            manifest["commands"].append(run(command, directory / "source.stdout.log",
                                             directory / "source.stderr.log", args.timeout))
            if not (directory / "source.png").is_file():
                raise ValueError("Poppler did not render the source page")
            manifest["pages"].append({"number": page, "epub": anchors[page],
                                      "simple": f"pages/{page}/simple.html",
                                      "positioned": f"pages/{page}/positioned.html",
                                      "source": f"pages/{page}/source.png"})
            save()
        for name in ("index.html", "viewer.js", "viewer.css"):
            shutil.copyfile(TOOLS / "comparison" / name, output / name)
        manifest["status"] = "ready"
        save()
        return output
    except BaseException as error:
        manifest["status"] = "failed"
        manifest["error"] = str(error) or type(error).__name__
        save()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--converter", required=True)
    parser.add_argument("--output", type=Path, required=True, help="new directory; retains all review artifacts")
    parser.add_argument("--pages", default="all", help="physical PDF pages: all (default), 1,16,90-92, etc.")
    parser.add_argument("--pdftohtml", default="pdftohtml")
    parser.add_argument("--pdftoppm", default="pdftoppm")
    parser.add_argument("--no-ocr", action="store_true")
    parser.add_argument("--timeout", type=float, default=1800, help="seconds per external command")
    parser.add_argument("--serve", action="store_true", help="serve the finished viewer on loopback until Ctrl-C")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("timeout must be positive and finite")
    try:
        output = build(args)
        print(f"Comparison ready: {output}", flush=True)
        if args.serve:
            from serve_comparison import serve
            serve(output, args.port)
        else:
            import shlex
            print("Open with: " + shlex.join([sys.executable, str(TOOLS / "serve_comparison.py"), str(output)]))
    except (OSError, ValueError, RuntimeError, TimeoutError, subprocess.SubprocessError,
            zipfile.BadZipFile, ET.ParseError) as error:
        parser.exit(1, f"Comparison failed: {error}\n")


if __name__ == "__main__":
    main()
