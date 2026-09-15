# Relative Poppler image URLs

Issue #9 is fixed by running each Poppler mode in its page output directory and supplying a
relative HTML basename. The comparison manifest records the exact command and working
directory. Generated HTML remains raw Poppler output; server containment and CSP remain intact.

The real Poppler regression consumes the committed image-bearing `scanned.pdf`, checks both
simple and positioned HTML under paths containing spaces, and serves each image through the
actual safe HTTP handler. It requires status 200 and exact asset bytes. The converter alone
is stubbed to isolate the preview defect. Missing Poppler produces an explicit test skip.
A separate test verifies child working-directory behavior and its manifest record.

[The negative baseline](negative-baseline.log) fails against `774452a` because simple HTML has
an absolute filesystem image URL. With the fix, the [fast gate](../warren-image-encoding/gate.log.gz)
passes 65 Swift tests, 51 Python tests and six PDF/EPUB checks. Existing traversal, symlink and
CSP protections are unchanged.

A real nine-page Warren excerpt comparison uses excerpt page 5 (original physical page 50),
with Poppler 26.04.0 on the [recorded Mac environment](../warren-image-encoding/identity.json).
[Identity](identity.json) pins the excerpt and changed harness sources.
[Commands](comparison.json), raw [simple HTML](simple.html) / [positioned HTML](positioned.html),
and [HTTP response identities](image-responses.json) record the result. All three generated
image references return HTTP 200 with exact bytes. The browser also loads both simple-mode
images with nonzero natural dimensions. The original page remains the fidelity reference:
Poppler's separation of scan background and foreground is not changed or qualified here.

Reproduce with a fresh output directory:

```sh
python3 measurements/gpo-warren-1964/prepare-excerpt.py \
  --pdf corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf --output /tmp/warren-relative-excerpt.pdf
scripts/compare-pdf-reflow.sh --pdf /tmp/warren-relative-excerpt.pdf \
  --pages 5 --output /tmp/warren-relative-review --no-ocr --serve
python3 -m unittest discover -s tools -p 'test_comparison.py' -v
```

Retained HTML files are evidence; their large referenced rasters are not committed. Use the
reproduction command to inspect the live comparison. This fix affects development tools only.
