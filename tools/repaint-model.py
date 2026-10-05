"""Repaint model material/UV assignments, not the original palette PNG.

Run on freshly converted Sidra geometry; original geometry hash is required.
Only diffuse RGBA, UV range and packed UV bytes change. No geometry/rig changes.
Pillow is used only to read the source palette for material classification.
"""
from pathlib import Path
import hashlib
import struct
from PIL import Image

root = Path(__file__).resolve().parents[1]
path = root / 'mod/assets/sidra-bike.zmlmesh'
data = bytearray(path.read_bytes())
original = '4d88164ad62e0590ac35b77d0c5b1dd3792ed1e4b3cd81c77c2c405824204e64'
assert hashlib.sha256(data).hexdigest() == original, 'Requires freshly converted original model'
texture = Image.open(root / 'mod/assets/Textures.png').convert('RGB')
# Runtime palette: charcoal, metal, mid-grey, light, yellow, rubber, white, white.
def slot(rgb):
    r, g, b = rgb
    if r > g * 1.4 and r > b * 1.4:
        return 4  # Red frame / amber indicators -> Endfield yellow.
    if min(rgb) >= 150 or b > r * 1.2:
        return 3  # Lamp/reflector.
    if min(rgb) >= 110:
        return 2  # Seat and mechanical mid-tones.
    if min(rgb) >= 90:
        return 1  # Exposed metal.
    return 0

at = 12
for part in range(struct.unpack_from('<I', data, 8)[0]):
    role, nv, ni, textured = struct.unpack_from('<4I', data, at)
    f = struct.unpack_from('<17f', data, at + 16)
    if textured:
        for v in range(nv):
            uv_at = at + 84 + v * 12 + 8
            u, w = struct.unpack_from('<2H', data, uv_at)
            x = round(max(0, min(1, f[9] + f[11] * u / 65535)) * 127)
            y = round((1 - max(0, min(1, f[10] + f[12] * w / 65535))) * 127)
            index = slot(texture.getpixel((x, y)))
            struct.pack_into('<2H', data, uv_at, round((index + .5) / 8 * 65535), 32768)
        struct.pack_into('<4f', data, at + 16 + 9 * 4, 0, 0, 1, 1)
        struct.pack_into('<4f', data, at + 16 + 13 * 4, 1, 1, 1, 1)
    else:
        # Painted tank/fenders/front casing white; tyres remain rubber, not white.
        color = (247/255, 247/255, 242/255, 1) if role in (0, 3) else (28/255, 28/255, 28/255, 1)
        struct.pack_into('<4f', data, at + 16 + 13 * 4, *color)
    at += 84 + nv * 12 + ni * 2
assert at == len(data)
path.write_bytes(data)
mesh_hash = hashlib.sha256(data).hexdigest()
texture_hash = hashlib.sha256((root / 'mod/assets/Textures.png').read_bytes()).hexdigest()
(root / 'src/asset_hashes.hpp').write_text(
    '#pragma once\nnamespace motorcycle {\n'
    f'inline constexpr char meshHash[]="{mesh_hash}";\n'
    f'inline constexpr char textureHash[]="{texture_hash}";\n}}\n', encoding='utf8')
print(f'PASS: repainted material/UV assignments only; {len(data)} bytes; SHA256 {mesh_hash}')
