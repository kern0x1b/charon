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
hdr = off(base)
# THE HEADER IS 28 BYTES FOR A 32-BIT MACH-O AND 32 FOR 64-BIT, and the size comes from the magic
# rather than from an assumption. The 6.1.3 cache's images are 0xfeedface - 32-bit - so a walk that
# starts at +32 begins FOUR BYTES INTO COMMAND 0, and every size read after that is garbage: the first
# "cmdsize" comes back as 1163157343 and the next offset leaves the file entirely.
magic = struct.unpack_from('<I', m, hdr)[0]
if magic == 0xfeedface: hdrsize = 28
elif magic == 0xfeedfacf: hdrsize = 32
else: sys.exit('%s: mach-o magic 0x%08x at file 0x%x is neither 32- nor 64-bit' % (install, magic, hdr))
ncmds, sizeofcmds = struct.unpack_from('<II', m, hdr + 16)
# sizeofcmds counts the load commands from AFTER the header, so the end is hdr + hdrsize + sizeofcmds.
# Reading it as hdr + sizeofcmds is short by exactly the header size, and the last command then trips the
# bounds check on a file that is in fact fine.
end = hdr + hdrsize + sizeofcmds; lc = hdr + hdrsize
symtab = None
for i in range(ncmds):
    if lc + 8 > end:
        sys.exit('%s: command %d starts at file 0x%x, past the load commands, which end at 0x%x'
                 % (install, i, lc, end))
    cmd, size = struct.unpack_from('<II', m, lc)
    if size < 8 or lc + size > end:
        sys.exit('%s: command %d is 0x%08x at file 0x%x and declares cmdsize %d, which does not fit '
                 'before the load commands end at 0x%x' % (install, i, cmd, lc, size, end))
    if cmd == 2: symtab = struct.unpack_from('<IIII', m, lc + 8)
    lc += size
if symtab is None: sys.exit('%s: no LC_SYMTAB in %d commands' % (install, ncmds))
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
