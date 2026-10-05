"""Audit local AnimeStudio dumps; game assets never belong in the release package."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import re
import struct


def integer(text, name):
    match = re.search(r"\b" + re.escape(name) + r" = (-?\d+)", text)
    if not match:
        raise ValueError("Missing field: " + name)
    return int(match[1])


def read(path):
    if path.stat().st_size > 512 * 1024 * 1024:
        raise ValueError("Dump too large")
    return path.read_text(encoding="utf8")


def audit(root, extract_d3d=False):
    provenance = json.loads(read(root / "provenance.json"))
    assert provenance["readOnly"] and all(s["crc32"] for s in provenance["sources"])
    prefabs = root / "prefab-dump"
    game_objects = []
    for path in sorted((prefabs / "GameObject").glob("*.txt")):
        text = read(path)
        game_objects.append({"name": re.search(r'm_Name = "(.*?)"', text)[1],
                             "layer": integer(text, "m_Layer"),
                             "components": integer(text, "size")})
    renderers = []
    for path in sorted((prefabs / "MeshRenderer").glob("*.txt")):
        text = read(path)
        renderers.append({key: integer(text, key) for key in (
            "m_RenderingLayerMask", "m_LightModeMask", "m_CastShadows",
            "m_ReceiveShadows", "m_SubMeshRenderMode", "m_CharacterIndex",
            "m_MotionVectors", "m_LightProbeUsage", "m_ReflectionProbeUsage",
            "firstSubMesh", "subMeshCount")})
    mesh_path = next((root / "mesh-material-dump/Mesh").glob("*lod0.txt"))
    mesh = read(mesh_path)
    channel_text = mesh[mesh.index("vector m_Channels"):mesh.index("TypelessData m_DataSize")]
    channels = [dict(zip(("stream", "offset", "format", "dimension_raw"), map(int, values)))
                for values in re.findall(
                    r"UInt8 stream = (\d+)\s+UInt8 offset = (\d+)\s+UInt8 format = (\d+)\s+UInt8 dimension = (\d+)",
                    channel_text)]
    shader_path = next((root / "shader-dump/Shader").glob("*.txt"))
    shader = read(shader_path)
    passes = re.findall(r'^\t{9}string m_Name = "(.*?)"', shader, re.M)
    assert "HGBuffer" in passes and "ForwardOnly" not in passes
    result = {"blc_crc_count": len(provenance["sources"]),
              "bundle_count": len(provenance["selected"]),
              "prefab_dump_objects": len(list(prefabs.rglob("*.txt"))),
              "game_objects": game_objects, "renderers": renderers,
              "mesh": {"vertex_count": integer(mesh, "m_VertexCount"),
                       "index_count": integer(mesh, "indexCount"), "channels": channels},
              "shader": {"name": "HGRP/Lit", "passes": passes,
                         "dump_sha256": hashlib.sha256(shader_path.read_bytes()).hexdigest()},
              "visual_acceptance": False}
    if extract_d3d:
        -- Offline research tool
        start = shader.index("SubShaderBlob data")
        end = shader.find("SubShaderBlob data", start + 1)
        block = shader[start:end]
        sections = ("m_CompressedBlob", "m_Offsets", "m_CompressedLengths", "m_DecompressedLengths")
        pieces = [block[block.index("vector " + key):] for key in sections]
        blob = bytes(map(int, re.findall(r"UInt8 data = (\d+)", pieces[0][:pieces[0].index("vector m_Offsets")])))
        fields = [list(map(int, re.findall(r"unsigned int data = (\d+)",
                  pieces[i][:pieces[i].find("vector " + sections[i+1])] if i < 3 else pieces[i])))
                  for i in range(1, 4)]
        offset, length, size = (x[0] for x in fields)
        assert 0 < size < 64 * 1024 * 1024 and offset + length <= len(blob)
        data = lz4.block.decompress(blob[offset:offset+length], uncompressed_size=size)
        assert len(data) == size
        (root / "shader-d3d.bin").write_bytes(data)
        dll = ctypes.WinDLL("d3dcompiler_47.dll")
        disassemble = dll.D3DDisassemble
        disassemble.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint,
                               ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
        disassemble.restype = ctypes.c_long
        for match in re.finditer(b"DXBC", data):
            pos = match.start()
            if pos + 32 > len(data):
                continue
            length = struct.unpack_from("<I", data, pos + 24)[0]
            if length < 32 or pos + length > len(data):
                continue
            buffer = ctypes.create_string_buffer(data[pos:pos+length])
            obj = ctypes.c_void_p()
            if disassemble(buffer, length, 0, None, ctypes.byref(obj)) or not obj:
                continue
            vtable = ctypes.cast(obj, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
            pointer = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vtable[3])(obj)
            count = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vtable[4])(obj)
            text = ctypes.string_at(pointer, count).decode("utf8", errors="replace")
            ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(vtable[2])(obj)
            if "\nvs_5_0" in text:
                (root / "vertex-audit.asm").write_text(text, encoding="utf8")
                result["shader"]["vertex_dxbc_offset"] = pos
                result["shader"]["ordinary_normal_fallback"] = (
                    "and r0.x, v1.x, l(0x40000000)" in text and "mov r1.xyw, v1.xyxz" in text)
                break
        assert result["shader"].get("ordinary_normal_fallback")
    (root / "comparison.json").write_text(json.dumps(result, indent=2), encoding="utf8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--extract-d3d", action="store_true")
    args = parser.parse_args()
    result = audit(args.root, args.extract_d3d)
    print("PASS: CRC", result["blc_crc_count"], "bundles", result["bundle_count"],
          "prefab objects", result["prefab_dump_objects"], "shader passes", result["shader"]["passes"])
