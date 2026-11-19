# Writes WritPathRoads.lua (shipped with the addon) from traced.json: python -I research/roads/make.py
import json, os
here = os.path.dirname(os.path.abspath(__file__))
d = json.load(open(os.path.join(here, 'traced.json'), encoding='utf-8'))
def line(pts): return '{ ' + ', '.join(f'{x:g}, {y:g}' for x, y in pts) + ' }'
out = ['-- WritPath: roads and trails traced by hand from the classic zone maps (Forever\'s own zones from guildorder.com\'s',
       '-- WoW: Forever maps), 2026-11-19, reviewed by the author. Positions on each zone\'s map (0-100), as flat',
       '-- x, y lists along each road. Generated from research/roads/traced.json (research/roads/make.py); edit that file.',
       '-- Routes follow these roads; roads players actually ride (learned in game) win wherever they are faster.',
       'WritPath_MapRoads = {']
for m in sorted(d, key=int):
    z = d[m]
    if not z.get('roads') and not z.get('trails'): continue
    out.append(f'  [{m}] = {{   -- {z["name"]}')
    for kind in ('roads', 'trails'):
        if z.get(kind):
            out.append(f'    {kind} = {{')
            for l in z[kind]: out.append('      ' + line(l) + ',')
            out.append('    },')
    out.append('  },')
out.append('}')
open(os.path.join(here, '..', '..', 'WritPathRoads.lua'), 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print('WritPathRoads.lua:', len(out), 'lines')
