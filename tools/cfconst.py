#!/usr/bin/env python3
# cfconst.py CACHE INSTALL SYMBOL... : the string a CFStringRef constant of an image of a 64-bit shared cache
# holds, read through the symbol: its address from the image's symbol table, the pointer stored there, the
# __cfstring it points at, and the bytes that names. Stored pointers are masked to their address bits (slide
# info v2 keeps chain bits above them).
import mmap, struct, sys
cachefile, install, symbols = sys.argv[1], sys.argv[2], sys.argv[3:]
f = open(cachefile, 'rb'); m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
moff, mcount, ioff, icount = struct.unpack_from('<IIII', m, 16)
maps = [struct.unpack_from('<QQQ', m, moff + 32 * k) for k in range(mcount)]
def off(a):
    for b, s, o in maps:
        if b <= a < b + s: return o + a - b
    return None
def ptr(a):
    raw = struct.unpack_from('<Q', m, off(a))[0]
    value = raw & 0xFFFFFFFFF
    if off(value) is None and off(value + maps[0][0]) is not None: value += maps[0][0]
    return raw, value
def cstr(a):
    o = off(a); e = m.find(b'\0', o, o + 400); return m[o:e].decode('latin-1')
base = None
for k in range(icount):
    addr, _, _, po = struct.unpack_from('<QQQI', m, ioff + 32 * k)
    e = m.find(b'\0', po)
    if m[po:e].decode() == install: base = addr
ncmds = struct.unpack_from('<I', m, off(base) + 16)[0]; lc = off(base) + 32
symtab = None
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', m, lc)
    if cmd == 2: symtab = struct.unpack_from('<IIII', m, lc + 8)
    lc += size
symoff, nsyms, stroff, strsize = symtab
wanted = set(symbols); found = {}
for i in range(nsyms):
    strx, ntype, nsect, ndesc, value = struct.unpack_from('<IBBHQ', m, symoff + 16 * i)
    if ntype & 0x0E == 0x0E:
        name = cstr_name = m[stroff + strx:m.find(b'\0', stroff + strx)].decode('latin-1')
        if name in wanted: found[name] = value
for s in symbols:
    if s not in found: print('%s: not in the symbol table' % s); continue
    raw, cf = ptr(found[s])
    isa_raw, isa = ptr(cf)
    _, chars = ptr(cf + 16)
    length = struct.unpack_from('<Q', m, off(cf + 24))[0]
    print('%s: symbol 0x%x -> __cfstring 0x%x (stored 0x%x) -> 0x%x, length %d: "%s"' % (s, found[s], cf, raw, chars, length, cstr(chars)))
