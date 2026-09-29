"""The dyld shared cache reader: address->file offset, the image's load commands, and its export trie.

ONE implementation, used by cfconst.py and by the export-trie walk in the runs-archive copy of
exports.py, so the two cannot disagree about how a cache is read.

Three things this gets right that the callers each got wrong on their own:

* HEADER SIZE FROM THE MAGIC. A Mach-O header is 28 bytes at 32 bits and 32 at 64. These caches hold
  0xfeedface images, and a walk that starts at +32 begins FOUR BYTES INTO COMMAND 0 - after which every
  cmdsize is garbage. The first cmdsize read that way comes back as 1163157343.
* PER-MAPPING TRANSLATION. A cache has several mappings, each with its own (address, size, fileOffset),
  and a file offset means nothing without the mapping it belongs to.
* BOUNDS ON EVERY cmdsize. A size under 8, or a walk that would pass the end, fails naming the image and
  the command instead of reading on.

Export-trie offsets (LC_DYLD_INFO's eo/es) are CACHE-ABSOLUTE FILE OFFSETS in the shared LINKEDIT. The
image base is NOT added to them.
"""
import mmap
import struct


class CacheError(Exception):
    pass


class Cache(object):
    def __init__(self, path):
        self._f = open(path, 'rb')
        self._m = mmap.mmap(self._f.fileno(), 0, access=mmap.ACCESS_READ)
        moff, _mc, ioff, icount = struct.unpack_from('<IIII', self._m, 16)
        self._maps = []
        for k in range(_mc):
            b, s, o = struct.unpack_from('<QQQ', self._m, moff + 32 * k)
            self._maps.append((b, s, o))
        self._images = []
        for k in range(icount):
            addr, _mt, _ino, po = struct.unpack_from('<QQQI', self._m, ioff + 32 * k)
            end = self._m.find(b'\0', po)
            self._images.append((addr, self._m[po:end].decode('latin-1')))

    def off(self, address):
        """address -> file offset, through the mapping that CONTAINS it."""
        for b, s, o in self._maps:
            if b <= address < b + s:
                return o + address - b
        return None

    def require_off(self, address, what):
        o = self.off(address)
        if o is None:
            raise CacheError('%s: address 0x%x is in no mapping' % (what, address))
        return o

    def image_base(self, install):
        for addr, path in self._images:
            if path == install:
                return addr
        raise CacheError('image %s is not in this cache' % install)

    def load_commands(self, install):
        """(file offset of the header, header size, [(cmd, size)]) with every cmdsize bounds-checked."""
        base = self.image_base(install)
        hdr = self.require_off(base, install)
        magic = struct.unpack_from('<I', self._m, hdr)[0]
        if magic == 0xfeedface:
            hdrsize = 28
        elif magic == 0xfeedfacf:
            hdrsize = 32
        else:
            raise CacheError('%s: mach-o magic 0x%08x is neither 32- nor 64-bit' % (install, magic))
        ncmds, sizeofcmds = struct.unpack_from('<II', self._m, hdr + 16)
        end = hdr + hdrsize + sizeofcmds      # sizeofcmds counts from AFTER the header
        cmds, off = [], hdr + hdrsize
        for i in range(ncmds):
            if off + 8 > end:
                raise CacheError('%s: command %d starts at file 0x%x, past the load commands, which end '
                                 'at 0x%x' % (install, i, off, end))
            cmd, size = struct.unpack_from('<II', self._m, off)
            if size < 8 or off + size > end:
                raise CacheError('%s: command %d is 0x%08x at file 0x%x and declares cmdsize %d, which does '
                                 'not fit before the load commands end at 0x%x' % (install, i, cmd, off, size, end))
            cmds.append((cmd, off, size))
            off += size
        return hdr, hdrsize, cmds

    def export_trie(self, install):
        """(file offset, size) of the export trie, from LC_DYLD_INFO(_ONLY). Cache-absolute."""
        _hdr, _hs, cmds = self.load_commands(install)
        for cmd, off, _size in cmds:
            if cmd in (0x22, 0x80000022):
                fl = struct.unpack_from('<10I', self._m, off + 8)
                return fl[8], fl[9]          # eo, es - FILE offsets, no image base added
        raise CacheError('%s: no LC_DYLD_INFO(_ONLY), so it has no export trie' % install)

    def exports(self, install):
        """{symbol name: address} for everything the image EXPORTS.

        The export trie is the standard format: a node is terminalSize as a ULEB128 FIRST, then exactly
        that many bytes of terminal info, then childCount as a single BYTE, then childCount children,
        each an edge label (NUL-terminated) and a child node offset (ULEB128) RELATIVE TO THE TRIE START.

        Reading childCount first is what breaks it: a root whose terminalSize is 0 is read as a node with
        ZERO CHILDREN, so a trie with hundreds of exports looks like a single leaf. The terminal info is
        SKIPPED by terminalSize, and only its address is taken, which is IMAGE-RELATIVE and so gets the
        image base added.
        """
        base = self.image_base(install)
        eo, es = self.export_trie(install)
        limit = eo + es
        m, found, stack = self._m, {}, [(eo, '')]

        def uleb(o):
            r = s = 0
            while True:
                if o >= limit:
                    raise CacheError('the export trie is truncated: a ULEB ran past its end')
                b = m[o]
                o += 1
                r |= (b & 0x7F) << s
                if not (b & 0x80):
                    return r, o
                s += 7

        while stack:
            node, pre = stack.pop()
            terminal_size, after = uleb(node)          # terminalSize comes FIRST
            if terminal_size:
                # the terminal info is flags ULEB then an IMAGE-RELATIVE address ULEB
                _flags, o = uleb(after)
                addr, _o2 = uleb(o)
                found[pre] = base + addr
                o = after + terminal_size             # and is SKIPPED by its size, not parsed whole
            else:
                o = after
            if o >= limit:
                raise CacheError('node at 0x%x has no child-count byte before the trie end 0x%x' % (node, limit))
            child_count = m[o]
            o += 1
            for _ in range(child_count):
                end = m.find(b'\0', o, limit)
                if end < 0:
                    raise CacheError('an edge label before the trie end 0x%x is unterminated' % limit)
                name = m[o:end].decode('latin-1')
                d, o = uleb(end + 1)
                if d:
                    stack.append((eo + d, pre + name))    # offsets are relative to the TRIE START
        return {k: v for k, v in found.items() if k}

    def string_at(self, address):
        o = self.require_off(address, 'a string')
        end = self._m.find(b'\0', o, o + 512)
        return self._m[o:end].decode('latin-1')

    def u64_at(self, address):
        return struct.unpack_from('<Q', self._m, self.require_off(address, 'a pointer'))[0]
