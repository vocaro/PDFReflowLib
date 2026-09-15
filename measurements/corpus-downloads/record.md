# Corpus download verification

Python 3.14 development tooling; five manifest-pinned PDFs. `verification.json` identifies the
fetcher implementation and each exact source. `python3 Tools/fetch_corpus.py --all --cache-dir
/tmp/pdfreflow-download-verification` downloads all five into an initially empty cache. Each
file matches the owner-supplied original by byte count and SHA-256. The normal repository cache
also contains all five verified originals. Source PDFs are ignored and are not committed.

The direct algebra URL is supplied by the owner and hosted on MyOpenMath's S3 path. Government
sources use the official publisher URLs recorded in the manifest. Ownership/rights clearance
is recorded separately; algebra retains its CC BY 3.0 attribution. This checks availability and
exact identity, not document fidelity, future URL stability, or conversion performance.
