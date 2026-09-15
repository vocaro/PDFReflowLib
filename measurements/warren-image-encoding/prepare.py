from pathlib import Path
import json,zipfile,xml.etree.ElementTree as ET
work=Path('/tmp/pdfreflow-encoding-experiment')
report=json.loads((work/'conversion-report.json').read_text())
fallback={w['page'] for w in report['warnings'] if w['code']=='pageImageFallback'}
html='{http://www.w3.org/1999/xhtml}';epub='{http://www.idpf.org/2007/ops}';opf='{http://www.idpf.org/2007/opf}'
images={};current=None
with zipfile.ZipFile(work/'warren-png.epub') as z:
 package=ET.fromstring(z.read('EPUB/package.opf'));manifest={e.get('id'):e.get('href') for e in package.find(opf+'manifest')}
 for ref in package.find(opf+'spine'):
  name='EPUB/'+manifest[ref.get('idref')]
  for e in ET.fromstring(z.read(name)).iter():
   if 'pagebreak' in e.get(epub+'type','').split():current=int(e.get('id').split('-')[1])
   if e.tag==html+'figure':
    caption=e.find(html+'figcaption').text;image=e.find(html+'img').get('src')
    if caption==f'Original page {current}' or current in fallback:
     assert current not in images,current
     images[current]='EPUB/'+image
 assert set(images)==set(range(1,921)),len(images)
 (work/'png').mkdir();(work/'q90').mkdir();(work/'q95').mkdir()
 for im in images.values():(work/'png'/Path(im).name).write_bytes(z.read(im))
paths=['png/'+Path(images[p]).name for p in sorted(images)]
for name, source in [('control-table', 'measurements/three-fidelity-fixes/flag27-table-output.png'), ('control-fraction', 'measurements/fractions-and-invisible-text/fraction-output.png')]:
 (work/'png'/(name+'.png')).write_bytes(Path(source).read_bytes()); paths.append('png/'+name+'.png')
(work/'images.json').write_text(json.dumps(paths)+'\n')
(work/'page-images.json').write_text(json.dumps(images,indent=2)+'\n')
print('Prepared',len(images),'full-page images; remaining image regions stay PNG.')
