# Draws traced.json on the zone maps for review: one image per zone plus index.html, in review/ next to this file.
# python -I review.py [uiMapID ...]   (no ids: every traced zone)
import json, os, sys, html, time, base64, io
from PIL import Image, ImageDraw
here = os.path.dirname(os.path.abspath(__file__))
MAPS = r'C:\dev\WritPath_Collector\review\maps'
AREA = {1411:14,1412:215,1413:17,1416:36,1417:45,1418:3,1419:4,1420:85,1421:130,1422:28,1423:139,1424:267,1425:47,1426:1,
        1427:51,1428:46,1429:12,1430:41,1431:10,1432:38,1433:44,1434:33,1435:8,1436:40,1437:11,1438:141,1439:148,1440:331,
        1441:400,1442:406,1443:405,1444:357,1445:15,1446:440,1447:16,1448:361,1449:490,1450:493,1451:1377,1452:618}
data = json.load(open(os.path.join(here, 'traced.json'), encoding='utf-8'))
out = os.path.join(here, 'review'); os.makedirs(os.path.join(out, 'img'), exist_ok=True)
only = [a for a in sys.argv[1:]]
embedded = {}   # every image inside the page itself, so it opens anywhere (a single-file snapshot too)
def base(m):
    a = AREA.get(int(m))
    p = os.path.join(MAPS, f'{a}.jpg') if a else os.path.join(MAPS, 'forever', f'{m}.jpg')
    return Image.open(p).convert('RGB')
for m, z in data.items():
    if only and m not in only: continue
    im = base(m); W, H = im.size; d = ImageDraw.Draw(im, 'RGBA')
    def P(q): return (q[0] / 100 * W, q[1] / 100 * H)
    for kind, col in (('trails', (60, 170, 255)), ('roads', (235, 40, 40))):
        for line in z.get(kind, []):
            pts = [P(q) for q in line]
            d.line(pts, fill=col + (230,), width=4)
            for q in pts: d.ellipse([q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3], fill=(255, 255, 255, 255), outline=col + (255,))
    im.save(os.path.join(out, 'img', f'{m}.jpg'), quality=85)
    small = im.resize((W * 3 // 4, H * 3 // 4)); buf = io.BytesIO(); small.save(buf, 'JPEG', quality=78)
    embedded[m] = 'data:image/jpeg;base64,' + base64.b64encode(buf.getvalue()).decode()
secs = []
for m in sorted(data, key=lambda k: data[k]['name']):
    z = data[m]
    n = sum(len(l) for l in z.get('roads', [])) , sum(len(l) for l in z.get('trails', []))
    note = f"<p class=note>{html.escape(z['note'])}</p>" if z.get('note') else ''
    secs.append(f'<section id="z{m}"><h2>{html.escape(z["name"])} <small>{m} · {len(z.get("roads", []))} roads, {len(z.get("trails", []))} trails</small></h2>{note}<img src="{embedded.get(m) or ('img/' + m + '.jpg')}" alt="{html.escape(z['name'])}"></section>')
nav = ' '.join(f'<a href="#z{m}">{html.escape(data[m]["name"])}</a>' for m in sorted(data, key=lambda k: data[k]['name']))
open(os.path.join(out, 'index.html'), 'w', encoding='utf-8').write(f'''<!doctype html><meta charset=utf-8><title>Traced roads review</title>
<style>body{{background:#15161a;color:#e8e8ea;font:14px/1.45 system-ui,sans-serif;max-width:1060px;margin:24px auto;padding:0 16px}}
img{{width:100%;border:1px solid #333}} a{{color:#e0a654}} small{{color:#999}} .note{{color:#f0c080}}</style>
<h1>Traced roads ({len(data)} zones)</h1><p>Red: roads, blue: trails. Traced by eye from the classic zone maps; check each against the map and note what's wrong.</p>
<p>{nav}</p>{''.join(secs)}''')
print('review:', os.path.join(out, 'index.html'))
