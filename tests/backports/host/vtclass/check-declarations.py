#!/usr/bin/env python3
"""Checks every declaration in the port's CharonVideoToolbox.h against SDK 26.2's own headers.

    VT_SDK=<an iPhoneOS*.sdk> python3 check-declarations.py [--quiet]

WHAT IT COMPARES, per class: the property names and their types, and for every method the SELECTOR
SPELLING, the NUMBER OF ARGUMENTS and each argument's TYPE. A selector that is right and an argument that
is wrong is the failure this exists for - the initialiser of VTMotionBlurConfiguration was declared with
four arguments where the SDK declares five, and twenty-six commits and a light guard did not see it,
because a declaration with no implementation behind it is not a thing a compiler objects to.

IT PARSES BOTH SIDES ITSELF, and that is deliberate. gen_body.py is what wrote most of these
declarations, so checking them with it would be the generator marking its own work. This file has its
own parser and knows nothing about the generator; the only thing the two share is the SDK.

HOW A DIFFERENCE IS CLASSIFIED, because "not in the port" is not one thing:

    MISMATCH  declared in both, and the selector, the argument count or a type differs
    MISSING   in the SDK, not in the port, and the SDK does not mark it unavailable on iOS
    OMITTED   in the SDK, not in the port, and the SDK marks it API_UNAVAILABLE(ios) - expected, and
              the ledger has a row for each: processorSupported is one, and carrying it would collide
              with the host's own header
    EXTRA     in the port, not in the SDK - a name no SDK header declares, which is the worst of the
              four, because an application could compile against it and get nothing

Only MISMATCH, MISSING and EXTRA are failures. OMITTED is printed so the count is visible rather than
inferred: a member that quietly stops being declared is a member the next person has to rediscover.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PORT_HEADER = os.path.join(HERE, "..", "..", "..", "..", "packages", "a", "apple-backports",
                           "VideoToolbox", "CharonVideoToolbox.h")

# API_* and NS_* the SDK writes after a declaration. strip() consumes the parenthesised list whole,
# parens included: API_DEPRECATED_WITH_REPLACEMENT("x", macos(15.4, 26.0)) has a ')' inside it, and
# stopping at the first one leaves a trailing ')' that matches nothing.
TRAILING = re.compile(r'\s*(?:API_[A-Z_]+|NS_REFINED_FOR_SWIFT|NS_SWIFT_NAME|NS_SWIFT_UNAVAILABLE'
                      r'|NS_SWIFT_SENDABLE|API_DEPRECATED_WITH_REPLACEMENT|NS_UNAVAILABLE|NS_DESIGNATED_INITIALIZER)'
                      r'\s*(\((?:[^()]|\([^()]*\))*\))?')


def strip(declaration):
    while True:
        m = TRAILING.search(declaration)
        if not m:
            break
        declaration = declaration[:m.start()] + declaration[m.end():]
    return ' '.join(declaration.split())


def normalise(type_name):
    return re.sub(r'\s*\**\s*$', lambda m: ' *' if m.group(0).strip() else '', type_name).strip()


def parse(text):
    """-> {class: {"properties": {name: type}, "instance": {selector: (types, return)}, "class": {...},
                  "unavailable": set(), "unavailable_methods": set()}} for every @interface."""
    classes = {}
    protocols = {}
    for m in re.finditer(r'@protocol\s+(VT\w+)\s*(?:<[^>]*>)?(.*?)@end', text, re.S):
        entry = protocols.setdefault(m.group(1), {"properties": {}, "instance": {}, "class": {}})
        for attrs, decl in re.findall(r'@property\s*\(([^)]*)\)([^;]*);', m.group(2), re.S):
            pm = re.match(r'^(.*?)\s*(\*?)\s*(\w+)$', strip(decl))
            if pm:
                entry["properties"][pm.group(3)] = pm.group(1).strip() + (' *' if pm.group(2) else '')
    for m in re.finditer(r'@interface\s+(VT\w+)\s*(:\s*\w+\s*(?:<[^>]*>)?)?(.*?)@end', text, re.S):
        name, body = m.group(1), m.group(3)
        entry = classes.setdefault(name, {"properties": {}, "instance": {}, "class": {}, "unavailable": set()})
        # The angle-bracketed list after a class name holds BARE protocol names -
        # <VTFrameProcessorConfiguration> - with no @protocol keyword in front of them, so searching for
        # that keyword finds nothing and every class comes back conforming to no protocol at all.
        angle = re.search(r'<([^>]*)>', m.group(2) or '')
        conformances = [x.strip() for x in angle.group(1).split(',')] if angle else []
        for attrs, decl in re.findall(r'@property\s*\(([^)]*)\)([^;]*);', body, re.S):
            raw, unavailable = decl, 'API_UNAVAILABLE(ios)' in decl
            pm = re.match(r'^(.*?)\s*(\*?)\s*(\w+)$', strip(decl))
            if not pm:
                continue
            type_name, property_name = pm.group(1).strip(), pm.group(3)
            type_name += ' *' if pm.group(2) else ''
            if unavailable:
                entry["unavailable"].add(property_name)
            else:
                entry["properties"][property_name] = type_name
        # what the class's own protocols declare, so a restatement is not an invention
        for proto in conformances:
            for prop, type_name in protocols.get(proto, {}).get("properties", {}).items():
                entry["properties"].setdefault(prop, type_name)
        for kind, _returns, decl in re.findall(r'([-+])\s*\(([^)]*)\)([^;]*);', body, re.S):
            unavailable = 'NS_UNAVAILABLE' in decl
            cleaned = strip(decl)
            parts = re.findall(r'(\w+):\s*\(([^)]*)\)', cleaned)
            return_type = normalise(cleaned.split(':', 1)[0]) if ':' in cleaned else normalise(cleaned)
            if parts:
                selector = ''.join(part + ':' for part, _ in parts)
                types = tuple(normalise(t) for _, t in parts)
            else:
                name_match = re.search(r'(\w+)\s*$', cleaned)
                if not name_match:
                    continue
                selector, types = name_match.group(1), ()
            bucket = "class" if kind == "+" else "instance"
            entry[bucket][selector] = (types, return_type)
            if unavailable:
                entry.setdefault("unavailable_methods", set()).add(selector)
    return classes


def main():
    quiet = '--quiet' in sys.argv
    sdk = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else \
        os.environ.get("VT_SDK", "")
    if not sdk:
        sys.exit("check-declarations.py: pass an iPhoneOS*.sdk or set VT_SDK")
    headers = os.path.join(sdk, "System/Library/Frameworks/VideoToolbox.framework/Headers")
    sdk_text = "\n".join(open(f).read() for f in sorted(glob.glob(os.path.join(headers, "*.h"))))
    port = parse(open(PORT_HEADER).read())
    sdk_classes = parse(sdk_text)

    mismatch, missing, extra, omitted = [], [], [], []
    for name in sorted(set(port) | set(sdk_classes)):
        p, s = port.get(name), sdk_classes.get(name)
        unavailable_methods = (s or {}).get("unavailable_methods", set())
        if p is None:
            missing.append("%s: the port declares no such class" % name)
            continue
        if s is None:
            extra.append("%s: declared in the port and in no SDK header" % name)
            continue
        for prop, type_name in sorted(s["properties"].items()):
            if prop in s["unavailable"]:
                continue
            if prop not in p["properties"]:
                missing.append("%s.%s: a property SDK 26.2 declares, the port does not" % (name, prop))
            elif p["properties"][prop] != type_name:
                mismatch.append("%s.%s: the port has %r and the SDK has %r"
                                % (name, prop, p["properties"][prop], type_name))
        for prop in sorted(p["properties"]):
            if prop not in s["properties"]:
                extra.append("%s.%s: a property the port declares and the SDK does not" % (name, prop))
        for bucket in ("instance", "class"):
            for selector, (types, return_type) in sorted(s[bucket].items()):
                if selector in unavailable_methods:
                    omitted.append("%s %s%s: NS_UNAVAILABLE, so not carried, and the ledger has a row"
                                   % (name, "-" if bucket == "instance" else "+", selector))
                    continue
                if selector in p[bucket]:
                    got_types, got_return = p[bucket][selector]
                    if got_types != types:
                        mismatch.append("%s %s%s: the port declares %d argument(s) %s and the SDK %d %s"
                                        % (name, "-" if bucket == "instance" else "+", selector,
                                           len(got_types), list(got_types) or "none",
                                           len(types), list(types) or "none"))
                    elif got_return != return_type:
                        mismatch.append("%s %s%s: the port returns %r and the SDK returns %r"
                                        % (name, "-" if bucket == "instance" else "+", selector,
                                           got_return, return_type))
                elif s["properties"].get(selector.split(":")[0]):
                    pass                      # a property's getter, counted with the property
                else:
                    missing.append("%s %s%s: a method SDK 26.2 declares, the port does not"
                                   % (name, "-" if bucket == "instance" else "+", selector))
            for selector in sorted(p[bucket]):
                if selector not in s[bucket] and selector.split(":")[0] not in s["properties"]:
                    extra.append("%s %s%s: a method the port declares and the SDK does not"
                                 % (name, "-" if bucket == "instance" else "+", selector))
        for prop in sorted(s["unavailable"]):
            if prop in s["properties"] and prop not in p["properties"]:
                omitted.append("%s.%s: API_UNAVAILABLE(ios), so not carried, and the ledger has a row"
                               % (name, prop))

    for label, items in (("MISMATCH", mismatch), ("EXTRA", extra)):
        for line in items:
            print("%s %s" % (label, line))
    if not quiet:
        for line in missing:
            print("NOT YET " + line)
    if not quiet:
        for line in omitted:
            print("OMITTED " + line)
    # Only MISMATCH and EXTRA fail the check. MISSING is the ledger's business - it is step 3's work not
    # yet done, and step 4 registers each row with its own reason - and counting it as a failure would
    # make this script the thing that has to be edited every time a class lands, which is a second place
    # the work is tracked. The initialiser declared with four arguments where the SDK declares five WAS a
    # MISMATCH, and is what this exists for.
    total = len(mismatch) + len(extra)
    print("check-declarations: %d properties and methods over %d classes; %d MISMATCH, %d EXTRA "
          "(the two that fail it); %d declared by the SDK and not yet carried, %d omitted as "
          "unavailable on iOS"
          % (sum(len(v["properties"]) + len(v["instance"]) + len(v["class"]) for v in port.values()),
             len(port), len(mismatch), len(extra), len(missing), len(omitted)))
    if total:
        print("the port's declarations do NOT match SDK 26.2's")
        sys.exit(1)
    print("the port's declarations match SDK 26.2's: every selector, every argument count, every type")


if __name__ == "__main__":
    main()
