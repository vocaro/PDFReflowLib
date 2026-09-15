import json, zipfile, xml.etree.ElementTree as ET, io, hashlib
from pathlib import Path
from PIL import Image, ImageChops
import argparse
parser=argparse.ArgumentParser(description="Check selected EPUB text/image preservation and FAA full-page raster proportions; requires Pillow.")
for flag in ['faa-evaluation','blue-book-evaluation','warren-evaluation','before-raster','after-raster','source-raster','output']:
    parser.add_argument('--'+flag, type=Path, required=True)
args=parser.parse_args()
OUT=args.output; OUT.mkdir(parents=True, exist_ok=False)
NS='{http://www.w3.org/1999/xhtml}'

def page_blocks(epub, target):
    found=[]
    with zipfile.ZipFile(epub) as z:
        for name in z.namelist():
            if not name.startswith('EPUB/chapter-') or not name.endswith('.xhtml'): continue
            root=ET.fromstring(z.read(name)); current=None
            for block in root.find(NS+'body'):
                markers=[int(e.get('id')[5:]) for e in block.iter() if e.get('id','').startswith('page-')]
                if markers: current=markers[-1]
                if current==target:
                    found.append(block)
    return found

def images(epub, blocks):
    return [str(Path('EPUB')/img.get('src')) for block in blocks for img in block.iter(NS+'img')]

faa=args.faa_evaluation/'faa-phak-8083-25c.epub'
blue=args.blue_book_evaluation/'cia-blue-book-14-1955.epub'
warren=args.warren_evaluation/'book.epub'
selected={}
for name,epub,targets in [('faa',faa,[121]),('blue-book',blue,[74,150]),('warren',warren,[1,9])]:
    selected[name]={}
    with zipfile.ZipFile(epub) as z:
        assert all('\ufffc' not in z.read(n).decode() for n in z.namelist() if n.endswith('.xhtml'))
        for page in targets:
            blocks=page_blocks(epub,page)
            paths=images(epub,blocks)
            assert paths, (name,page)
            selected[name][page]={'xhtml':'\n'.join(ET.tostring(b,encoding='unicode') for b in blocks),'images':paths}
            if name=='warren':
                assert not any(b.tag in [NS+'p',NS+'h2',NS+'pre'] and ''.join(b.itertext()).strip() for b in blocks)
                assert len(paths)==1
            if name in ['faa','blue-book']:
                (OUT/f'{name}-page-{page}.png').write_bytes(z.read(paths[-1]))
(OUT/'selected-pages.json').write_text(json.dumps(selected,indent=2)+'\n')

def bounds(path):
    im=Image.open(path).convert('RGB')
    ink=ImageChops.difference(im,Image.new('RGB',im.size,'white')).convert('L').point(lambda p:255 if p>20 else 0)
    box=ink.getbbox()
    return {'size':list(im.size),'inkBounds':list(box),'inkWidthFraction':(box[2]-box[0])/im.width,'inkHeightFraction':(box[3]-box[1])/im.height}

before=bounds(args.before_raster); after=bounds(args.after_raster); reference=bounds(args.source_raster)
assert abs(after['inkWidthFraction']-reference['inkWidthFraction'])<.01
assert abs(after['inkHeightFraction']-reference['inkHeightFraction'])<.01
assert before['inkWidthFraction']<after['inkWidthFraction']*.5
r={'faaPage121':{'before':before,'afterExplicitWholePageRender':after,'popplerSource':reference,'passed':True},
   'warrenExcerpt':{'textlessPages':[1,9],'sourcePages':[1,920],'reflowedPageCount':json.loads((args.warren_evaluation/'conversion-report.json').read_text())['reflowedPageCount'],'textlessPagesHaveOnlyImageAndSourceBoundary':True},
   'noObjectPlaceholdersInXHTML':['full FAA','full Blue Book','nine-page Warren excerpt'],
   'scope':'Selected EPUB assets/XHTML plus an explicit whole-page raster of FAA page 121. Page 121 now reflows with region images; the explicit raster exercises the historically affected fallback transform. Ink bounds qualify scaling, not transcription or full-book fidelity.'}
assert r['warrenExcerpt']['reflowedPageCount']==7
(OUT/'fidelity-checks.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r,indent=2))
