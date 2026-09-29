#!/usr/bin/env python3
"""cfconst.py CACHE IMAGE SYMBOL... : the string a CFStringRef constant of an image holds.

The symbol's address comes from the image's EXPORT TRIE, the __cfstring it points at is a 32-bit
pointer, and the bytes that name it are read through the shared reader's per-mapping translation. Every
symbol asked for that the image does not EXPORT is reported by name and is a FAILURE, not a silence:
this exists to read a release's real constant values, and a name it cannot find has no value.
"""
import sys

import dyldcache


def main():
    if len(sys.argv) < 4:
        sys.exit('cfconst.py CACHE IMAGE SYMBOL...')
    cache = dyldcache.Cache(sys.argv[1])
    image, wanted = sys.argv[2], sys.argv[3:]
    try:
        exports = cache.exports(image)
    except dyldcache.CacheError as exc:
        sys.exit('%s: %s' % (image, exc))
    missing = [s for s in wanted if s not in exports]
    if missing:
        sys.exit('%s: not exported by the image, and a symbol with no export has no address to follow: %s'
                 % (image, ', '.join(missing)))
    for sym in wanted:
        addr = exports[sym]
        # the __cfstring is a POINTER to the object, at the symbol's address
        isa = cache.u32_at(addr)
        if isa != 1:
            sys.exit('%s: the value at 0x%08x is 0x%08x, not the isa of a __cfstring'
                     % (sym, addr, isa))
        flags = cache.u32_at(addr + 4)
        length = cache.u32_at(addr + 8)
        pointer = cache.u32_at(addr + 12) & 0xFFFFFFFFF   # the stored pointer keeps chain bits
        text = cache.string_at(pointer)
        print('%s\t0x%08x\t%s\t(%d bytes, flags 0x%x)' % (sym, addr, text, length, flags))


if __name__ == '__main__':
    main()
