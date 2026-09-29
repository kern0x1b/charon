#!/usr/bin/env python3
"""cfconst.py CACHE IMAGE SYMBOL... : the string a CFStringRef constant of an image holds.

The symbol's address comes from the image's EXPORT TRIE, the __cfstring it points at is a 32-bit
pointer, and the bytes that name it are read through the shared reader's per-mapping translation. Every
symbol asked for that the image does not EXPORT is reported by name and is a FAILURE, not a silence:
this exists to read a release's real constant values, and a name it cannot find has no value.
"""
import struct
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
        # the exported ADDRESS is a VARIABLE in __DATA; a 32-bit pointer there is the __cfstring, and the
        # two are different things at different addresses - checking the variable's own contents for a
        # __cfstring isa is reading the wrong address, which is what the first version did.
        cfptr = cache.u32_at(addr)
        cfo = cache.require_off(cfptr, '__cfstring for ' + sym)
        isa, flags, chars, length = struct.unpack_from('<IIII', cache._m, cfo)
        text = cache.string_at(chars)
        print('%s\t0x%08x\t%s\t(%d bytes, flags 0x%x, cfstring 0x%08x)'
              % (sym, addr, text, length, flags, cfptr))


if __name__ == '__main__':
    main()
