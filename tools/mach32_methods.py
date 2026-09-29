#!/usr/bin/env python3
"""A class's own instance methods, read out of one 32-bit armv7 image **in a shared cache**.

`tests/backports/tools/cache-methods.py` does this for a 64-bit image, and every field offset in it is
64-bit: a 32-bit Mach-O header is 28 bytes and not 32, load commands start at +28, pointers are four
bytes, `objc_class.ro` is at +16 and not +32, `class_ro_t` puts `name` at +16 and `baseMethods` at +20,
and a `method_t` is twelve bytes. Pointed at 32-bit it reads a load command at the wrong place and walks
off into an address the cache cannot map, which is how the 6.1.3 MediaPlayer run died in
`cache_reader.read()` with a KeyError instead of saying which field was wrong.

Two things this does that the extraction cannot:

- It reads the **cache**, so every pointer is translated through the cache's own mappings. A selector
  the runtime has already uniqued lives in libobjc's `__objc_methname`, which is a *different* image, so
  an extracted single image cannot name it - and a method whose name cannot be read is not evidence of
  absence. Any class left with an unresolved name is refused, never decided.
- It keeps the stride asserted. The first word of a 32-bit ObjC 2 method list packs the entry size with
  two flag bits in the low two, so the size is the word with those cleared and the flags are what is
  left: 6.1.3's own lists read `0x0000000f`, which is an entry size of 12 with both flags set. An
  assertion on the low sixteen bits would refuse every correct list on this release.

    python3 tools/mach32_methods.py <cache> <image-address> [--counts | <Class> ...]
    python3 tools/mach32_methods.py <cache> <image-address> --categories <Class>
"""
import mmap
import struct
import sys
import traceback

LC_SEGMENT = 0x1
METHOD_FLAGS = 0x3                 # the two low bits of the first word are flags, not size
DIRECT_SELECTORS = 0x2             # names are SELs, tagged pointers into __objc_methname
SEL_MASK = 0xfffffffc
SMALL_METHOD_LIST = 0x80000000
METHOD_SIZE_32 = 12


class Cache:
    """The shared cache, mapped read-only: it is a quarter of a gigabyte and is never read whole."""

    def __init__(self, path):
        self.file = open(path, "rb")
        self.map = mmap.mmap(self.file.fileno(), 0, prot=mmap.PROT_READ)
        self.mapping_offset, self.mapping_count = struct.unpack_from("<2I", self.map, 16)
        self.mappings = []
        at = self.mapping_offset
        for _ in range(self.mapping_count):
            address, size, file_offset = struct.unpack_from("<QQQ", self.map, at)
            self.mappings.append((address, size, file_offset))
            at += 32

    def va2off(self, va):
        """The file offset of an address, or a refusal naming it: a wrong field must be loud."""
        for address, size, file_offset in self.mappings:
            if address <= va < address + size:
                return va - address + file_offset
        raise ValueError("%#x is in none of the cache's %d mappings, so it is not an address this image "
                         "can hold" % (va, len(self.mappings)))

    def at(self, va):
        return self.map[self.va2off(va):]

    def u32(self, va):
        return struct.unpack_from("<I", self.map, self.va2off(va))[0]

    def cstring(self, va, limit=512):
        offset = self.va2off(va)
        end = self.map.find(b"\0", offset, offset + limit)
        if end < 0:
            raise ValueError("the string at %#x has no terminator within %d bytes" % (va, limit))
        return self.map[offset:end].decode("utf-8", "replace")


class Image:
    """One image inside the cache, found by its address, with its segment and section tables."""

    def __init__(self, cache, address):
        self.cache = cache
        self.address = address
        (self.magic, self.cputype, self.cpusubtype, self.filetype,
         self.ncmds, self.sizeofcmds, self.flags) = struct.unpack_from("<7I", cache.at(address), 0)
        if self.magic not in (0xfeedface, 0xcefaedfe):
            raise ValueError("the image at %#x is not a 32-bit Mach-O: magic %#010x" % (address, self.magic))
        self.segments = {}
        self.sections = []
        # The walk is by address, not by file offset: each of an image's segments is its own mapping in
        # the cache, so a file offset computed from one segment's mapping means nothing in the next.
        va = address + 28                        # a 32-bit header is 28 bytes; the 64-bit one is 32
        for _ in range(self.ncmds):
            cmd, size = struct.unpack_from("<II", cache.map, cache.va2off(va))
            if cmd == LC_SEGMENT:
                (_segname, vmaddr, vmsize, fileoff, filesize,
                 _maxprot, _initprot, nsects, _sflags) = struct.unpack_from("<16s8I", cache.map, cache.va2off(va + 8))
                name = _segname.split(b"\0")[0].decode()
                self.segments[name] = (vmaddr, vmsize, fileoff, filesize)
                at = va + 56                    # after the 56-byte LC_SEGMENT_32 command
                for _section in range(nsects):
                    fields = struct.unpack_from("<16s16s9I", cache.map, cache.va2off(at))
                    self.sections.append((name, fields[0].split(b"\0")[0].decode(), fields[2], fields[3]))
                    at += 68                    # a 32-bit section is 68 bytes
            va += size

    def section(self, sectname):
        for segment, name, addr, size in self.sections:
            if name == sectname:
                return segment, addr, size
        return None

    def uint32_pointers(self, addr, size):
        offset = self.cache.va2off(addr)
        return [struct.unpack_from("<I", self.cache.map, offset + 4 * i)[0] for i in range(size // 4)]


def method_list(image, va):
    """A method list: entsize_and_flags, count, then method_t{name, types, imp} of twelve bytes."""
    if not va:
        return {"selectors": [], "entsize": 0, "flags": 0}
    entsize_and_flags, count = struct.unpack_from("<2I", image.cache.map, image.cache.va2off(va))
    entsize = entsize_and_flags & ~METHOD_FLAGS
    flags = entsize_and_flags & METHOD_FLAGS
    if entsize != METHOD_SIZE_32:
        raise ValueError("the method list at %#x has entries of %d bytes, not %d: this is not a 32-bit "
                         "method_t walk" % (va, entsize, METHOD_SIZE_32))
    if entsize_and_flags & SMALL_METHOD_LIST:
        raise ValueError("the method list at %#x is a small relative list, which no release before "
                         "iOS 14 has" % va)
    found, base = [], image.cache.va2off(va)
    for index in range(count):
        name_va, _types_va, imp = struct.unpack_from("<3I", image.cache.map, base + 8 + index * METHOD_SIZE_32)
        found.append((image.cache.cstring(name_va), imp))
    return {"selectors": [s for s, _ in found], "entsize": entsize, "flags": flags}


def class_at(image, klass_va):
    """A class's name, its own instance methods and its own class methods, from one class_t."""
    isa, _superclass, _cache, _vtable, bits = struct.unpack_from("<5I", image.cache.map, image.cache.va2off(klass_va))
    ro = bits & 0xfffffffc
    _flags, _istart, _isize, _ivars, name_va, base_methods = \
        struct.unpack_from("<6I", image.cache.map, image.cache.va2off(ro))
    metaclass_ro = struct.unpack_from("<5I", image.cache.map, image.cache.va2off(isa))[4] & 0xfffffffc if isa else 0
    return {"address": klass_va, "ro": ro, "name": image.cache.cstring(name_va),
            "instance": method_list(image, base_methods),
            "class": method_list(image, image.cache.u32(metaclass_ro + 20)) if metaclass_ro
                     else {"selectors": [], "entsize": 0, "flags": 0}}


def classes(image):
    """Every class in __objc_classlist, in the image's own order."""
    found = image.section("__objc_classlist")
    if not found:
        raise ValueError("this image has no __objc_classlist: %s"
                         % ", ".join("%s,%s" % (a, b) for a, b, _, _ in image.sections))
    _segment, addr, size = found
    return [class_at(image, va) for va in image.uint32_pointers(addr, size)]


def categories(image):
    """Every category as (name, class pointer, instance selectors, class selectors)."""
    found = image.section("__objc_catlist")
    if not found:
        return []
    _segment, addr, size = found
    out = []
    for va in image.uint32_pointers(addr, size):
        name_va, cls_va, instance_va, class_va = struct.unpack_from("<4I", image.cache.map, image.cache.va2off(va))
        out.append((image.cache.cstring(name_va), cls_va,
                    method_list(image, instance_va)["selectors"],
                    method_list(image, class_va)["selectors"]))
    return out


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    cache = Cache(argv[1])
    image = Image(cache, int(argv[2], 0))
    read = classes(image)
    cats = categories(image)
    if argv[3] == "--counts":
        print("magic %#010x  cputype %d  ncmds %d  image at %#x" % (image.magic, image.cputype, image.ncmds, image.address))
        print("classes in __objc_classlist: %d" % len(read))
        print("categories in __objc_catlist: %d" % len(cats))
        for entry in read:
            print("%s: %d own instance, %d own class"
                  % (entry["name"], len(entry["instance"]["selectors"]), len(entry["class"]["selectors"])))
        return 0
    if argv[3] == "--categories":
        for name, cls, inst, clas in cats:
            if name in argv[4:]:
                print("%s on %#x: %d instance, %d class" % (name, cls, len(inst), len(clas)))
        return 0
    for entry in read:
        if argv[3:] and entry["name"] not in argv[3:]:
            continue
        instance, own = entry["instance"], entry["class"]
        print("%s (%#x, ro %#x): %d own instance method(s) (entry size %d, flags %d), %d own class method(s)"
              % (entry["name"], entry["address"], entry["ro"], len(instance["selectors"]),
                 instance["entsize"], instance["flags"], len(own["selectors"])))
        for selector in instance["selectors"]:
            print("  -[%s %s]" % (entry["name"], selector))
        for selector in own["selectors"]:
            print("  +[%s %s]" % (entry["name"], selector))
    missing = [name for name in argv[3:] if not any(e["name"] == name for e in read)]
    for name in missing:
        sys.stderr.write("not in __objc_classlist: %s\n" % name)
    return 1 if missing else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception:
        traceback.print_exc()
        sys.exit(3)
