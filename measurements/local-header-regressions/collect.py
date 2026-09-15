"""Collect completed gate receipts and compare against the retained client-policy baseline."""
import collections, difflib, gzip, hashlib, json, subprocess, sys, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2] if Path(__file__).resolve().parent.name=='local-header-regressions' else Path.cwd()
sys.path.insert(0,str(ROOT/'tools'))
from check_corpus_content import read_pages

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def packed(source,target): target.write_bytes(gzip.compress(source.read_bytes(),mtime=0))
def image_hashes(path):
 with zipfile.ZipFile(path) as z:
  return collections.Counter(hashlib.sha256(z.read(i)).hexdigest() for i in z.namelist() if i.startswith('EPUB/images/'))

def main():
 import argparse
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True)
 p.add_argument('--logs',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
 args=p.parse_args();out=args.output;out.mkdir(parents=True,exist_ok=True)
 summary=json.loads((args.after/'summary.json').read_text());assert summary['passed']
 rows=[]
 differences=[]
 for case in summary['results']:
  name=case['case'];before=args.before/name;after=args.after/name
  book=name+'.epub';old=json.loads((before/'conversion-report.json').read_text());new=json.loads((after/'conversion-report.json').read_text())
  old_pages,old_markers=read_pages(before/book);new_pages,new_markers=read_pages(after/book)
  assert old_markers==new_markers
  changes=[]
  for number in old_pages:
   a=old_pages[number]['text'];b=new_pages[number]['text']
   if a==b:continue
   x=a.split();y=b.split()
   edits=[{'before':' '.join(x[i:j]),'after':' '.join(y[k:l])}
          for tag,i,j,k,l in difflib.SequenceMatcher(None,x,y,autojunk=False).get_opcodes() if tag!='equal']
   changes.append({'page':number,'diff':edits})
  if name not in {'gpo-911-2004', 'fed-explained-2021'}:
   assert not changes, f'Unexpected semantic-text change needs review: {name}'
  differences.append({'case':name,'changes':changes})
  equal_images=image_hashes(before/book)==image_hashes(after/book)
  assert equal_images, f'Image-byte change needs review: {name}'
  rows.append({'case':name,'beforeResultSHA256':sha(before/'result.json'),
               'beforeEPUBSHA256':sha(before/book),'afterEPUBSHA256':sha(after/book),
               'sameImageBytesAsMultiset':equal_images,'beforeImages':old['imageCount'],'afterImages':new['imageCount'],
               'beforeReflowedPages':old['reflowedPageCount'],'afterReflowedPages':new['reflowedPageCount'],
               'changedTextPages':sum(old_pages[n]['text']!=new_pages[n]['text'] for n in old_pages),
               'beforeHeadings':sum(len(x['headings']) for x in old_pages.values()),
               'afterHeadings':sum(len(x['headings']) for x in new_pages.values()),
               'beforeFurniturePages':sum(w['code']=='furnitureRemoved' for w in old['warnings']),
               'afterFurniturePages':sum(w['code']=='furnitureRemoved' for w in new['warnings'])})
  dest=out/name;dest.mkdir(exist_ok=True)
  for f in ['result.json','conversion-report.json','content-assessment.json','progress.log','memory-samples.json','epubcheck.log']:
   if (after/f).exists():packed(after/f,dest/(f+'.gz'))
  if name=='gpo-911-2004':
   selected={str(n):{'before':old_pages[n],'after':new_pages[n]} for n in [19,20,21,65,67,471,472]}
   (out/'reviewed-pages.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2)+'\n')
 files=sorted(p for base in ['Sources','Tests','tools'] for p in (ROOT/base).rglob('*') if p.is_file() and p.suffix in ('.swift','.py','.json','.pdf'))
 files += [ROOT/'Package.swift',ROOT/'Package.resolved',ROOT/'corpus/regressions.json',ROOT/'corpus/manifest.json',ROOT/'scripts/check-all.sh']
 identity={'producerSHA256':sha(Path(__file__)), 'baseRevision':'cd28856','workingTreeSHA256':{str(p.relative_to(ROOT)):sha(p) for p in files},
           'platform':subprocess.check_output(['sw_vers'],text=True).strip(),
           'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
           'comparisonBaseline':'measurements/client-options/record.md; retained complete default-policy corpus outputs',
           'baselineTestScope':'before-tests.log captures the initial five header tests; shifted-folio-before.log captures the later source-derived safeguard before its fix' }
 (out/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
 (out/'corpus-differences.json.gz').write_bytes(gzip.compress((json.dumps(differences,indent=2,ensure_ascii=False)+'\n').encode(),mtime=0))
 (out/'comparison-summary.json').write_text(json.dumps(rows,indent=2)+'\n')
 (out/'corpus-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 for f in ['before-tests.log','before-content.json','shifted-folio-before.log','release-gate.log','release-ios-tests.log','flag-intermediate-content.json','flag-original-content.json','blue-intermediate-content.json','blue-original-content.json']:
  packed(args.logs/f,out/(f+'.gz'))
 print(json.dumps(rows,indent=2))
if __name__=='__main__': main()
