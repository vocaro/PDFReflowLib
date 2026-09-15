from pathlib import Path
import json,html
from PIL import Image
work=Path('/tmp/pdfreflow-encoding-experiment');out=work/'review';out.mkdir(exist_ok=True)
mapping=json.loads((work/'page-images.json').read_text());records=[]
# Same pixel crop for every codec; PNG review exports avoid a second JPEG encode.
for page in [21,50,100,890,910]:
 stem=Path(mapping[str(page)]).stem
 with Image.open(work/'png'/(stem+'.png')) as im:
  w,h=im.size;box=(int(w*.12),int(h*.085),int(w*.12)+620,int(h*.085)+280)
 records.append((f'page-{page}',f'Warren physical page {page}',stem,box))
for stem,label in [('control-table','Our Flag numeric table (cropped-region control)'),('control-fraction','Detached fraction (cropped-region control)')]:
 with Image.open(work/'png'/(stem+'.png')) as im:box=(0,0,im.width,im.height)
 records.append((stem,label,stem,box))
body=[];details=[]
for name,label,stem,box in records:
 body.append(f'<h2>{html.escape(label)}</h2><div class="row">')
 for mode,ext in [('png','png'),('q90','jpg'),('q95','jpg')]:
  source=work/mode/(stem+'.'+ext);dest=out/f'{name}-{mode}.png'
  with Image.open(source) as image:image.convert('RGB').crop(box).save(dest)
  body.append(f'<figure><figcaption>{mode.upper()} · same source pixels</figcaption><img src="{dest.name}" style="width:{box[2]-box[0]}px"></figure>')
  details.append({'sample':name,'label':label,'mode':mode,'sourceImage':str(source.relative_to(work)),'crop':list(box),'file':dest.name})
 body.append('</div>')
(out/'samples.json').write_text(json.dumps(details,indent=2)+'\n')
(out/'index.html').write_text('''<!doctype html><meta charset="utf-8"><title>Warren PNG/JPEG experiment</title><style>body{font:16px system-ui;margin:24px;background:#eee;color:#111}h1{font-size:24px}h2{font-size:18px;margin-top:40px}.row{display:flex;gap:20px;overflow:auto}figure{margin:0;flex:none}figcaption{padding:8px;background:white}img{display:block}button{padding:8px}body.zoom img{width:calc(var(--w)*2)!important}</style><h1>PNG / JPEG quality 90 / JPEG quality 95</h1><p>Identical 180-DPI source rasters. These crops retain decoded pixels and introduce no additional JPEG compression. Browser zoom can enlarge the comparison. Global pixel-error scores do not prove transcription accuracy.</p>'''+''.join(body))
