#!/usr/bin/env python3
"""Generate original synthetic PDFs. Requires ReportLab, Pillow and pdftoppm; no fetched content.

The built-in PDF fonts are referenced, not redistributed as embedded font programs.
Regeneration updates the fixture identity manifest in the same operation.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageDraw
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

from pdfreflow_tools.corpus import FIXTURES as DESTINATION, identity
from pdfreflow_tools.encryption import encrypted_pdf


def page(c, lines, x=54, y=690, size=12, step=18, font="Helvetica"):
    c.setFont(font, size)
    for line in lines:
        c.drawString(x, y, line)
        y -= step


# Fixtures that are locked, and the password each one takes.
PASSWORDS = {"encrypted.pdf": {"password": "reflow"}}


def create(name):
    return canvas.Canvas(str(DESTINATION / name), pagesize=(612, 792),
                         invariant=1, pageCompression=1)


def generate(renderer):
    DESTINATION.mkdir(parents=True, exist_ok=True)
    c = create("prose.pdf")
    c.setTitle("A Small Book of Conversion")
    for number in range(1, 4):
        page(c, ["PDF REFLOW TEST BOOK"], y=766, size=9)
        page(c, [str(number)], y=26, size=9)
        if number == 1:
            page(c, ["A Small Book of Conversion"], y=722, size=22)
            page(c, ["A conversion should preserve words and paragraphs.",
                     "This paragraph uses ordinary hard-wrapped lines that",
                     "belong together in a single reflowable paragraph."])
            page(c, ["The next paragraph describes a reliable conver-",
                     "sion without inventing or dropping any words."], y=600)
            page(c, ["A well-known method remains well-",
                     "known when its real hyphen crosses a line."], y=540)
            page(c, ["A reader can continue across a page boundary without"], y=76)
        elif number == 2:
            page(c, ["losing the original sentence or its source-page anchor."], y=720)
            page(c, ["Second Section"], y=660, size=20)
            page(c, ["The second section has a distinct paragraph."], y=620)
        else:
            page(c, ["Third Section"], y=720, size=20)
            page(c, ["The last page confirms that repeated furniture is removable.",
                     "Every substantive line stays inside the resulting book."], y=678)
        c.showPage()
    c.save()

    c = create("columns.pdf")
    page(c, ["Two Columns, One Reading Order"], y=730, size=21)
    page(c, ["LEFT FIRST begins the left column.", "Its next line belongs to the left.",
             "LEFT LAST ends this column."], x=42, y=660, size=11)
    page(c, ["RIGHT FIRST begins the right column.", "Its next line belongs to the right.",
             "RIGHT LAST ends this column."], x=332, y=660, size=11)
    c.showPage(); c.save()

    c = create("graphics.pdf")
    page(c, ["Illustrations and a Table"], y=730, size=22)
    page(c, ["Text before the illustrated region remains searchable."], y=688)
    picture = Image.new("RGB", (160, 100), "#dfefff")
    draw = ImageDraw.Draw(picture)
    draw.ellipse((30, 20, 85, 75), fill="#235fb1")
    draw.rectangle((100, 20, 140, 75), fill="#ebad2e")
    # A nested Form XObject exercises the transform stack rather than just top-level images.
    c.beginForm("diagram", 0, 0, 260, 160)
    c.drawImage(ImageReader(picture), 0, 0, width=160, height=100)
    c.setStrokeColorRGB(0.1, 0.2, 0.6)
    c.line(165, 50, 220, 50)
    c.line(210, 60, 220, 50)
    c.line(210, 40, 220, 50)
    page(c, ["OUTPUT"], x=170, y=80, size=10)
    c.endForm()
    c.saveState(); c.translate(54, 500); c.doForm("diagram"); c.restoreState()
    page(c, ["Figure 1. A raster illustration with vector labels."], y=475, size=10)
    c.setStrokeColorRGB(0, 0, 0)
    for y in [320, 350, 380]: c.line(54, y, 360, y)
    for x in [54, 210, 360]: c.line(x, 320, x, 380)
    page(c, ["Quantity", "12"], x=65, y=360, step=30)
    page(c, ["Description", "sample units"], x=221, y=360, step=30)
    page(c, ["Text after the table also remains searchable."], y=260)
    page(c, ["E = mc"], x=200, y=195, size=18)
    page(c, ["2"], x=257, y=203, size=11)
    page(c, ["A displayed formula keeps its superscript placement."], y=155)
    c.showPage(); c.save()

    c = create("lists-code.pdf")
    page(c, ["Lists and Code"], y=730, size=22)
    page(c, ["1. Keep the first item.", "2. Keep the second item."], y=680)
    page(c, ["if value < 3:", "    print(value)", "return value"], y=570, font="Courier")
    page(c, ["Markup is source text: <script>alert('no')</script> & data."], y=450, size=10)
    text = c.beginText(54, 390)
    text.setFont("Helvetica", 12); text.textOut("Keep ")
    text.setFont("Helvetica-Bold", 12); text.textOut("bold")
    text.setFont("Helvetica", 12); text.textOut(" and ")
    text.setFont("Helvetica-Oblique", 12); text.textOut("italic")
    text.setFont("Helvetica", 12); text.textOut(" emphasis.")
    c.drawText(text)
    c.showPage(); c.save()

    # Links, which convert to EPUB anchors (#247): an external URL over part of a line, a
    # mailto, a scheme that must be dropped, a cross-reference to a later page, a link covering
    # two lines of one sentence, and a link over a picture rather than over text.
    c = create("links.pdf")

    def word_rect(line, word, x=54, y=0, size=12):
        """The rectangle around `word` inside `line`, drawn at (x, y) in Helvetica `size`."""
        start = x + c.stringWidth(line[:line.index(word)], "Helvetica", size)
        return (start, y - 2, start + c.stringWidth(word, "Helvetica", size), y + size)

    page(c, ["Links and Where They Point"], y=730, size=20)
    specification = "The EPUB specification is published by the W3C."
    page(c, [specification], y=690)
    c.linkURL("https://www.w3.org/TR/epub-33/", word_rect(specification, "published", y=690), relative=0)
    correspondence = "Write to reader@example.org with corrections."
    page(c, [correspondence], y=660)
    c.linkURL("mailto:reader@example.org", word_rect(correspondence, "reader@example.org", y=660), relative=0)
    script = "A script link must never reach the output."
    page(c, [script], y=630)
    c.linkURL("javascript:alert('no')", word_rect(script, "script link", y=630), relative=0)
    crossing = ["This sentence about the second page runs across",
                "two lines and the link covers both of them."]
    page(c, crossing, y=600)
    c.linkAbsolute("second page", "second-page",
                   (54, 582 - 2, 54 + max(c.stringWidth(line, "Helvetica", 12) for line in crossing), 600 + 12))
    picture = Image.new("RGB", (120, 60), (250, 250, 250))
    draw = ImageDraw.Draw(picture)
    draw.rectangle([10, 10, 110, 50], fill=(40, 90, 200))
    c.drawImage(ImageReader(picture), 54, 440, width=240, height=120)
    c.linkAbsolute("linked figure", "second-page", (54, 440, 294, 560))
    page(c, ["Figure 1. A picture the source links."], y=420, size=10)
    c.showPage()
    c.bookmarkPage("second-page")
    page(c, ["The Second Page"], y=730, size=20)
    page(c, ["This is where the cross-reference and the figure both point."], y=690)
    c.showPage(); c.save()

    c = create("rotated.pdf")
    c.setPageRotation(90)
    page(c, ["Rotated source page"], y=500, size=24)
    page(c, ["The original orientation must remain readable."], y=450)
    c.showPage(); c.save()

    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "scan-source.pdf"
        c = canvas.Canvas(str(source), pagesize=(612, 792), invariant=1)
        page(c, ["Scanned Reading Sample"], y=720, size=24)
        page(c, ["This page contains a clear scanned paragraph.",
                 "The words should become reflowable text.",
                 "The original page preserves the little blue square."], y=660, size=16, step=26)
        c.setFillColorRGB(0.1, 0.3, 0.8); c.rect(54, 420, 80, 80, fill=1)
        c.showPage(); c.save()
        prefix = Path(tmp) / "scan"
        subprocess.run([renderer, "-singlefile", "-r", "150", "-png", str(source), str(prefix)], check=True)
        c = create("scanned.pdf")
        c.drawImage(str(prefix) + ".png", 0, 0, width=612, height=792)
        c.showPage(); c.save()

    # A locked document. ReportLab writes no encryption this old, and the standard security
    # handler at revision 2 is the one a stdlib MD5 and RC4 can produce, so it is built by hand
    # (#252); its password is `reflow`, recorded beside its identity in the manifest.
    (DESTINATION / "encrypted.pdf").write_bytes(encrypted_pdf())

    manifest = {
        "provenance": "Original synthetic text and drawings; no external documents or embedded font programs.",
        "fixtures": [{"file": p.name, **identity(p), **PASSWORDS.get(p.name, {})}
                     for p in sorted(DESTINATION.glob("*.pdf"))],
    }
    (DESTINATION / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--renderer", default="pdftoppm")
    generate(parser.parse_args().renderer)
