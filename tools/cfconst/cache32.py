#!/usr/bin/env python3
"""cfconst32.py IMAGE SYMBOL... : the string each exported NSString constant of a 32-bit
Mach-O holds, read through the symbol.

The symbol's address comes from the image's symbol table, the pointer stored there names an
__cfstring, and the __cfstring's third word is the address of the bytes. An NSString constant
of Apple's is exactly that: a __cfstring whose bytes are the constant's value.
"""
import struct, sys

path = sys.argv[1]
symbols = sys.argv[2:]
data = open(path, "rb").read()

def u32(at):
    return struct.unpack_from("<I", data, at)[0]

magic = struct.unpack_from("<I", data, 0)[0]
if magic != 0xFEEDFACE:
    raise SystemExit("not a 32-bit Mach-O: %08x" % magic)
ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
segments, symtab = [], None
at = 28
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", data, at)
    if cmd == 0x1:
        name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags = struct.unpack_from("<16s8I", data, at + 8)
        segments.append((name.rstrip(b"\0").decode(), vmaddr, vmsize, fileoff, filesize))
    elif cmd == 0x2:
        symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, at + 8)
        symtab = (symoff, nsyms, stroff, strsize)
    at += size
if symtab is None:
    raise SystemExit("no LC_SYMTAB")
symoff, nsyms, stroff, strsize = symtab

def fileoff(vmaddr):
    for name, base, size, off, filesize in segments:
        if base <= vmaddr < base + size and vmaddr < base + filesize:
            return off + (vmaddr - base)
    return None

def cstring(vmaddr):
    off = fileoff(vmaddr)
    if off is None:
        return None
    end = data.find(b"\0", off, off + 4096)
    return data[off:end].decode("utf-8", "replace")

def cstring_at(off):
    end = data.find(b"\0", off, off + 4096)
    return data[off:end].decode("utf-8", "replace")

def pointer(vmaddr):
    off = fileoff(vmaddr)
    if off is None:
        return None
    return u32(off)

addresses = {}
for i in range(nsyms):
    strx, ntype, nsect, ndesc, value = struct.unpack_from("<IBBhI", data, symoff + 12 * i)
    if ntype & 0x0E != 0x0E:
        continue
    name = cstring_at(stroff + strx)
    if name.lstrip("_") in symbols:
        addresses[name.lstrip("_")] = value

for symbol in symbols:
    name = "_" + symbol
    if symbol not in addresses:
        print("%s: not an exported symbol of this image" % symbol)
        continue
    cf = pointer(addresses[symbol])
    if cf is None:
        print("%s: symbol 0x%x does not land in a mapped segment" % (symbol, addresses[symbol]))
        continue
    chars = pointer(cf + 8)
    if chars is None or fileoff(cf + 12) is None:
        print("%s: symbol 0x%x -> 0x%x, which names no __cfstring" % (symbol, addresses[symbol], cf))
        continue
    length = u32(fileoff(cf + 12))
    value = cstring(chars) if chars is not None else None
    if value is None or len(value) != length:
        print("%s: symbol 0x%x -> 0x%x, whose __cfstring holds no C string of length %d"
              % (symbol, addresses[symbol], cf, length))
        continue
    print("%s\t%s" % (symbol, value))
