#!/usr/bin/env python3
"""Write the scripts in ../src back into a Roblox binary place file.

    python3 tools/build_place.py IN.rbxl OUT.rbxl

Every script under src/ (ReplicatedStorage, ServerScriptService, StarterPlayer) replaces the
Source of the instance at the same path. A .lua file with no instance at its path becomes a new
ModuleScript under the (existing) parent folder, with its other properties copied from an
existing ModuleScript (fresh UniqueId and ScriptGuid). Only the ModuleScript INST chunk, the
script PROP chunks and the PRNT chunk are re-encoded; every other chunk is copied byte for byte.
The result is re-read and checked.
"""
import os
import struct
import sys
import uuid

import zstandard
import lz4.block

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from rbxl import load, path  # noqa: E402

SRC = os.path.join(HERE, '..', 'src')
SCRIPT_CLASSES = {'Script': '.server.lua', 'LocalScript': '.client.lua', 'ModuleScript': '.lua'}
ROOTS = ('ReplicatedStorage', 'ServerScriptService', 'StarterPlayer')

# ModuleScript property encodings we know how to extend: 'str' = length-prefixed sequential,
# 'bool' = one byte each, ('il', w) = byte-interleaved fixed width w.
LAYOUT = {0x01: 'str', 0x02: 'bool', 0x03: ('il', 4), 0x12: ('il', 4), 0x1B: ('il', 8), 0x1C: ('il', 4),
          0x1F: ('il', 16), 0x21: ('il', 8)}


def src_files():
    """instance path (dotted) -> (class, file bytes) for every script file under src/."""
    out = {}
    for dirpath, _, files in os.walk(SRC):
        for fn in files:
            if not fn.endswith('.lua'):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), SRC)[:-4]
            cls = 'ModuleScript'
            if rel.endswith('.server'):
                rel, cls = rel[:-7], 'Script'
            elif rel.endswith('.client'):
                rel, cls = rel[:-7], 'LocalScript'
            with open(os.path.join(dirpath, fn), 'rb') as fh:
                out[rel.replace(os.sep, '.')] = (cls, fh.read())
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


def pack(name, body):
    comp = zstandard.ZstdCompressor(level=19).compress(bytes(body))
    return name + struct.pack('<III', len(comp), len(body), 0) + comp


def deinterleave(payload, n, w):
    return [bytes(payload[b * n + i] for b in range(w)) for i in range(n)]


def interleave(values, w):
    n = len(values)
    out = bytearray(n * w)
    for i, v in enumerate(values):
        for b in range(w):
            out[b * n + i] = v[b]
    return bytes(out)


def decode_refs(payload, n):
    out, acc = [], 0
    for v in deinterleave(payload, n, 4):
        z = int.from_bytes(v, 'big')
        acc += (z >> 1) ^ -(z & 1)
        out.append(acc)
    return out


def encode_refs(refs):
    vals, prev = [], 0
    for r in refs:
        d = r - prev
        prev = r
        vals.append((((d << 1) ^ (d >> 31)) & 0xFFFFFFFF).to_bytes(4, 'big'))
    return interleave(vals, 4)


def build(src_path, out_path):
    data = open(src_path, 'rb').read()
    inst = load(src_path)
    files = src_files()
    by_path = {}
    for ref, i in inst.items():
        by_path.setdefault(path(inst, i), []).append(ref)

    # replacements for existing scripts, and new ModuleScripts to insert
    new_src, new_mods = {}, []
    for p, (cls, src) in sorted(files.items()):
        refs = [r for r in by_path.get(p, []) if inst[r]['class'] in SCRIPT_CLASSES]
        if refs:
            new_src[refs[0]] = src
            continue
        parent = by_path.get(p.rsplit('.', 1)[0])
        if cls != 'ModuleScript' or not parent:
            raise SystemExit('cannot add %s (%s): only ModuleScripts under an existing parent' % (p, cls))
        new_mods.append({'path': p, 'name': p.rsplit('.', 1)[1], 'parent': parent[0], 'source': src})
    next_ref = max(inst) + 1
    for m in new_mods:
        m['ref'] = next_ref
        next_ref += 1
        new_src[m['ref']] = m['source']

    # UniqueIds are unique place-wide: new ones continue after the highest index in use
    class_refs, uid_index = {}, 0
    parsed = []
    for c in chunks(data):
        name, clen, ulen, _, raw, _ = c
        body = decompress(clen, ulen, raw) if name in (b'INST', b'PROP', b'PRNT') else None
        parsed.append((c, body))
        if name == b'INST':
            cid, nlen = struct.unpack_from('<II', body, 0)
            count = struct.unpack_from('<I', body, 9 + nlen)[0]
            class_refs[cid] = (body[8:8 + nlen].decode(), decode_refs(body[13 + nlen:13 + nlen + 4 * count], count))
        elif name == b'PROP':
            cid, nlen = struct.unpack_from('<II', body, 0)
            if body[8 + nlen] == 0x1F:
                n = len(class_refs[cid][1])
                for v in deinterleave(body[9 + nlen:], n, 16):
                    uid_index = max(uid_index, int.from_bytes(v[:4], 'big'))

    out = bytearray(data[:32])
    if new_mods:
        classes, count = struct.unpack_from('<ii', data, 16)
        struct.pack_into('<ii', out, 16, classes, count + len(new_mods))
    changed = 0
    for (name, clen, ulen, reserved, raw, whole), body in parsed:
        if name == b'INST':
            cid, nlen = struct.unpack_from('<II', body, 0)
            cname, refs = class_refs[cid]
            if cname == 'ModuleScript' and new_mods:
                refs = refs + [m['ref'] for m in new_mods]
                head = bytearray(body[:9 + nlen])
                assert body[8 + nlen] == 0, 'ModuleScript is not expected to be a service'
                out += pack(name, head + struct.pack('<I', len(refs)) + encode_refs(refs))
                continue
            out += whole
        elif name == b'PROP':
            cid, nlen = struct.unpack_from('<II', body, 0)
            prop = body[8:8 + nlen].decode()
            t = body[8 + nlen]
            cname, refs = class_refs[cid]
            extend = cname == 'ModuleScript' and new_mods
            if not (extend or (prop == 'Source' and cname in SCRIPT_CLASSES)):
                out += whole
                continue
            layout = LAYOUT.get(t)
            if layout is None:
                raise SystemExit('unsupported property type 0x%02x (%s.%s)' % (t, cname, prop))
            payload = body[9 + nlen:]
            n = len(refs)
            if layout == 'str':
                values, off = [], 0
                for _ in range(n):
                    ln = struct.unpack_from('<I', payload, off)[0]
                    values.append(payload[off + 4:off + 4 + ln])
                    off += 4 + ln
                assert off == len(payload), 'trailing bytes in %s.%s' % (cname, prop)
            elif layout == 'bool':
                assert len(payload) == n
                values = [payload[i:i + 1] for i in range(n)]
            else:
                w = layout[1]
                assert len(payload) == n * w, 'unexpected size for %s.%s' % (cname, prop)
                values = deinterleave(payload, n, w)
            if prop == 'Source':
                for i, ref in enumerate(refs):
                    nv = new_src.get(ref)
                    if nv is not None and nv != values[i]:
                        values[i] = nv
                        changed += 1
            if extend:
                template = values[0]
                for m in new_mods:
                    if prop == 'Name':
                        v = m['name'].encode()
                    elif prop == 'Source':
                        v = m['source']
                        changed += 1
                    elif prop == 'ScriptGuid':
                        v = ('{' + str(uuid.uuid4()).upper() + '}').encode()
                    elif prop == 'UniqueId':
                        uid_index += 2
                        v = uid_index.to_bytes(4, 'big') + template[4:]
                    else:
                        v = template
                    values.append(v)
            if layout == 'str':
                enc = b''.join(struct.pack('<I', len(v)) + v for v in values)
            elif layout == 'bool':
                enc = b''.join(values)
            else:
                enc = interleave(values, layout[1])
            out += pack(name, body[:9 + nlen] + enc)
        elif name == b'PRNT' and new_mods:
            n = struct.unpack_from('<I', body, 1)[0]
            kids = decode_refs(body[5:5 + 4 * n], n)
            parents = decode_refs(body[5 + 4 * n:5 + 8 * n], n)
            kids += [m['ref'] for m in new_mods]
            parents += [m['parent'] for m in new_mods]
            out += pack(name, body[:1] + struct.pack('<I', len(kids)) + encode_refs(kids) + encode_refs(parents))
        else:
            out += whole
    with open(out_path, 'wb') as f:
        f.write(out)
    return changed, new_src, new_mods


def verify(orig_path, out_path, new_src, new_mods):
    a, b = load(orig_path), load(out_path)
    added = {m['ref'] for m in new_mods}
    assert set(b) == set(a) | added, 'instance set changed'
    for ref in a:
        pa, pb = a[ref]['props'], b[ref]['props']
        assert a[ref]['class'] == b[ref]['class'] and a[ref]['parent'] == b[ref]['parent'], ref
        for k in pa:
            if k == 'Source' and ref in new_src:
                assert pb[k] == new_src[ref], 'Source mismatch for ' + path(b, b[ref])
            else:
                assert pa[k] == pb.get(k), 'property %s changed on %s' % (k, path(a, a[ref]))
    for m in new_mods:
        i = b[m['ref']]
        assert i['class'] == 'ModuleScript' and path(b, i) == m['path'], m['path']
        assert i['props']['Source'] == m['source'], m['path']


if __name__ == '__main__':
    src_path, out_path = sys.argv[1], sys.argv[2]
    changed, new_src, new_mods = build(src_path, out_path)
    verify(src_path, out_path, new_src, new_mods)
    print('%d script(s) updated (%d new: %s), %d tracked; wrote %s (%d bytes); verified' % (
        changed, len(new_mods), ', '.join(m['path'] for m in new_mods) or '-', len(new_src), out_path,
        os.path.getsize(out_path)))
