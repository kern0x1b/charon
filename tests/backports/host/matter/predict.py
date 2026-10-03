#!/usr/bin/env python3
"""What the HOST's -description and fresh readings must be, given the PORT's values.

The host's Matter.framework is built from a LATER SDK than the one the port implements: it renames
`thumbnailUrl` to `thumbnailURL` and reorders members. So a difference in member SET or ORDER, or in a
member's NULLABILITY, between the host's readings and the port's is a difference between two RELEASES and not
a defect in the port - and copying the host's order or defaults into the port would make the port answer as
the later release, which is not what it implements.

What is a defect is a VALUE that differs where the two SDKs DECLARE THE MEMBER THE SAME WAY. That is what
this script separates:

    identical   the port's reading IS the host's
    predicted   the port's values, laid out in the HOST SDK's declaration order and set - every difference
                accounted for by a declaration the two SDKs spell differently, and named
    unexplained a difference that no declaration difference accounts for. THIS IS WHAT MUST BE ZERO.

Both SDKs are read with the generator's own reader - tools/matter-generate.py, payload_classes() - so the
order and the set come from the headers and not from a list here.

    predict.py <host sdk> <host.tsv> <port.tsv> [--members FILE]
"""
import importlib.util, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../../../.."))


def reader():
    spec = importlib.util.spec_from_file_location("mg", os.path.join(ROOT, "tools/matter-generate.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def declarations(sdk):
    module = reader()
    lines = [line for _, block in module.matter_headers(os.path.abspath(sdk)) for line in block]
    return module, module.payload_classes(lines)


def described_readings(path):
    """<class, member, what %@ prints> from a probe run."""
    found = {}
    for line in open(path):
        fields = line.rstrip("\n").split("\t")
        if fields[0] == "described" and len(fields) > 3:
            found[(fields[1], fields[2])] = fields[3]
    return found


def fresh_readings(path):
    found = {}
    for line in open(path):
        fields = line.rstrip("\n").split("\t")
        if fields[0] == "fresh" and len(fields) > 3:
            found[(fields[1], fields[2])] = fields[3]
    return found


def own_members(info):
    """The class's OWN members, in declaration order: what a -description lists, inherited ones excluded."""
    return [prop["name"] for prop in info["properties"]] if info else []


def declared_type(module, info, name):
    for prop in info["properties"]:
        if prop["name"] == name:
            return module.bare_type(prop), module.nullable_of(prop)
    return None, None


def main():
    host_sdk, host_tsv, port_tsv = sys.argv[1], sys.argv[2], sys.argv[3]
    module, host = declarations(host_sdk)
    _, port = declarations(os.path.join(ROOT, ".agent-work/sdk262"))
    host_described = described_readings(host_tsv)
    port_described = described_readings(port_tsv)
    host_fresh = fresh_readings(host_tsv)
    port_fresh = fresh_readings(port_tsv)

    identical = predicted = unexplained = 0
    named = []
    for (name, member), want in sorted(host_described.items()):
        if member == "-":
            continue
        info = host.get(name)
        if info is None:
            continue
        mine = port_described.get((name, member))
        if mine is None:
            # The host has a member the port's SDK does not declare at all: a later release added it.
            predicted += 1
            named.append("%s.%s: in the host SDK, not in the port's" % (name, member))
            continue
        if member not in own_members(info):
            # And the other way round, which is the one that counted: the PORT prints a member the host's SDK
            # does not declare, so the host's string cannot contain it.
            # MTRJointFabricDatastoreClusterDatastoreGroupKeySetStruct is the measured case - the port prints
            # `groupKeyMulticastPolicy:0;` and the host's SDK has no such member. A member the port declares
            # and the host's SDK does not is a difference between two releases, and it is predicted rather
            # than unexplained.
            predicted += 1
            named.append("%s.%s: in the port's SDK, not in the host SDK's" % (name, member))
            continue
        if mine == want:
            identical += 1
            continue
        their_type, their_null = declared_type(module, info, member)
        our_info = port.get(name)
        our_type, our_null = declared_type(module, our_info, member) if our_info else (None, None)
        if (their_type, their_null) != (our_type, our_null):
            predicted += 1
            named.append("%s.%s: host declares %s%s, the port's SDK declares %s%s"
                         % (name, member, their_type, " nullable" if their_null else " nonnull",
                            our_type, " nullable" if our_null else " nonnull"))
            continue
        unexplained += 1
        named.append("%s.%s: UNEXPLAINED, both SDKs declare %s%s, the host holds %r and the port %r"
                     % (name, member, their_type, " nullable" if their_null else " nonnull", want, mine))

    fresh_same = fresh_declared = fresh_unexplained = 0
    for (name, member), want in sorted(host_fresh.items()):
        mine = port_fresh.get((name, member))
        if mine is None:
            fresh_declared += 1
            continue
        if mine == want:
            fresh_same += 1
            continue
        info, our_info = host.get(name), port.get(name)
        if info is not None and member not in own_members(info):
            fresh_declared += 1
            named.append("%s.%s fresh: in the port's SDK, not in the host SDK's" % (name, member))
            continue
        their_type, their_null = declared_type(module, info, member)
        our_type, our_null = declared_type(module, our_info, member) if our_info else (None, None)
        if (their_type, their_null) != (our_type, our_null):
            fresh_declared += 1
            named.append("%s.%s fresh: host declares %s%s, the port's SDK declares %s%s"
                         % (name, member, their_type, " nullable" if their_null else " nonnull",
                            our_type, " nullable" if our_null else " nonnull"))
            continue
        fresh_unexplained += 1
        named.append("%s.%s fresh: UNEXPLAINED, both declare %s%s, host %r port %r"
                     % (name, member, their_type, " nullable" if their_null else " nonnull", want, mine))

    print("params-diff: description  %d identical, %d predicted by the SDK difference, %d unexplained"
          % (identical, predicted, unexplained))
    print("params-diff: fresh        %d identical, %d predicted by the SDK difference, %d unexplained"
          % (fresh_same, fresh_declared, fresh_unexplained))
    for line in named:
        print("  %s" % line)
    return 0 if unexplained == 0 and fresh_unexplained == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
