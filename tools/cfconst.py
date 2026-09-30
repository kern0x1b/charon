#!/usr/bin/env python3
"""cfconst.py CACHE IMAGE SYMBOL... : the string a CFStringRef constant of an image of a shared cache holds.

The symbol's address comes from the image's EXPORT TRIE, the __cfstring it points at is named by the
pointer stored there, and the __cfstring's third word is the address of the bytes and its fourth is
their count. Every symbol asked for that the image does not EXPORT is reported by name and is a
FAILURE, not a silence: this exists to read a release's real constant values, and a name it cannot find
has no value. A name is asked for as C spells it - HKErrorDomain - or as the image exports it, with
the leading underscore; the export trie holds the second, and a caller who spells the first was told
the name was missing when the image carries it.

TWO THINGS about the width, both measured, and both of which this version used to get wrong:

- The pointer in the exported variable is 64 bits and the __cfstring is four 64-bit words. Reading
  them as 32 bits takes the low half of the variable's pointer as an address, and on every arm64 cache
  this workspace holds that address is in no mapping: `address 0x201b26026b8 is in no mapping` on the
  cache of iOS 12.0, `address 0xa1f5c0d0 is in no mapping` on the one of 10.0.1. The 32-bit image is a
  different reader, tools/cfconst/cache32.py, which walks an extracted image's own symbol table.
- Every pointer in the images of a cache carries flags ABOVE the cache's own address space: 0x2 in a
  variable of __DATA,__const, 0x4 in the isa of an __cfstring and in its pointer to the bytes, while
  all three mappings of the cache of iOS 12.0 end below 2^41 and all three of 10.0.1 do too. The mask
  is therefore derived from the cache rather than written down - every mapping's top, rounded up to a
  byte - and a pointer whose masked form lands in no mapping while its whole form does is read whole,
  which is what a cache with no flags in it needs, and the reading used is printed with the value.
"""
import struct
import sys

import dyldcache


def mask_of(cache):
    """The bits an address of THIS cache occupies: above its own top mapping are the flags."""
    top = max(base + size for base, size, _off in cache._maps)
    return (1 << ((top.bit_length() + 7) // 8 * 8)) - 1


def address(cache, word, mask, what):
    """The address a pointer word names, flags masked off, or the word whole if that is what lands."""
    if cache.off(word & mask) is not None:
        return word & mask
    if cache.off(word) is not None:
        return word
    raise dyldcache.CacheError('%s: 0x%x is in no mapping, masked (0x%x) or whole' % (what, word, word & mask))


def main():
    if len(sys.argv) < 4:
        sys.exit('cfconst.py CACHE IMAGE SYMBOL...')
    cache = dyldcache.Cache(sys.argv[1])
    image, wanted = sys.argv[2], sys.argv[3:]
    try:
        exports = cache.exports(image)
    except dyldcache.CacheError as exc:
        sys.exit('%s: %s' % (image, exc))
    # an image of 32 bits has 32-bit pointers and no flags above an address, and nothing here reads them:
    # refusing it by name beats answering off the low half of a pointer that is not an address
    hdr, _hdrsize, _cmds = cache.load_commands(image)
    magic = struct.unpack_from('<I', cache._m, hdr)[0]
    if magic == 0xfeedface:
        sys.exit('%s: a 32-bit image, whose pointers are 32 bits wide and carry no flags. Extract it with '
                 "modules/apple/dyld.lua's extract() and read it with tools/cfconst/cache32.py, which walks "
                 'an extracted image own symbol table' % image)
    mask = mask_of(cache)
    # a name the image does not export is answered by name, as cache32.py answers it, and the run still
    # ends non-zero: a caller that checked the exit code keeps seeing the refusal, and a caller reading
    # a batch keeps the answers for the names the image does carry
    wanted = ['_' + sym.lstrip('_') for sym in wanted]
    missing = [sym for sym in wanted if sym not in exports]
    for sym in missing:
        print('%s\tnot an exported symbol of this image' % sym[1:])
    for name in wanted:
        if name in missing:
            continue
        sym = name[1:]
        # the exported ADDRESS is a VARIABLE in __DATA and the __cfstring is named by the pointer stored
        # there: two different things at two different addresses, so checking the variable's own contents
        # for a __cfstring isa is reading the wrong address, which is what the first version did.
        try:
            variable = cache.require_off(exports[name], 'exported variable for ' + sym)
            cfptr = address(cache, struct.unpack_from('<Q', cache._m, variable)[0], mask,
                            '__cfstring for ' + sym)
            cfo = cache.require_off(cfptr, '__cfstring for ' + sym)
            isa, flags, chars, length = struct.unpack_from('<QQQQ', cache._m, cfo)
            chars = address(cache, chars, mask, 'the bytes of ' + sym)
        except dyldcache.CacheError as exc:
            print('%s\t%s' % (sym, exc))
            continue
        at = cache.off(chars)
        if cache._m[at + length:at + length + 1] != b'\0':
            # the length is Apple's own and the bytes are its own: a run of that many bytes that no NUL
            # closes is not a C string, so the walk landed on the wrong object and says so
            print('%s\tisa 0x%09x, __cfstring at 0x%09x, %d bytes at 0x%09x, which no NUL closes'
                  % (sym, isa & mask, cfptr, length, chars))
            continue
        text = cache._m[at:at + length].decode('utf-8', 'replace')
        print('%s\t0x%09x\t%s\t(%d bytes, flags 0x%x, cfstring 0x%09x)'
              % (sym, exports[name], text, length, flags, cfptr))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())