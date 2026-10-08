"""Black-box shared-controller composition using actual independent Mod DLLs.

No game executable or real runtime is loaded; --service must be our test fixture.
Run each transform order in a fresh process, like a fresh Loader startup.
"""
import argparse
import ctypes as C
from pathlib import Path
import subprocess
import sys
import base64

p = argparse.ArgumentParser()
p.add_argument('--keybinds-dll', required=True)
p.add_argument('--firstperson-dll', required=True)
p.add_argument('--motorcycle-dll', required=True)
p.add_argument('--service', required=True)
p.add_argument('--source', required=True)
p.add_argument('--lupa-dir', required=True)
p.add_argument('--output-dir', required=True)
p.add_argument('--order', choices=['camera-first', 'motorcycle-first'])
a = p.parse_args()
if not a.order:
    for order in ['camera-first', 'motorcycle-first']:
        subprocess.run([sys.executable, __file__, *sys.argv[1:], '--order', order], check=True)
    sys.exit(0)

Sink = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_size_t)
Transform = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p, C.c_size_t, Sink, C.c_void_p)
Log = C.CFUNCTYPE(None, C.c_void_p, C.c_char_p)
Register = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_char_p, Transform, C.c_void_p)
class Host(C.Structure):
    _fields_ = [('size', C.c_uint32), ('abi', C.c_uint32), ('owner', C.c_void_p),
               ('mod_directory', C.c_char_p), ('state_directory', C.c_char_p),
               ('log', Log), ('transform_lua', Register)]
Start = C.CFUNCTYPE(C.c_int, C.POINTER(Host))
class Plugin(C.Structure):
    _fields_ = [('size', C.c_uint32), ('abi', C.c_uint32), ('id', C.c_char_p), ('start', Start)]
Source = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_char_p, Sink, C.c_void_p)
runtime = C.CDLL(str(Path(a.service).resolve()))
runtime.ZML_TestSource.argtypes = [C.POINTER(C.c_void_p)]
runtime.ZML_TestSource.restype = Source
keep = [runtime]
transforms = {}
order = ['keybinds', 'first-person', 'motorcycle'] if a.order == 'camera-first' else ['keybinds', 'motorcycle', 'first-person']
paths = {'keybinds': a.keybinds_dll, 'first-person': a.firstperson_dll, 'motorcycle': a.motorcycle_dll}
for owner, id in enumerate(order, 1):
    @Log
    def log(_, msg):
        print('LOG', msg.decode('utf8'))
    @Register
    def register(_, name, fn, data):
        transforms.setdefault(name.decode(), []).append((id, fn, data))
        return 1
    dll = Path(paths[id]).resolve()
    host = Host(C.sizeof(Host), 1, owner, str(dll.parent).encode(), str(dll.parent).encode(), log, register)
    lib = C.CDLL(str(dll))
    lib.ZML_PluginV1.restype = C.POINTER(Plugin)
    plugin = lib.ZML_PluginV1().contents
    assert plugin.id.decode() == id and plugin.start(C.byref(host)) == 1, id
    keep.extend([host, lib, log, register])

source = Path(a.source).read_bytes()
for id, fn, data in transforms['UI/Panels/BattleAction/BattleActionCtrl']:
    out = []
    @Sink
    def sink(_, address, length):
        out.append(C.string_at(address, length))
    assert fn(data, source, len(source), sink, None) == 1 and len(out) == 1, f'{id} rejected {len(source)} bytes'
    print(f'PASS {a.order}: {id} {len(source)} -> {len(out[0])} bytes')
    source = out[0]
    assert len(source) <= 768 * 1024
assert len(source) < 192 * 1024, 'large assets must not live in the shared controller'
for marker in [b'-- ZML_KEYBINDS_V1', b'-- ZML_FIRST_PERSON_V1', b'-- ZML_MOTORCYCLE_V1']:
    assert source.count(marker) == 1, marker
for call in [b'ZMLMotorcycle.show(self)', b'ZMLMotorcycle.hide(self)', b'ZMLMotorcycle.close(self)',
             b'ZMLFP.show(self)', b'ZMLFP.hide(self)', b'ZMLFP.close(self)']:
    assert source.count(call) == 1, call
data = C.c_void_p()
provider = runtime.ZML_TestSource(C.byref(data))
out = []
@Sink
def capture(_, address, length):
    out.append(C.string_at(address, length))
assert provider(data, b'assets', capture, None) == 1 and len(out) == 1
assets = out[0]
assert len(assets) <= 768 * 1024
sys.path.insert(0, a.lupa_dir)
from lupa.lua54 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.eval('function(s) local f,e=load(s); assert(f,e) end')(source.decode())
payload = lua.execute(assets.decode())
mod = Path(a.motorcycle_dll).resolve().parent
for field, file in [('mesh', 'sidra-bike.zmlmesh'), ('texture', 'Textures.png')]:
    assert base64.b64decode(payload[field], validate=True) == (mod/'assets'/file).read_bytes()
    assert payload[field].encode() not in source
target = Path(a.output_dir)
target.mkdir(parents=True, exist_ok=True)
(target/(a.order+'.lua')).write_bytes(source)
(target/(a.order+'.lua.assets.lua')).write_bytes(assets)
print(f'PASS {a.order}: lifecycle markers, complete Lua syntax and separate {len(assets)}-byte asset source')
