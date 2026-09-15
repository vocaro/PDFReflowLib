from pathlib import Path
import json,zipfile,hashlib,xml.etree.ElementTree as ET
work=Path('/tmp/pdfreflow-encoding-experiment')
images=json.loads((work/'page-images.json').read_text());selected=set(images.values())
ns={'o':'http://www.idpf.org/2007/opf','h':'http://www.w3.org/1999/xhtml'}
def describe(path):
 with zipfile.ZipFile(path) as z:
  opf=ET.fromstring(z.read('EPUB/package.opf'))
  mapping={x.get('id'):x.get('href') for x in opf.findall('o:manifest/o:item',ns)}
  pages=[];texts=[]
  for ref in opf.findall('o:spine/o:itemref',ns):
   tree=ET.fromstring(z.read('EPUB/'+mapping[ref.get('idref')]))
   texts+=list(tree.find('h:body',ns).itertext())
   pages+=[x.get('id') for x in tree.iter() if 'pagebreak' in x.get('{http://www.idpf.org/2007/ops}type','').split()]
  assert pages==[f'page-{p}' for p in range(1,921)]
  for item in opf.findall('o:manifest/o:item',ns):assert 'EPUB/'+item.get('href') in z.namelist()
  return {'epubBytes':path.stat().st_size,'entryBytes':sum(i.file_size for i in z.infolist()),'imageBytes':sum(i.file_size for i in z.infolist() if i.filename.startswith('EPUB/images/')),'imageCount':sum(i.filename.startswith('EPUB/images/') for i in z.infolist()),'pageCount':len(pages),'bodyTextSHA256':hashlib.sha256(''.join(texts).encode()).hexdigest(),'epubSHA256':hashlib.sha256(path.read_bytes()).hexdigest()}
results={'png':describe(work/'warren-png.epub')}
for quality in [90,95]:
 output=work/f'warren-q{quality}.epub'
 with zipfile.ZipFile(work/'warren-png.epub') as source,zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as target:
  for item in source.infolist():
   name=item.filename
   if name in selected:
    jpg=work/f'q{quality}'/(Path(name).stem+'.jpg');target.write(jpg,name.removesuffix('.png')+'.jpg')
   else:
    data=source.read(name)
    if name.endswith('.xhtml') or name=='EPUB/package.opf':
     for image in selected:
      old=image.removeprefix('EPUB/').encode();new=old.removesuffix(b'.png')+b'.jpg'
      if name.endswith('.xhtml'):data=data.replace(b'src="'+old+b'"',b'src="'+new+b'"')
      else:data=data.replace(b'href="'+old+b'" media-type="image/png"',b'href="'+new+b'" media-type="image/jpeg"')
    target.writestr(name,data,compress_type=zipfile.ZIP_STORED if name=='mimetype' else zipfile.ZIP_DEFLATED)
 results[f'q{quality}']=describe(output)
 assert results[f'q{quality}']['bodyTextSHA256']==results['png']['bodyTextSHA256']
 # Every untouched asset retains exact bytes; page images have only the reviewed codec change.
 with zipfile.ZipFile(work/'warren-png.epub') as source,zipfile.ZipFile(output) as target:
  for name in source.namelist():
   if name.startswith('EPUB/images/') and name not in selected:assert source.read(name)==target.read(name)
(work/'package-results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
