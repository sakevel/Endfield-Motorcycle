"""Current v29 metadata names/signatures only; no RVA or fixed runtime offsets."""
import struct, json, re, argparse, hashlib
from pathlib import Path
p=Path(r'D:\Game\Hypergryph Launcher\games\Endfield Game\Endfield_Data\il2cpp_data\Metadata\global-metadata.dat')
b=p.read_bytes(); h=struct.unpack_from('<64I',b)
assert h[:2]==(0xfab11baf,29)
so,ss=h[6:8]; mo,ms=h[12:14]; po,ps=h[22:24]; fo,fs=h[24:26]; to,ts=h[40:42]; io,isz=h[42:44]
def string(index):
    assert 0<=index<ss
    return b[so+index:b.index(b'\0',so+index)].decode('utf8')
types=[struct.unpack_from('<17i8H2I',b,i) for i in range(to,to+ts,92)]
names={t[2]:'.'.join(filter(None,(string(t[1]),string(t[0])))) for t in types}
images=[struct.unpack_from('<10I',b,i) for i in range(io,io+isz,40)]
a=argparse.ArgumentParser(); a.add_argument('--match',required=True); arg=a.parse_args()
result=[]
for index,t in enumerate(types):
    name='.'.join(filter(None,(string(t[1]),string(t[0]))))
    if not re.search(arg.match,name,re.I): continue
    image=next(string(i[0]) for i in images if i[2]<=index<i[2]+i[3])
    methods=[]
    for n in range(t[9],t[9]+t[17]):
        m=struct.unpack_from('<6i4H',b,mo+n*32)
        params=[struct.unpack_from('<3i',b,po+(m[3]+k)*12) for k in range(m[-1])]
        methods.append(dict(name=string(m[0]),ret=names.get(m[2],str(m[2])),static=bool(m[6]&16),argc=m[-1],params=[(string(x[0]),names.get(x[2],str(x[2]))) for x in params]))
    fields=[]
    for n in range(t[8],t[8]+t[19]):
        f=struct.unpack_from('<3i',b,fo+n*12); fields.append((string(f[0]),names.get(f[1],str(f[1]))))
    result.append(dict(image=image,name=name,parent=names.get(t[4],str(t[4])),methods=methods,fields=fields))
out=Path(__file__).resolve().parents[1]/'artifacts/research'
out.mkdir(parents=True,exist_ok=True)
(out/'metadata.json').write_text(json.dumps(dict(sha256=hashlib.sha256(b).hexdigest(),types=result),indent=2),encoding='utf8')
for t in result:
    print(t['image'],t['name'])
    print(' fields:',', '.join(x[0]+':'+x[1] for x in t['fields']))
    print(' methods:',', '.join(x['name']+'('+','.join(v[0]+':'+v[1] for v in x['params'])+')->'+x['ret'] for x in t['methods']))
