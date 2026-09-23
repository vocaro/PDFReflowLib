#!/usr/bin/env python3
"""Package the unfiled Apple Feedback drafts under measurements/apple-feedback-*/ for filing.

For every draft whose submission.json still carries a null feedbackID (and that is not marked
as deliberately unfiled), this writes to OUT/<name>/:

  title.txt        the report's H1, which is the Feedback Assistant title
  description.txt  the report body reflowed for Feedback Assistant's single description field
  <name>.zip       probe.swift and report.md, the attachment
  fields.json      title, area, type, attachment path, size and SHA-256

and prints one table. Nothing under measurements/ is modified; the feedbackID is written back
by hand once Feedback Assistant issues it.

  python3 tools/prepare_feedback_submissions.py OUT
  python3 tools/prepare_feedback_submissions.py OUT --clipboard font-substitution
"""
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DRAFTS = sorted(ROOT.glob("measurements/apple-feedback-*"))


def parse(report: str):
    lines = report.splitlines()
    title = lines[0].lstrip("# ").strip()
    area = type_ = None
    m = re.search(r"Suggested area:\s*(.+?)\.\s*Type:\s*(.+?)\.?$", report, re.M)
    if m:
        area, type_ = m.group(1).strip(), m.group(2).strip()
    sections, current, buf = [], None, []
    for line in lines[1:]:
        if line.startswith("## "):
            if current is not None:
                sections.append((current, "\n".join(buf).strip()))
            current, buf = line[3:].strip(), []
        elif current is not None:
            buf.append(line)
    if current is not None:
        sections.append((current, "\n".join(buf).strip()))
    return title, area, type_, sections


def describe(sections):
    out = []
    for heading, body in sections:
        body = re.sub(r"`([^`]*)`", r"\1", body)          # inline code marks
        body = re.sub(r"<(https?://[^>]+)>", r"\1", body)  # autolinks
        out.append(f"{heading.upper()}\n\n{body}")
    return "\n\n\n".join(out).strip() + "\n"


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    out_root = pathlib.Path(argv[1]).resolve()
    clip = argv[3] if len(argv) > 3 and argv[2] == "--clipboard" else None
    rows = []
    for d in DRAFTS:
        sub_path = d / "submission.json"
        if not sub_path.exists():
            continue
        sub = json.loads(sub_path.read_text())
        if sub.get("feedbackID") or sub.get("resolution", "").startswith("Not filed; no defect"):
            continue
        name = d.name.removeprefix("apple-feedback-")
        title, area, type_, sections = parse((d / "report.md").read_text())
        out = out_root / name
        out.mkdir(parents=True, exist_ok=True)
        (out / "title.txt").write_text(title + "\n")
        desc = describe(sections)
        (out / "description.txt").write_text(desc)
        zip_path = out / f"{name}.zip"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
            for f in ("probe.swift", "report.md"):
                z.write(d / f, f)
        fields = {
            "name": name, "title": title, "area": area, "type": type_,
            "trackingIssue": sub.get("trackingIssue"),
            "attachment": str(zip_path), "attachmentBytes": zip_path.stat().st_size,
            "attachmentSHA256": sha256(zip_path), "descriptionChars": len(desc),
        }
        (out / "fields.json").write_text(json.dumps(fields, indent=2) + "\n")
        rows.append(fields)
        if clip == name:
            subprocess.run(["pbcopy"], input=desc.encode(), check=True)
            print(f"description of {name} copied to the clipboard")
    width = max(len(r["name"]) for r in rows)
    for r in rows:
        print(f"{r['name']:<{width}}  {r['area']:<16} {r['attachmentBytes']:>6} B  "
              f"{r['descriptionChars']:>5} chars  {r['trackingIssue'].rsplit('/', 1)[-1]:>4}  {r['title']}")
    (out_root / "manifest.json").write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv)
