"""Unit tests with mocked Unity environment."""
from pathlib import Path
import argparse,subprocess,sys,tempfile,base64,struct
a=argparse.ArgumentParser();a.add_argument('--keybinds',required=True);a.add_argument('--lupa-dir');a.add_argument('--services',required=True);a.add_argument('--patched');a.add_argument('--wheel-patched');a.add_argument('--native-fixtures');a.add_argument('--native-only',action='store_true');a.add_argument('--features-only',action='store_true');args=a.parse_args()
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
    lua.globals().keybind_factory=lua.execute(Path(args.keybinds).read_text(encoding='utf8'))
    lua.execute((root/'tests/keybind_fixture.lua').read_text(encoding='utf8'))
    def decode(s):
        data=base64.b64decode(s,validate=True)
        return data # Actual XLua byte[] return is a binary Lua string, no Length property.
    lua.globals().mock_decode_asset=decode
    helper=(root/'mod/motorcycle.lua').read_text(encoding='utf8')
    asset_data='local BIKE_MESH_BASE64="'+base64.b64encode((root/'mod/assets/sidra-bike.zmlmesh').read_bytes()).decode()+'"\nlocal BIKE_TEXTURE_BASE64="'+base64.b64encode((root/'mod/assets/Textures.png').read_bytes()).decode()+'"'
    helper=helper.replace('-- ZML_ASSET_DATA',asset_data)
    helper=helper.replace('-- ZML_VEHICLE_FLIGHT',(root/'mod/flight.lua').read_text(encoding='utf8'))
    helper=helper.replace('-- ZML_NATIVE_ACTIONS',(root/'mod/native-actions.lua').read_text(encoding='utf8'))
    if args.patched:
        compiled=Path(args.patched).read_text(encoding='utf8')
        begin='local ZMLMotorcycle = (function()\n'
        assert compiled.count(begin)==1
        start=compiled.index(begin)+len(begin)
        helper=compiled[start:compiled.index('\nend)()\n\n',start)]
        print('Testing actual DLL-assembled compacted helper')
    lua.globals().M=lua.execute(helper)
    if not args.native_only and not args.features_only: lua.execute((root/'tests/scenarios.lua').read_text(encoding='utf8'))
    if not args.native_only: lua.execute((root/'tests/riding_features.lua').read_text(encoding='utf8'))
    wheel=(root/'mod/wheel.lua').read_text(encoding='utf8').replace('-- ZML_WHEEL_ICON_DATA','local WHEEL_ICON_BASE64="'+base64.b64encode((root/'mod/wheel-icon.png').read_bytes()).decode()+'"')
    lua.globals().W=lua.execute(wheel)
    lua.execute((root/'tests/native_scenarios.lua').read_text(encoding='utf8'))
    lua.execute((root/'tests/collision_scenarios.lua').read_text(encoding='utf8'))
    lua.execute((root/'tests/keybind_scenarios.lua').read_text(encoding='utf8'))
    if args.patched:
        source=Path(args.patched).read_text(encoding='utf8')
        assert lua.eval('function(s) local fn,err=load(s); assert(fn,err); return true end')(source)
        assert source.count('local ZMLMotorcycle')==1
        print('PASS: complete current-client transformed Lua syntax')
    if args.wheel_patched:
        source=Path(args.wheel_patched).read_text(encoding='utf8')
        assert lua.eval('function(s) local fn,err=load(s); assert(fn,err); return true end')(source)
        print('PASS: complete current-client transformed native wheel syntax')
    if args.native_fixtures:
        assert args.wheel_patched, '--native-fixtures requires the actual --wheel-patched output'
        lua.globals().native_source=lambda name: (Path(args.native_fixtures)/name).read_text(encoding='utf8')
        lua.globals().wheel_native_source=Path(args.wheel_patched).read_text(encoding='utf8')
        lua.execute((root/'tests/current_native.lua').read_text(encoding='utf8'))
    print('PASS: motorcycle production Lua, real services, rig/state/rollback/input/resource mock scenarios')
finally:
    server.stdin.close()
    try:server.wait(timeout=5)
    except subprocess.TimeoutExpired:server.kill();server.wait()
    temp.cleanup()
    if server.returncode:raise RuntimeError(server.stderr.read().decode(errors='replace'))
