"""Writes a small compiled asset catalogue of data sets, for the tests of NSDataAsset: a BOM store with the trees a catalogue
holds (FACETKEYS, RENDITIONS, KEYFORMAT and the rest) and a rendition of raw data for every data set."""
import struct
import sys

ELEMENT_DATA, PART_DATA = 85, 181
KEY_FORMAT = [7, 13, 12, 15, 16, 9, 8, 17, 1, 2]
IDIOMS = {"universal": 0, "phone": 1, "pad": 2}


class Store:
    def __init__(self):
        self.blocks = [b""]
        self.variables = []

    def add(self, data):
        self.blocks.append(data)
        return len(self.blocks) - 1

    def tree(self, name, entries, key_size=0xFFFFFFFF):
        leaf = struct.pack(">HHII", 1, len(entries), 0, 0)
        for value, key in entries:
            leaf += struct.pack(">II", self.add(value), self.add(key))
        node = self.add(leaf.ljust(4096, b"\0"))
        self.variables.append((name, self.add(b"tree" + struct.pack(">IIIIBII", 1, node, 4096, len(entries), 0, key_size, 0))))

    def block_variable(self, name, data):
        self.variables.append((name, self.add(data)))

    def write(self, path):
        body = b""
        offsets = []
        base = 32
        for block in self.blocks:
            offsets.append((base + len(body), len(block)))
            body += block
        index = struct.pack(">I", len(self.blocks)) + b"".join(struct.pack(">II", o, l) for o, l in offsets) + struct.pack(">I", 0)
        variables = struct.pack(">I", len(self.variables)) + b"".join(struct.pack(">IB", i, len(n)) + n.encode() for n, i in self.variables)
        index_offset = base + len(body)
        variables_offset = index_offset + len(index)
        header = b"BOMStore" + struct.pack(">IIIIII", 1, len(self.blocks), index_offset, len(index), variables_offset, len(variables))
        with open(path, "wb") as out:
            out.write(header + body + index + variables)


def rendition(name, data, idiom, scale, uti):
    tlv = struct.pack("<II", 0x3EC, 8) + struct.pack("<ff", 0.0, 1.0)
    if uti:
        text = uti.encode() + b"\0"
        tlv += struct.pack("<II", 0x3ED, 8 + len(text)) + struct.pack("<II", len(text), 0) + text
    tlv += struct.pack("<II", 0x3EE, 4) + struct.pack("<I", 1)
    payload = b"DWAR" + struct.pack("<II", 0, len(data)) + data
    csi = b"ISTC" + struct.pack("<IIIIIII", 1, 0, 0, 0, 100, 0x44415441, 0)
    csi += struct.pack("<IHH", 0, 1000, 0) + (name.encode() + b"\0" * 128)[:128]
    csi += struct.pack("<IIII", len(tlv), 1, 0, len(payload)) + tlv + payload
    return csi


def main(path):
    sets = [
        ("Plain", [(b"plain data set\n", "universal", 1, None)]),
        ("Config", [(b'{"key": "value"}\n', "universal", 1, "public.json")]),
        ("Empty", [(b"", "universal", 1, None)]),
        ("Binary", [(bytes(range(256)) * 20, "universal", 1, "public.data")]),
        ("Varied", [(b"universal", "universal", 1, None), (b"phone", "phone", 1, None), (b"pad", "pad", 1, None)]),
    ]
    store = Store()
    header = bytearray(436)
    header[0:4] = b"RATC"
    struct.pack_into("<IIII", header, 4, 970, 17, 0, sum(len(variants) for _, variants in sets))
    header[20:20 + 40] = b"@(#)PROGRAM:CoreUI  PROJECT:CoreUI-970.1"
    store.block_variable("CARHEADER", bytes(header))
    facets, renditions = [], []
    for number, (name, variants) in enumerate(sets):
        identifier = 20000 + number
        facets.append((struct.pack("<HHH", 0, 0, 3) + struct.pack("<HHHHHH", 1, ELEMENT_DATA, 2, PART_DATA, 17, identifier), name.encode()))
        for data, idiom, scale, uti in variants:
            key = {7: 0, 13: 0, 12: scale, 15: IDIOMS[idiom], 16: 0, 9: 0, 8: 0, 17: identifier, 1: ELEMENT_DATA, 2: PART_DATA}
            renditions.append((rendition(name + ".bin", data, idiom, scale, uti), struct.pack("<10H", *[key[a] for a in KEY_FORMAT])))
    store.block_variable("EXTENDED_METADATA", b"META" + bytes(1024))
    store.block_variable("KEYFORMAT", b"tmfk" + struct.pack("<II", 0, len(KEY_FORMAT)) + struct.pack("<%dI" % len(KEY_FORMAT), *KEY_FORMAT))
    store.tree("FACETKEYS", sorted(facets, key=lambda e: e[1]))
    store.tree("RENDITIONS", sorted(renditions, key=lambda e: struct.unpack("<10H", e[1])), 20)
    store.tree("APPEARANCEKEYS", [])
    store.tree("BITMAPKEYS", [])
    store.write(path)


if __name__ == "__main__":
    main(sys.argv[1])
