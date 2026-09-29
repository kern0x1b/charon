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


def read_class(cache, image, class_name):
    want = '_OBJC_CLASS_$_' + class_name
    e = cache.exports(image)
    if want not in e:
        raise SystemExit('%s: %s is not exported by the image' % (image, class_name))
    cls = e[want]
    isa = cache.u32_at(cls)
    if isa != e.get('_OBJC_METACLASS', 0) and cls == 0:
        raise SystemExit('%s: %s has no metaclass pointer' % (image, class_name))
    meta = isa                      # for a class_t, isa is its METACLASS
    ro = cache.u32_at(meta) & ~(1 << 31)   # the low bit is FAST_DATA on 6.1.3
    return cls, meta, ro


def methods(cache, ro, base_off, limit):
    ptr = cache.u32_at(ro + base_off) & ~(1 << 31)
    if not ptr or ptr < limit:
        return []
    count = cache.u32_at(ptr)
    out = []
    entsize = 12 if count < 0x8000 else 20      # method_t is 12 bytes on armv7
    count &= 0x7fff if count >= 0x8000 else 0xffff
    for i in range(count):
        m = ptr + 4 + i * entsize
        nameptr = cache.u32_at(m)
        out.append(cache.string_at(nameptr))
    return out


def main():
    cache = dyldcache.Cache(sys.argv[1])
    image, class_name = sys.argv[2], sys.argv[3]
    cls, meta, ro = read_class(cache, image, class_name)
    print('%s @ 0x%08x   metaclass 0x%08x   class_ro 0x%08x'
          % (class_name, cls, meta, ro))
    # class_ro_t (32-bit): flags, ivarBase, ivarSize, reserved, name, baseMethods...
    # 32-bit class_ro_t: flags, instanceStart, instanceSize, THEN the ivar layout pointer and the name
    # pointer, and baseMethods is the NEXT field - so 20, not 16. The known-present control
    # +defaultMediaLibrary read ABSENT at 16, which is what caught it.
    inst = methods(cache, ro, 20, 1 << 62)
    metar = methods(cache, cache.u32_at(ro) & ~(1 << 31), 20, 1 << 62)
    print('  instance methods (%d):' % len(inst))
    for m in inst: print('    - %s' % m)
    print('  CLASS methods (%d):' % len(metar))
    for m in metar: print('    + %s' % m)
    for probe in ('authorizationStatus', 'requestAuthorization:', 'defaultMediaLibrary',
                  'noSuchSelectorForTheControl'):
        where = []
        if probe in inst: where.append('instance')
        if probe in metar: where.append('class')
        print('  %-28s %s' % (probe, 'present as ' + '+'.join(where) if where else 'ABSENT'))


if __name__ == '__main__':
    main()
