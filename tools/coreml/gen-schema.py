#!/usr/bin/env python3
"""
Turn the CoreML model specification into the C schema table CharonMLSchema.c reads.

Apple's model format is open: coremltools (BSD-3-Clause, Apple Inc.) ships the protobuf
specification the .mlmodel container is written in, as one generated module per .proto file
under coremltools/proto/. Every one of those modules registers its own file descriptor with
`AddSerializedFile(b'...')`, so the specification is read here from the descriptors themselves --
field number, wire type, name, and the type of a message or enum field -- rather than
transcribed by hand. Nothing in the emitted table is invented; it is what protoc was given.

Reads the installed coremltools, writes:
    packages/a/apple-backports/CoreML/CharonMLSchema.inc

Usage:
    python3 tools/coreml/gen-schema.py [--coremltools <site-packages dir>] [--out <file>]
                                        [--check]

--check writes nothing and fails if the checked-in table differs, so a change of coremltools
is a diff the reviewer reads rather than a silent regeneration.
"""
import argparse
import os
import re
import sys

SERIALIZED = re.compile(r"AddSerializedFile\((b'.*?')\)\n", re.S)

# charon_ml_kind_*, in the order CharonMLSchema.h declares them, with the protobuf type each
# names and the wire type a value of it is written with. 0 is CHARON_ML_KIND_NONE, which names
# a field that is neither a number nor a submessage: a repeated field of strings, bytes or
# messages is one entry per element, a packed repeated number is one run.
KIND = {
    "TYPE_DOUBLE": (1, 1), "TYPE_FLOAT": (2, 5), "TYPE_INT64": (3, 0), "TYPE_UINT64": (4, 0),
    "TYPE_INT32": (5, 0), "TYPE_FIXED64": (6, 1), "TYPE_FIXED32": (7, 5), "TYPE_BOOL": (8, 0),
    "TYPE_STRING": (9, 2), "TYPE_BYTES": (10, 2), "TYPE_MESSAGE": (11, 2), "TYPE_GROUP": (11, 3),
    "TYPE_UINT32": (12, 0), "TYPE_ENUM": (13, 0), "TYPE_SFIXED32": (14, 5),
    "TYPE_SFIXED64": (15, 1), "TYPE_SINT32": (16, 0), "TYPE_SINT64": (17, 0),
}

# A field of one of these kinds carries a number of the wire type the reader reads directly;
# a string, bytes, message or group does not (an enum is a varint of its case's number).
NUMERIC = {1, 2, 3, 4, 5, 6, 7, 8, 12, 14, 15, 16, 17}


def descriptors(coremltools):
    from google.protobuf import descriptor_pb2
    directory = os.path.join(coremltools, "proto")
    parsed = []
    for name in sorted(os.listdir(directory)):
        if not name.endswith("_pb2.py"):
            continue
        with open(os.path.join(directory, name), encoding="utf-8") as f:
            match = SERIALIZED.search(f.read())
        if not match:
            # NamedParameters_pb2.py carries no file of its own: it only re-exports messages
            # the model files already define, so it adds no descriptor to read.
            continue
        proto = descriptor_pb2.FileDescriptorProto()
        proto.ParseFromString(eval(match.group(1), {"b": bytes}))  # noqa: S307 - protoc's own literal
        parsed.append((name[:-len("_pb2.py")], proto))
    return parsed


def collect(parsed):
    """messages[name] = list of fields, keyed by the name relative to CoreML.Specification."""
    from google.protobuf import descriptor_pb2
    names = descriptor_pb2.FieldDescriptorProto.Type.Name
    label = descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED
    messages = {}

    def walk(message, prefix):
        fields = []
        for field in message.field:
            kind, wire = KIND[names(field.type)]
            repeated = field.label == label
            # protobuf3 packs a repeated field of a packable number type: every numeric one,
            # but no string, no bytes, no message and no group.
            fields.append({
                "name": field.name,
                "number": field.number,
                # A packed repeated field is written as one length-delimited run of its
                # elements, not as one entry per element, so the wire type the reader matches
                # against is the run's -- the element's own width is in `element`.
                "wire": 2 if repeated and kind in NUMERIC else wire,
                "kind": kind,
                # A packed repeated field arrives as one run of the element's wire type; a
                # repeated field that is not packed arrives as one entry per element, and its
                # kind is then the element's own.
                "element": kind if repeated and kind in NUMERIC else 0,
                "type": field.type_name.lstrip("."),
                "repeated": repeated,
                "oneof": field.oneof_index if field.HasField("oneof_index") else -1,
            })
        messages[prefix + message.name] = fields
        for nested in message.nested_type:
            walk(nested, prefix + message.name + ".")

    for _, proto in parsed:
        for message in proto.message_type:
            walk(message, "")
    return messages


def c_string(text):
    return '"%s"' % "".join(c if 32 <= ord(c) < 127 and c not in '"\\' else "\\%03o" % ord(c) for c in text)


def emit(messages, source):
    lines = [
        "/* Generated by tools/coreml/gen-schema.py from the protobuf specification Apple ships in",
        "   coremltools. Do not edit by hand: run the generator and read the diff.",
        "   Source: %s */" % source,
        "",
        "const charon_ml_field charon_ml_fields[] = {",
    ]
    layout, index = [], 0
    # Every message of the specification is in the table, including the ones with no fields:
    # a message that declares none is still a message an empty submessage of that type is, and
    # a reader that had no row for it would refuse the container that carries one.
    for name in sorted(messages):
        fields = messages[name]
        layout.append((name, index, len(fields)))
        for field in fields:
            lines.append("    {%s, %d, %d, %d, %d, %s, %s}," % (
                c_string(field["name"]), field["number"], field["wire"],
                field["kind"], field["element"], c_string(field["type"]),
                " | ".join(filter(None, [
                    "CHARON_ML_REPEATED" if field["repeated"] else "",
                    "CHARON_ML_ONEOF(%d)" % field["oneof"] if field["oneof"] >= 0 else "",
                ])) or "0"))
            index += 1
    lines += [
        "};",
        "",
        "const charon_ml_message charon_ml_messages[] = {",
    ]
    for name, first, count in layout:
        lines.append("    {%s, %d, %d}," % (c_string(name), first, count))
    lines += [
        "};",
        "",
        "const unsigned charon_ml_message_count = %d;" % len(layout),
        "const unsigned charon_ml_field_count = %d;" % index,
    ]
    return "\n".join(lines) + "\n"


def main():
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    parser = argparse.ArgumentParser()
    parser.add_argument("--coremltools", default=None)
    parser.add_argument("--out", default=os.path.join(here, "packages", "a", "apple-backports", "CoreML", "CharonMLSchema.inc"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    root = args.coremltools
    if root is None:
        import coremltools
        root = os.path.dirname(os.path.realpath(coremltools.__file__))
    parsed = descriptors(root)
    messages = collect(parsed)
    version = getattr(__import__("coremltools"), "__version__", "?")
    source = "coremltools %s, its %d .proto descriptors, %d messages" % (version, len(parsed), len(messages))
    text = emit(messages, source)

    if args.check:
        with open(args.out, encoding="utf-8") as f:
            current = f.read()
        if current != text:
            print("differs: %s is not what this coremltools describes" % args.out, file=sys.stderr)
            return 1
        print("matches: %s" % args.out)
        return 0
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote %s: %d messages, %d fields" % (
        args.out, len(messages), sum(1 for line in text.splitlines() if line.startswith("    {\""))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
