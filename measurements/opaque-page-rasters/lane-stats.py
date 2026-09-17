import json, pathlib, sys, zipfile

lane = pathlib.Path(sys.argv[1])
rows = []
for d in sorted(lane.iterdir()):
    r = d / 'result.json'
    if not r.is_dir() and r.exists():
        res = json.loads(r.read_text())
        epub = next(d.glob('*.epub'), None)
        entry = images = n = 0
        if epub:
            z = zipfile.ZipFile(epub)
            entry = sum(i.file_size for i in z.infolist())
            ims = [i for i in z.infolist() if i.filename.lower().endswith(('.png', '.jpg', '.jpeg'))]
            images = sum(i.file_size for i in ims)
            n = len(ims)
        g = res.get('memoryGate', {})
        rows.append({'case': d.name, 'seconds': round(res['conversionSeconds'], 1),
                     'epubBytes': res.get('outputBytes'), 'entryBytes': entry,
                     'imageBytes': images, 'images': n,
                     'peakRSS': g.get('lowestPeakRSSBytes') or res.get('converterPeakRSSBytes'),
                     'footprint': res.get('converterPeakPhysicalFootprintBytes')})
json.dump(rows, open(sys.argv[2], 'w'), indent=1)
for x in rows:
    print(f"{x['case']:38s} {x['seconds']:7.1f}s  entry {x['entryBytes']:>11}  "
          f"images {x['imageBytes']:>11} ({x['images']:>5})  rss {x['peakRSS']:>11}")
print('TOTAL seconds', round(sum(x['seconds'] for x in rows), 1),
      ' entry bytes', sum(x['entryBytes'] for x in rows),
      ' image bytes', sum(x['imageBytes'] for x in rows))
