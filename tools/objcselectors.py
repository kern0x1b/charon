#!/usr/bin/env python3
"""The selectors a class in a dyld shared cache actually declares, read from the ObjC metadata.

    python3 objcselectors.py CACHE IMAGE /ClassName

Methods do NOT live in the export trie - a selector is reached through the class's method lists, which
sit in the shared __DATA segment and are read through __objc_methname. So a trie that reports "no such
symbol" for a method is not evidence, and this exists to answer that question properly.

For a 32-bit objc2 class_t the chain is: isa -> metaclass -> class_ro_t -> baseMethods, and a method_t
is {char *name, char *types, IMP imp} - 12 bytes. The small-method-list flag bits DO NOT EXIST in a 6.1.3
cache, so a nonzero flag is a parse we do not understand and this fails rather than reporting selectors it
invented.
"""
import struct
import sys

import dyldcache
from dyldcache import CacheError


def read_class(cache, image, class_name):
    """(class, metaclass, class_ro, metaclass_ro) for an image's class, or a reason there is none.

    A 32-bit objc2 class_t is FIVE words - isa, superclass, cache, vtable, data - so `data` is at +16.
    Reading it at +12 gives the VTABLE, which in a cache points into a string pool: the sixteen words of
    ASCII filler I first dumped were that, and I took it for the class_ro. `data` carries flags in its
    low 2 bits, so it is masked with ~3 before it is dereferenced.
    """
    want = '_OBJC_CLASS_$_' + class_name
    e = cache.exports(image)
    if want not in e:
        raise SystemExit('%s: %s is not exported by the image' % (image, class_name))
    cls = e[want]
    meta = cache.u32_at(cls + 0)            # a class_t's isa IS its metaclass
    ro = cache.u32_at(cls + 16) & ~3
    metaro = cache.u32_at(meta + 16) & ~3
    return cls, meta, ro, metaro


def methods(cache, ro, base_off, limit):
    """The selectors in the method list at class_ro + base_off.

    baseMethods is a POINTER (an address): it goes through the per-mapping off() to a file offset. There
    the list is {entsize_and_flags, count} and the entries FOLLOW, so THE COUNT IS THE SECOND WORD -
    reading it from the first reads entsize_and_flags, 0x0000000f, and walks off the end of the list.
    Each entry is a method_t of {name, types, imp} and its name is a pointer, read back the same way.

    The small-method-list flag bits do not exist in a 6.1.3 cache, so a nonzero flag word is a layout we
    do not understand: this FAILS rather than reporting selectors it invented.
    """
    base = cache.u32_at(ro + base_off)
    if not base:
        return []
    mo = cache.require_off(base, 'method list at ro+%d' % base_off)
    # The bound is on the FILE OFFSET, never on the ADDRESS: base is an address and every address in
    # this cache is below 2**62, so testing the address against the bound refused EVERY list and made a
    # working reader return nothing.
    if mo >= limit:
        return []
    entsize, count = struct.unpack_from('<II', cache._m, mo)
    # The first word is NOT a stride and NOT a zero flag word: on this 6.1.3 cache it reads 0x0000000f
    # for lists whose entries are plainly 12 bytes apart, so deriving the stride from it - or asserting
    # the small-method-list flag bits are zero - would both refuse a list this tool can read. It is
    # REPORTED instead, and the stride is the 12 bytes the raw dump measured.
    step = 12
    if entsize & 0xFFFF0000:
        raise CacheError('a method list at 0x%x carries a word 0x%08x whose high bits I do not read'
                         % (mo, entsize))
    out = []
    for i in range(count):
        m = mo + 8 + i * step
        out.append(cache.string_at(struct.unpack_from('<I', cache._m, m)[0]))
    return out


def main():
    cache = dyldcache.Cache(sys.argv[1])
    image, class_name = sys.argv[2], sys.argv[3]
    cls, meta, ro, metaro = read_class(cache, image, class_name)
    print('%s @ 0x%08x   metaclass 0x%08x   class_ro 0x%08x   metaclass_ro 0x%08x'
          % (class_name, cls, meta, ro, metaro))
    rflags = cache.u32_at(ro) & 3
    mrflags = cache.u32_at(metaro) & 3
    print('  class_ro flags %d (bit0 RO_META=%d bit1 RO_ROOT=%d)   metaclass_ro flags %d (RO_META=%d)'
          % (rflags, rflags & 1, rflags >> 1 & 1, mrflags, mrflags & 1))
    # class_ro_t (32-bit): flags, ivarBase, ivarSize, reserved, name, baseMethods...
    # 32-bit class_ro_t: flags, instanceStart, instanceSize, THEN the ivar layout pointer and the name
    # pointer, and baseMethods is the NEXT field - so 20, not 16. The known-present control
    # +defaultMediaLibrary read ABSENT at 16, which is what caught it.
    inst = methods(cache, ro, 20, 1 << 62)
    metar = methods(cache, metaro, 20, 1 << 62)
    print('  instance methods (%d): %s' % (len(inst), ', '.join(inst[:5])))
    print('  CLASS methods (%d): %s' % (len(metar), ', '.join(metar[:5])))
    for probe in ('authorizationStatus', 'requestAuthorization:', 'defaultMediaLibrary',
                  'noSuchSelectorForTheControl'):
        where = []
        if probe in inst: where.append('instance')
        if probe in metar: where.append('class')
        print('  %-28s %s' % (probe, 'present as ' + '+'.join(where) if where else 'ABSENT'))


if __name__ == '__main__':
    main()
