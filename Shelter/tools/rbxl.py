import struct, sys, os, json
import lz4.block, zstandard

def interleave(data, n, w):
    out = []
    for i in range(n):
        v = 0
        for b in range(w):
            v = (v << 8) | data[b * n + i]
        out.append(v)
    return out

def zz(x):
    return (x >> 1) ^ -(x & 1)

def rfloat(x):
    x = ((x >> 1) | ((x & 1) << 31)) & 0xffffffff
    return struct.unpack('<f', struct.pack('<I', x))[0]

class R:
    def __init__(self, b):
        self.b = b; self.p = 0
    def u8(self):
        v = self.b[self.p]; self.p += 1; return v
    def u32(self):
        v = struct.unpack_from('<I', self.b, self.p)[0]; self.p += 4; return v
    def i32(self):
        v = struct.unpack_from('<i', self.b, self.p)[0]; self.p += 4; return v
    def f32(self):
        v = struct.unpack_from('<f', self.b, self.p)[0]; self.p += 4; return v
    def f64(self):
        v = struct.unpack_from('<d', self.b, self.p)[0]; self.p += 8; return v
    def raw(self, n):
        v = self.b[self.p:self.p + n]; self.p += n; return v
    def s(self):
        n = self.u32(); return self.raw(n)
    def refs(self, n):
        vals = interleave(self.raw(n * 4), n, 4)
        out = []; acc = 0
        for v in vals:
            acc += zz(v); out.append(acc)
        return out
    def ints(self, n):
        return [zz(v) for v in interleave(self.raw(n * 4), n, 4)]
    def u32s(self, n):
        return interleave(self.raw(n * 4), n, 4)
    def floats(self, n):
        return [rfloat(v) for v in interleave(self.raw(n * 4), n, 4)]

def load(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'<roblox!'
    p = 32
    classes = {}  # id -> (name, refs)
    inst = {}  # ref -> dict
    sstrs = []
    while p < len(data):
        name = data[p:p + 4]; clen, ulen, _ = struct.unpack_from('<III', data, p + 4); p += 16
        if clen == 0:
            body = data[p:p + ulen]; p += ulen
        else:
            comp = data[p:p + clen]; p += clen
            if comp[:4] == b'\x28\xb5\x2f\xfd':
                body = zstandard.ZstdDecompressor().decompress(comp, max_output_size=ulen)
            else:
                body = lz4.block.decompress(comp, uncompressed_size=ulen)
        r = R(body)
        if name == b'SSTR':
            r.u32(); n = r.u32()
            for _ in range(n):
                r.raw(16); sstrs.append(r.s())
        elif name == b'INST':
            cid = r.u32(); cname = r.s().decode(); fmt = r.u8(); n = r.u32()
            refs = r.refs(n)
            classes[cid] = (cname, refs)
            for ref in refs:
                inst[ref] = {'ref': ref, 'class': cname, 'props': {}, 'children': [], 'parent': None}
        elif name == b'PROP':
            cid = r.u32(); pname = r.s().decode(); t = r.u8()
            cname, refs = classes[cid]; n = len(refs)
            vals = None
            try:
                if t == 0x01:
                    vals = [r.s() for _ in range(n)]
                elif t == 0x02:
                    vals = [bool(x) for x in r.raw(n)]
                elif t == 0x03:
                    vals = r.ints(n)
                elif t == 0x04:
                    vals = r.floats(n)
                elif t == 0x05:
                    vals = [r.f64() for _ in range(n)]
                elif t == 0x0B or t == 0x12:
                    vals = r.u32s(n)
                elif t == 0x0C:
                    a, b, c = r.floats(n), r.floats(n), r.floats(n)
                    vals = list(zip(a, b, c))
                elif t == 0x0E:
                    a, b, c = r.floats(n), r.floats(n), r.floats(n)
                    vals = list(zip(a, b, c))
                elif t == 0x13:
                    vals = r.refs(n)
                elif t == 0x10:
                    rots = []
                    for _ in range(n):
                        rid = r.u8()
                        if rid == 0:
                            rots.append([r.f32() for _ in range(9)])
                        else:
                            rots.append(rid)
                    a, b, c = r.floats(n), r.floats(n), r.floats(n)
                    vals = list(zip(a, b, c))  # position only
                elif t == 0x1C:
                    vals = r.u32s(n)
                    vals = [sstrs[v] if v < len(sstrs) else None for v in vals]
                elif t == 0x1D:
                    vals = [r.s() for _ in range(n)]
                elif t == 0x07:
                    sx, sy = r.floats(n), r.floats(n)
                    ox, oy = r.ints(n), r.ints(n)
                    vals = list(zip(sx, ox, sy, oy))
            except Exception as e:
                vals = None
            if vals is not None:
                for ref, v in zip(refs, vals):
                    inst[ref]['props'][pname] = v
        elif name == b'PRNT':
            r.u8(); n = r.u32()
            ch = r.refs(n); pa = r.refs(n)
            for c, pr in zip(ch, pa):
                inst[c]['parent'] = pr
                if pr in inst:
                    inst[pr]['children'].append(c)
        elif name == b'END\x00':
            break
    return inst

def nm(i):
    v = i['props'].get('Name', b'?')
    return v.decode('utf-8', 'replace') if isinstance(v, bytes) else str(v)

def path(inst, i):
    parts = []
    while i is not None:
        parts.append(nm(i))
        i = inst.get(i['parent']) if i['parent'] is not None else None
    return '.'.join(reversed(parts))

if __name__ == '__main__':
    inst = load(sys.argv[1])
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    roots = [i for i in inst.values() if i['parent'] is None or i['parent'] not in inst]
    skip_classes = set()
    with open(os.path.join(out, 'tree.txt'), 'w') as f:
        def walk(i, d):
            # collapse large homogeneous child sets
            f.write('  ' * d + f"{nm(i)} [{i['class']}]\n")
            kids = [inst[c] for c in i['children']]
            from collections import Counter
            cnt = Counter((k['class']) for k in kids)
            shown = Counter()
            for k in kids:
                big = cnt[k['class']] > 15 and not k['children'] and k['class'] in ('Part', 'MeshPart', 'UnionOperation', 'WedgePart', 'Decal', 'Texture', 'Weld', 'WeldConstraint', 'Attachment', 'Motor6D', 'SpecialMesh', 'TrussPart', 'CornerWedgePart', 'Seat', 'PointLight', 'SurfaceAppearance')
                if big:
                    shown[k['class']] += 1
                    if shown[k['class']] == 1:
                        f.write('  ' * (d + 1) + f"... {cnt[k['class']]} x [{k['class']}] (leaf, collapsed)\n")
                    continue
                walk(k, d + 1)
        for r in roots:
            walk(r, 0)
    sdir = os.path.join(out, 'scripts'); os.makedirs(sdir, exist_ok=True)
    idx = []
    for i in inst.values():
        if i['class'] in ('Script', 'LocalScript', 'ModuleScript'):
            p = path(inst, i)
            src = i['props'].get('Source', b'')
            if isinstance(src, bytes):
                src = src.decode('utf-8', 'replace')
            ext = {'Script': '.server.lua', 'LocalScript': '.client.lua', 'ModuleScript': '.lua'}[i['class']]
            fn = p.replace('/', '_') + ext
            k = 1
            while os.path.exists(os.path.join(sdir, fn)):
                k += 1; fn = p.replace('/', '_') + f'__{k}' + ext
            with open(os.path.join(sdir, fn), 'w') as g:
                g.write(src)
            props = {k2: v for k2, v in i['props'].items() if k2 in ('Disabled', 'Enabled', 'RunContext', 'LinkedSource')}
            idx.append((p, i['class'], len(src.splitlines()), fn, {k2: (v.decode() if isinstance(v, bytes) else v) for k2, v in props.items()}))
    with open(os.path.join(out, 'scripts.txt'), 'w') as f:
        for e in sorted(idx):
            f.write(f"{e[2]:6d}  {e[1]:12s} {e[0]}  {e[4]}\n")
    from collections import Counter
    c = Counter(i['class'] for i in inst.values())
    with open(os.path.join(out, 'classes.txt'), 'w') as f:
        for k, v in c.most_common():
            f.write(f"{v:7d} {k}\n")
    print(len(inst), 'instances,', len(idx), 'scripts')
