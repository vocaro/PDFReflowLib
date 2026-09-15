from pathlib import Path
import json,gzip,shutil,zipfile,hashlib,re,collections,sys
work=Path(sys.argv[1]);dest=Path(sys.argv[2])
summary={};assets={};texts={}
for name in ['jpeg-references','no-references']:
 d=work/name;out=dest/name;out.mkdir()
 result=json.loads((d/'result.json').read_text());report=json.loads((d/'conversion-report.json').read_text())
 for path in d.iterdir():
  if path.suffix=='.epub':continue
  (out/(path.name+'.gz')).write_bytes(gzip.compress(path.read_bytes(),mtime=0))
 shutil.copyfile(work/(name+'.sh'),out/'launcher.sh')
 raw=hashlib.sha256((d/'result.json').read_bytes()).hexdigest()
 result.pop('conversionReport', None)  # Complete warnings remain in the compressed raw reports.
 result['rawResultSHA256']=raw
 result['options']={'referenceImages':'automatic' if name=='jpeg-references' else 'never','fullPageImageEncoding':{'jpegQuality':0.9},'regionImageEncoding':'png','maximumOutputBytes':9223372036854775807 if name=='jpeg-references' else 536870912,'maximumEPUBBytes':536870912 if name=='jpeg-references' else 67108864}
 result['launcherSHA256']=result.pop('converterSHA256')
 result['converterSHA256']=json.loads((dest/'identity.json').read_text())['converter']['sha256']
 result['receiptNote']='Effective CLI options are supplied by the exec launcher; the preserved raw evaluator receipt assumes library defaults. This derived receipt records the effective options and underlying implementation separately.'
 (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 epub=d/'gpo-warren-1964.epub'
 with zipfile.ZipFile(epub) as z:
  import xml.etree.ElementTree as ET
  ns={'o':'http://www.idpf.org/2007/opf','h':'http://www.w3.org/1999/xhtml'}
  opf=ET.fromstring(z.read('EPUB/package.opf'))
  manifest={e.get('id'):e.get('href') for e in opf.findall('o:manifest/o:item',ns)}
  pages=[];text=[]
  for item in opf.findall('o:spine/o:itemref',ns):
   tree=ET.fromstring(z.read('EPUB/'+manifest[item.get('idref')]))
   for node in tree.iter():
    if 'pagebreak' in node.get('{http://www.idpf.org/2007/ops}type','').split():pages.append(node.get('id'))
    if node.tag in ['{'+ns['h']+'}'+t for t in ['p','pre','h1','h2']]:text.append(''.join(node.itertext()))
  assert pages==['page-'+str(i) for i in range(1,921)]
  texts[name]=re.sub(r'[\s\u00ad-]+','',''.join(text))
  images=[e.filename for e in z.infolist() if e.filename.startswith('EPUB/images/')]
  assets[name]=collections.Counter(hashlib.sha256(z.read(n)).hexdigest() for n in images)
  summary[name]={'epubBytes':epub.stat().st_size,'entryBytes':sum(e.file_size for e in z.infolist()),'pageCount':len(pages),'imageCount':len(images),'pngCount':sum(n.endswith('.png') for n in images),'jpegCount':sum(n.endswith('.jpg') for n in images),'reflowedPageCount':report['reflowedPageCount'],'recognizedPageCount':report['recognizedPageCount'],'warningCounts':dict(collections.Counter(w['code'] for w in report['warnings'])),'canonicalTextSHA256':hashlib.sha256(texts[name].encode()).hexdigest()}
assert texts['jpeg-references']==texts['no-references'],'Text mismatch beyond whitespace/hyphen joins'
assert not (assets['no-references']-assets['jpeg-references']), 'Remaining images differ'
summary['checks']={'all920SourceAnchors':True,'canonicalTextEqual':True,'canonicalization':'Paragraph/preformatted/heading text excluding figure captions, with whitespace, ASCII hyphens and soft hyphens removed to allow cross-page joins. Not exact body-byte equality.','remainingImagesByteIdentical':True}
(dest/'warren-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
