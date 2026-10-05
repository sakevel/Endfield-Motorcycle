"""Bounded current-client rider extraction, local research only (never packaged).

Uses the existing pinned upstream AnimeStudio CLI supplied explicitly. Cached
ResConv JSON is accepted ONLY if fresh VFS manifest/string index bytes match.
No game files, saves, account data or installed tool source are modified.
"""
from pathlib import Path
import argparse, json, subprocess
from research_vfs import inventory, extract

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('--anime-studio',type=Path,required=True)
    p.add_argument('--game-data',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--indices',type=Path,default=ROOT/'artifacts/research/current/raw/data')
    a=p.parse_args();assert a.anime_studio.is_file()
    a.out.mkdir(parents=True,exist_ok=True);records,sources=inventory(a.game_data)
    for resource in ('bundles/windows/manifest.hgmmap','extenddata/main/stringpathhash.bin'):
        dst=a.out/Path(resource).name;extract(records['data/'+resource],dst)
        assert dst.read_bytes()==(a.indices/resource).read_bytes(),'indices changed: rerun pinned ResConv first'
    m=json.loads((a.indices/'bundles/windows/manifest.json').read_text(encoding='utf8'))
    bundles={b['bundleIndex']:b for b in m['Bundles']};selected=[]
    for name in ('typhoea','chen','laevat','pograni'):
        body=next(v for v in m['Assets']if v['path'].endswith('/sk_actor_'+name+'_01.fbx##s_actor_'+name+'_body_01_lod0'))
        prefab=next(v for v in m['Assets']if '/actors/postmodels/characters/'in v['path']and v['path'].endswith(name+'_postmodel.prefab'))
        directory=a.out/name
        for asset,folder in ((body,'bundles'),(prefab,'prefab-bundle')):
            key='data/bundles/windows/'+bundles[asset['bundleIndex']]['name'];rec=records[key]
            dst=directory/folder/Path(key).name
            h=extract(rec,dst);selected.append(dict(rec,asset=asset,sha256=h,character=name))
        for folder,out,mode,types in (
            ('bundles','json','JSON',['Mesh','Avatar']),
            ('prefab-bundle','skeleton-dump','Dump',['Transform','GameObject','SkinnedMeshRenderer','Animator'])):
            command=[str(a.anime_studio.resolve()),str((directory/folder).resolve()),str((directory/out).resolve()),
                     '--game','ArknightsEndfield','--export_type',mode,'--types',*types,'--logger_flags','Error,Warning,Info']
            with (directory/(out+'-export.log')).open('wb')as log:subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True)
        print(name,'local Avatar/LOD0 + prefab exported')
    (a.out/'provenance.json').write_text(json.dumps(dict(readOnly=True,sources=sources,selected=selected),indent=2),encoding='utf8')
    print('BLC CRC verified:',len(sources),'selected bundles:',len(selected))

if __name__=='__main__':main()
