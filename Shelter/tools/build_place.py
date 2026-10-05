#!/usr/bin/env python3
"""Write the scripts in ../src back into a Roblox binary place file.

    python3 tools/build_place.py IN.rbxl OUT.rbxl

Every script under src/ (ReplicatedStorage, ServerScriptService, StarterPlayer) replaces the
Source of the instance at the same path. Only the PROP chunks holding script Source are
re-encoded; every other chunk is copied byte for byte. The result is re-read and checked.
"""
import os
import struct
import sys

import zstandard
import lz4.block

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from rbxl import load, path  # noqa: E402

SRC = os.path.join(HERE, '..', 'src')
SCRIPT_CLASSES = {'Script': '.server.lua', 'LocalScript': '.client.lua', 'ModuleScript': '.lua'}
ROOTS = ('ReplicatedStorage', 'ServerScriptService', 'StarterPlayer')


def wanted_sources(inst):
    """ref -> new Source bytes, for every script that has a file under src/."""
    out = {}
    for ref, i in inst.items():
        ext = SCRIPT_CLASSES.get(i['class'])
        if not ext:
            continue
        parts = path(inst, i).split('.')
        if parts[0] not in ROOTS:
            continue
        f = os.path.join(SRC, *parts[:-1], parts[-1] + ext)
        if os.path.exists(f):
            with open(f, 'rb') as fh:
                out[ref] = fh.read()
    return out


def chunks(data):
    p = 32
    while p < len(data):
        name = data[p:p + 4]
        clen, ulen, reserved = struct.unpack_from('<III', data, p + 4)
        n = clen or ulen
        raw = data[p + 16:p + 16 + n]
        yield name, clen, ulen, reserved, raw, data[p:p + 16 + n]
        p += 16 + n
        if name == b'END\x00':
            break


def decompress(clen, ulen, raw):
    if clen == 0:
        return raw
    if raw[:4] == b'\x28\xb5\x2f\xfd':
        return zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen)
    return lz4.block.decompress(raw, uncompressed_size=ulen)


def interleaved_refs(body, off, n):
    vals = []
    for i in range(n):
        v = 0
        for b in range(4):
            v = (v << 8) | body[off + b * n + i]
        vals.append(v)
    out, acc = [], 0
    for v in vals:
        acc += (v >> 1) ^ -(v & 1)
        out.append(acc)
    return out, off + 4 * n


def build(src_path, out_path):
    data = open(src_path, 'rb').read()
    inst = load(src_path)
    new_src = wanted_sources(inst)
    class_refs = {}  # class id -> (class name, [refs])
    out = bytearray(data[:32])
    changed = 0
    for name, clen, ulen, reserved, raw, whole in chunks(data):
        if name == b'INST':
            body = decompress(clen, ulen, raw)
            cid, nlen = struct.unpack_from('<II', body, 0)
            cname = body[8:8 + nlen].decode()
            off = 8 + nlen + 1
            count = struct.unpack_from('<I', body, off)[0]
            refs, _ = interleaved_refs(body, off + 4, count)
            class_refs[cid] = (cname, refs)
            out += whole
            continue
        if name == b'PROP':
            body = decompress(clen, ulen, raw)
            cid, nlen = struct.unpack_from('<II', body, 0)
            prop = body[8:8 + nlen].decode()
            cname, refs = class_refs[cid]
            if prop == 'Source' and cname in SCRIPT_CLASSES:
                off = 8 + nlen
                assert body[off] == 0x01, 'Source is not a string property'
                off += 1
                values = []
                for _ in refs:
                    ln = struct.unpack_from('<I', body, off)[0]
                    values.append(body[off + 4:off + 4 + ln])
                    off += 4 + ln
                assert off == len(body), 'unexpected trailing bytes in Source chunk'
                rebuilt = bytearray(body[:8 + nlen + 1])
                for ref, v in zip(refs, values):
                    nv = new_src.get(ref, v)
                    if nv != v:
                        changed += 1
                    rebuilt += struct.pack('<I', len(nv)) + nv
                comp = zstandard.ZstdCompressor(level=19).compress(bytes(rebuilt))
                out += name + struct.pack('<III', len(comp), len(rebuilt), 0) + comp
                continue
        out += whole
    with open(out_path, 'wb') as f:
        f.write(out)
    return changed, new_src


def verify(orig_path, out_path, new_src):
    a, b = load(orig_path), load(out_path)
    assert a.keys() == b.keys(), 'instance set changed'
    for ref in a:
        pa, pb = a[ref]['props'], b[ref]['props']
        assert a[ref]['class'] == b[ref]['class'] and a[ref]['parent'] == b[ref]['parent'], ref
        for k in pa:
            if k == 'Source' and ref in new_src:
                assert pb[k] == new_src[ref], 'Source mismatch for ' + path(b, b[ref])
            else:
                assert pa[k] == pb.get(k), 'property %s changed on %s' % (k, path(a, a[ref]))


if __name__ == '__main__':
    src_path, out_path = sys.argv[1], sys.argv[2]
    changed, new_src = build(src_path, out_path)
    verify(src_path, out_path, new_src)
    print('%d script(s) updated, %d tracked; wrote %s (%d bytes); verified' % (
        changed, len(new_src), out_path, os.path.getsize(out_path)))
