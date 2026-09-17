#!/usr/bin/env python3
"""Writes an instrumented copy of GraphicsReader.swift into OUTDIR: every `unsupported = true`
records its source line, and the operation counter is exported, for diagnose-main.swift.

  python3 measurements/dga-and-fallback-reverify/tools/instrument.py OUTDIR
  cp measurements/dga-and-fallback-reverify/tools/{diagnose-main.swift,survey.py} OUTDIR/
  mv OUTDIR/diagnose-main.swift OUTDIR/main.swift
  xcrun swiftc -O -module-cache-path OUTDIR/mc OUTDIR/GraphicsReader.swift OUTDIR/main.swift \
    Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
    Sources/PDFReflowLib/ConversionTypes.swift -o OUTDIR/diag
  OUTDIR/diag corpus/cache/faa-h-8083-25c.pdf 226,286,288,302,348,448   # DUMP=1 lists regions
  python3 OUTDIR/survey.py > operation-survey.txt                     # every cached corpus PDF
"""
import re, sys
from pathlib import Path
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
lines = Path('Sources/PDFReflowLib/GraphicsReader.swift').read_text().split('\n')
result = []
for number, line in enumerate(lines, 1):
    line = re.sub(r'\b(s\.)?unsupported = true', lambda m: f'{m.group(0)}; Diag.hit({number})', line)
    line = line.replace('return Result(regions: [], unsupported: true)', f'Diag.hit({number}); return Result(regions: [], unsupported: true)')
    line = line.replace('            operations += 1', '            operations += 1; Diag.ops = operations')
    result.append(line)
(out / 'GraphicsReader.swift').write_text('\n'.join(result))
