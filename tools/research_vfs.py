"""Read-only, bounded current-client resource research. Never packaged with the mod."""
from pathlib import Path
import struct, zlib, json, hashlib, re, argparse
from Crypto.Cipher import ChaCha20

KEY = bytes.fromhex('E95B317AC4F828569D23A86BF271DCB53E846FA75C924D671DBA8E38F4CA52E1')
def decrypt(data, nonce):
    cipher = ChaCha20.new(key=KEY, nonce=nonce)
    cipher.seek(64)
    return cipher.decrypt(data)
class Reader:
    def __init__(self, data): self.data, self.pos = data, 0
    def take(self, size):
        if size < 0 or self.pos + size > len(self.data): raise ValueError('bounds')
        value = self.data[self.pos:self.pos+size]; self.pos += size
        return value
    def number(self, fmt): return struct.unpack('<'+fmt, self.take(struct.calcsize('<'+fmt)))[0]
    def string(self): return self.take(self.number('H')).decode('ascii')
def inventory(root):
    records, sources = {}, []
    for overlay in ('StreamingAssets', 'Persistent'):
        for blc in sorted((root/overlay/'VFS').glob('*/*.blc')):
            data = blc.read_bytes(); plain = decrypt(data[12:], data[:12])
            assert zlib.crc32(plain[:-4]) & 0xffffffff == struct.unpack('<I', plain[-4:])[0]
            sources.append({'path':str(blc),'sha256':hashlib.sha256(data).hexdigest(),'crc32':True})
            r = Reader(plain[:-4]); version = r.number('i'); code = version if version < 11 else 3
            if version < 11: version = r.number('i')
            r.string(); r.number('q'); r.number('i'); r.number('q'); r.number('B')
            for _ in range(r.number('i')):
                chunk = r.take(16).hex().upper(); r.take(16); r.number('q'); r.number('B')
                if code > 3: r.number('i')
                for _ in range(r.number('i')):
                    path = r.string(); r.number('q'); r.take(16); r.take(16)
                    offset, size = r.number('q'), r.number('q'); r.number('B'); enc = r.number('B')
                    iv = r.number('q') if enc else None
                    if code > 3: r.number('i')
                    chk = blc.parent/(chunk+'.chk')
                    if not chk.is_file(): continue
                    normal = path.replace('\\','/').lower()
                    records[normal] = dict(path=normal, overlay=overlay, chunk=str(chk), offset=offset, size=size, iv=iv)
    return records, sources
def extract(record, target):
    chunk = Path(record['chunk']); size = record['size']; offset = record['offset']
    assert 0 < size <= 256*1024*1024 and 0 <= offset <= chunk.stat().st_size-size
    with chunk.open('rb') as stream: stream.seek(offset); data=stream.read(size)
    if record['iv'] is not None: data=decrypt(data, struct.pack('<iq',3,record['iv']))
    target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
    return hashlib.sha256(data).hexdigest()
if __name__ == '__main__':
    a=argparse.ArgumentParser(); a.add_argument('--match',required=True); args=a.parse_args()
    root=Path(r'D:\Game\Hypergryph Launcher\games\Endfield Game\Endfield_Data')
    out=Path(__file__).resolve().parents[1]/'artifacts/research/current'
    out.mkdir(parents=True,exist_ok=True)
    records,sources=inventory(root)
    (out/'inventory.json').write_text(json.dumps(records,indent=2),encoding='utf8')
    selected=[]
    for path,record in records.items():
        if not re.search(args.match,path,re.I): continue
        # Extract target resources
        if not (path.startswith(('data/luascripts/','data/bundles/','data/res/','data/config/')) or path.endswith(('manifest.hgmmap','stringpathhash.bin'))): continue
        if '..' in Path(path).parts: raise ValueError('path')
        item=dict(record); item['sha256']=extract(record,out/'raw'/path); selected.append(item)
        print(record['overlay'],record['size'],path)
    (out/'provenance.json').write_text(json.dumps(dict(readOnly=True,overlay=['StreamingAssets','Persistent'],sources=sources,selected=selected),indent=2),encoding='utf8')
    print('Verified BLC:',len(sources),'Available files:',len(records),'Extracted:',len(selected))
