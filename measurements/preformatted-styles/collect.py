import sys,zipfile,xml.etree.ElementTree as E,json,hashlib,collections
import argparse,gzip,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'tools'))
from check_corpus_content import read_pages
parser=argparse.ArgumentParser(description='Compare complete corpus outputs; only inline styles inside preformatted blocks may differ.')
for name in ('before','after','logs','output'):
 parser.add_argument('--'+name,type=Path,required=True)
args=parser.parse_args()
before,after=args.before,args.after
args.output.mkdir(parents=True,exist_ok=True)
summary=json.loads((after/'summary.json').read_text())
assert summary['passed'] and len(summary['results'])==8 and not summary['notRun']
rows=[]
def save(name,value):
 (args.output/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def digest(path):
 return hashlib.sha256(path.read_bytes()).hexdigest()

def semantic(epub):
 with zipfile.ZipFile(epub) as z:
  opf=E.fromstring(z.read('EPUB/package.opf'));ns='{http://www.idpf.org/2007/opf}'
  names={e.get('id'):e.get('href') for e in opf.find(ns+'manifest')};blocks=[];page=0
  for ref in opf.find(ns+'spine'):
   for e in E.fromstring(z.read('EPUB/'+names[ref.get('idref')])).find('{http://www.w3.org/1999/xhtml}body'):
    kind=e.tag.split('}')[1]
    if e.get('id','').startswith('page-'):page=int(e.get('id')[5:])
    # Strip style tags ONLY inside preformatted blocks; all other structure is frozen.
    if kind=='pre':
     assert all(child.tag.split('}')[1] in ('pre','strong','em','sup','sub','span') for child in e.iter())
     blocks.append((page,kind,''.join(e.itertext())))
    else: blocks.append((page,kind,E.tostring(e,encoding='unicode').strip()))
  images={n:hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if n.startswith('EPUB/images/')}
 return blocks,images
for p in sorted(after.glob('*/*.epub')):
 case=p.parent.name;old=before/case/p.name
 left,lm=read_pages(old);right,rm=read_pages(p);assert lm==rm
 lb,li=semantic(old);rb,ri=semantic(p);assert lb==rb,case
 assert li==ri,case
 changed=[];added=[]
 for number in left:
  l,r=left[number].copy(),right[number].copy();ls=l.pop('scripts');rs=r.pop('scripts');assert l==r,(case,number)
  lc=collections.Counter(json.dumps(s,sort_keys=True) for s in ls);rc=collections.Counter(json.dumps(s,sort_keys=True) for s in rs)
  assert not lc-rc,(case,number,'lost script')
  if lc!=rc:
   changed.append(number);added.extend({'page':number,**json.loads(s)} for s,count in (rc-lc).items() for _ in range(count))
 rows.append({'case':case,'pages':len(left),'imageCount':len(li),'allImageBytesIdentical':True,'allNonPreformattedBlocksIdentical':True,'allPlainTextAndBlockOrderIdentical':True,'pagesWithNewScripts':changed,'addedScripts':added})
assert len(rows)==8
for row in rows:
 case=row['case'];folder=args.output/case;folder.mkdir(exist_ok=True)
 (folder/'added-scripts.json.gz').write_bytes(gzip.compress(json.dumps(row.pop('addedScripts'),ensure_ascii=False,indent=2).encode(),mtime=0))
 for filename in ('result.json','conversion-report.json','content-assessment.json','progress.log','memory-samples.json','epubcheck.log'):
  (folder/(filename+'.gz')).write_bytes(gzip.compress((after/case/filename).read_bytes(),mtime=0))
 row['addedScriptCount']=len(json.loads(gzip.decompress((folder/'added-scripts.json.gz').read_bytes())))
 row['beforeEPUBSHA256']=digest(before/case/(case+'.epub'))
 row['afterEPUBSHA256']=digest(after/case/(case+'.epub'))
for case,numbers in [('wallace-algebra-2010',[26]),('faa-phak-8083-25c',[211,212])]:
 l,_=read_pages(before/case/(case+'.epub'));r,_=read_pages(after/case/(case+'.epub'))
 save(case+'-reviewed-pages.json',{str(n):{'before':l[n],'after':r[n]} for n in numbers})
save('comparison-summary.json',rows)
save('corpus-summary.json',summary)
paths=sorted(p for base in ('Sources','Tests','tools') for p in (root/base).rglob('*')
             if p.is_file() and p.suffix in ('.swift','.py','.json','.pdf'))
paths += [root/name for name in ('Package.swift','Package.resolved','corpus/manifest.json','corpus/regressions.json','scripts/check-all.sh')]
save('identity.json',{'baseRevision':'0fd4728','producerSHA256':digest(Path(__file__)),
 'workingTreeSHA256':{str(p.relative_to(root)):digest(p) for p in paths},
 'platform':subprocess.check_output(['sw_vers'],text=True).strip(),
 'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip()})
for name in ('before-tests.log','before-content.json','before-faa-content.json','final-gate.log','final-ios-tests.log'):
 (args.output/(name+'.gz')).write_bytes(gzip.compress((args.logs/name).read_bytes(),mtime=0))
print(json.dumps(rows,indent=2))
