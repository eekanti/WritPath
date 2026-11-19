# Adds or replaces zones in traced.json: python -I add.py batch.json
# batch.json: { "<uiMapID>": { "name": "...", "roads": [[[x, y], ...], ...], "trails": [...], "note": "..." } }
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(here, 'traced.json')
data = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
batch = json.load(open(sys.argv[1], encoding='utf-8'))
for k, v in batch.items():
    data[str(k)] = v
json.dump(data, open(path, 'w', encoding='utf-8'), indent=1, sort_keys=True)
print(len(data), 'zones traced:', ', '.join(f"{data[k]['name']}" for k in sorted(data, key=int)))
