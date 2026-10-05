"""Actual Lua + real public services, simulated Unity objects; NOT in-game acceptance."""
from pathlib import Path
import argparse,subprocess,sys,tempfile,base64,struct
a=argparse.ArgumentParser();a.add_argument('--lupa-dir');a.add_argument('--services',required=True);a.add_argument('--patched');args=a.parse_args()
if args.lupa_dir:sys.path.insert(0,args.lupa_dir)
from lupa.lua54 import LuaRuntime
root=Path(__file__).resolve().parents[1]
manifest=root/'build/package/Release/motorcycle/mod.ini'
# The public fixture's primary record requires a PNG; keep that unrelated fixture synthetic.
# The real Mod manifest is loaded as an additional record, unchanged (no runtime icon requirement).
temp=tempfile.TemporaryDirectory(prefix='zml-motorcycle-test-')
t=Path(temp.name)
(t/'icon.png').write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='))
(t/'Fixture.dll').write_bytes(b'fixture-not-loaded')
(t/'mod.ini').write_text('[mod]\nid=fixture\nname=Fixture\nlibrary=Fixture.dll\nicon=icon.png\nconfig_menu=none\napi=1\nenabled=true\n',encoding='utf8')
server=subprocess.Popen([str(Path(args.services).resolve()),'--serve',str(t/'mod.ini'),str(manifest)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
def route(_,path):
    server.stdin.write((path+'\n').encode());server.stdin.flush()
    header=server.stdout.readline();assert header,server.stderr.read().decode(errors='replace')
    size=int(header);result=server.stdout.read(size);assert len(result)==size
    return result.decode('utf8')
try:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().native_route=route
    lua.execute('loadstring=load; LuaManagerInst={LoadLua=function(self,p)return native_route(self,p)end}')
    public=lua.execute(route(None,'ZML/Api'))
    lua.globals().PUBLIC=public
    lua.execute((root/'tests/mock.lua').read_text(encoding='utf8'))
    def decode(s):
        data=base64.b64decode(s,validate=True)
        return data # Actual XLua byte[] return is a binary Lua string, no Length property.
    lua.globals().mock_decode_asset=decode
    helper=(root/'mod/motorcycle.lua').read_text(encoding='utf8')
    asset_data='local BIKE_MESH_BASE64="'+base64.b64encode((root/'mod/assets/sidra-bike.zmlmesh').read_bytes()).decode()+'"\nlocal BIKE_TEXTURE_BASE64="'+base64.b64encode((root/'mod/assets/Textures.png').read_bytes()).decode()+'"'
    helper=helper.replace('-- ZML_ASSET_DATA',asset_data)
    lua.globals().M=lua.execute(helper)
    lua.execute((root/'tests/scenarios.lua').read_text(encoding='utf8'))
    if args.patched:
        source=Path(args.patched).read_text(encoding='utf8')
        assert lua.eval('function(s) local fn,err=load(s); assert(fn,err); return true end')(source)
        assert source.count('local ZMLMotorcycle')==1
        print('PASS: complete current-client transformed Lua syntax')
    print('PASS: motorcycle production Lua, real services, rig/state/rollback/input/resource mock scenarios')
finally:
    server.stdin.close()
    try:server.wait(timeout=5)
    except subprocess.TimeoutExpired:server.kill();server.wait()
    temp.cleanup()
    if server.returncode:raise RuntimeError(server.stderr.read().decode(errors='replace'))
