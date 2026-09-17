import subprocess, sys, os, tempfile, glob
import numpy as np
from PIL import Image
C = '/Users/trevorharmon/Development/PDFReflowLib/corpus/cache/'
books = {'faa': 'faa-h-8083-25c.pdf', 'wallace': 'Beginning_and_Intermediate_Algebra.pdf',
         'warren': 'GPO-WARRENCOMMISSIONREPORT.pdf', '911': 'GPO-911REPORT.pdf', 'fed': 'the-fed-explained.pdf',
         'dga': 'DGA.pdf', 'noaa': 'noaa_61592_DS1.pdf', 'flag': 'CDOC-108hdoc97.pdf',
         'bluebook': 'CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf', 'cdc': 'cdc_6023_DS1.pdf',
         'nbs': 'jresv82n3p173_A1b.pdf', 'replay': '2311.07842v1.pdf', 'usgs': 'mcs2025-copper.pdf',
         'scotus': '22-451_7m58.pdf', 'census': 'rrs2002-01.pdf'}
sel = sys.argv[1:] or list(books)
for b in sel:
    f = C + books[b]
    txt = subprocess.run(['pdftotext', '-layout', f, '-'], capture_output=True, text=True, errors='replace').stdout.split('\f')
    cands = [i + 1 for i, t in enumerate(txt[:-1]) if len(''.join(t.split())) <= 6]
    print(b, len(txt) - 1, 'candidates', len(cands), flush=True)
    with tempfile.TemporaryDirectory() as d:
        for p in cands:
            subprocess.run(['pdftoppm', '-r', '36', '-gray', '-f', str(p), '-l', str(p), f, d + '/p'], check=True)
            fn = glob.glob(d + '/p*')[0]
            a = np.asarray(Image.open(fn)).astype(int)
            os.remove(fn)
            print('  ', p, repr(''.join(txt[p - 1].split())), 'ink<250', round(float((a < 250).mean()), 5),
                  'ink<128', round(float((a < 128).mean()), 5), 'min', int(a.min()), flush=True)
