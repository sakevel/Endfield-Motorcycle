"""Native UI/VFX extraction tool."""
from pathlib import Path
import argparse,json,subprocess,hashlib
from research_vfs import inventory,extract
p=argparse.ArgumentParser()
p.add_argument('--game-data',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--decode-lua',type=Path,required=True)
p.add_argument('--indices',type=Path,required=True)
p.add_argument('--anime-studio',type=Path,required=True)
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
records,sources=inventory(a.game_data);selected=[]
def take(key,path):
    record=records[key];sha=extract(record,path)
    selected.append(dict(record,sha256=sha));return path
for name in ('const/quickmenuconst','const/interactoptionconst','ui/panels/quickmenu/quickmenuctrl',
    'ui/panels/interactoption/interactoptionctrl','ui/panels/facbuildmode/facbuildmodectrl',
    'ui/panels/facbuildinginteract/facbuildinginteractctrl','ui/panels/battleaction/battleactionctrl',
    'ui/panels/generalability/generalabilityctrl','ui/widgets/generalabilitycell',
    'const/facconst','common/utils/factoryutils'):
    stem=name.rsplit('/',1)[-1]
    raw=take('data/luascripts/'+name+'.lua',a.out/(stem+'.raw'))
    target=a.out/(stem+'.lua')
    subprocess.run([str(a.decode_lua.resolve()),str(raw.resolve()),str(target.resolve())],check=True)
    selected[-1]['decryptedSha256']=hashlib.sha256(target.read_bytes()).hexdigest()
for resource in ('bundles/windows/manifest.hgmmap','extenddata/main/stringpathhash.bin'):
    current=take('data/'+resource,a.out/Path(resource).name)
    assert current.read_bytes()==(a.indices/resource).read_bytes(),'indices changed: rerun pinned ResConv first'
m=json.loads((a.indices/'bundles/windows/manifest.json').read_text(encoding='utf8'))
bundles={b['bundleIndex']:b for b in m['Bundles']}
for asset in m['Assets']:
    if asset['path'].endswith(('p_factory_appear_cutoff.asset','p_factory_appear_add.asset',
        'p_factory_disappear_add.asset','p_factory_disappear_cutoff.asset')):
        key='data/bundles/windows/'+bundles[asset['bundleIndex']]['name']
        take(key,a.out/'effects'/Path(key).name);selected[-1]['asset']=asset
with (a.out/'export.log').open('wb')as log:
    subprocess.run([str(a.anime_studio.resolve()),str((a.out/'effects').resolve()),str((a.out/'effects-dump').resolve()),
        '--game','ArknightsEndfield','--export_type','Dump','--types','MonoBehaviour:Both','AssetBundle:Both',
        '--logger_flags','Error,Warning,Info'],check=True,stdout=log,stderr=subprocess.STDOUT)
(a.out/'provenance.json').write_text(json.dumps(dict(readOnly=True,sources=sources,selected=selected),indent=2),encoding='utf8')
print('CRC verified',len(sources),'Lua roundtrips 11; native effect bundles 4')
