#!/usr/bin/env python3
"""Emits each VideoToolbox class's declaration and its value file, from the iOS 26.2 SDK's headers.

    VT_SDK=<an iPhoneOS*.sdk> python3 emit.py

The output goes under the worktree's .agent-work, not into /tmp: a generated file the commits are built
from is evidence, and /tmp is wiped. It is regenerable from the SDK, and regenerable is the reason it
is not tracked - but it is kept, and the differential is what says the committed files match it.

gen_body is loaded by its explicit path, and the loaded module's own __file__ is asserted to be this
directory's copy. That is not ceremony: the first version of this imported gen_body by name, and because
Python puts a script's own directory ahead of anything the script inserts, it silently loaded a DIFFERENT
copy that was one bug behind - the star fix appeared to be in place and was not. One copy, in one place,
loaded by path, checked.

Every property the SDK marks API_UNAVAILABLE(ios) is left out and listed in unavailable.tsv, because the
ledger has a row for each and step 4 registers it as absent with that measured reason.
"""
import glob
import re
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))


def load_gen_body():
    path = os.path.join(HERE, "gen_body.py")
    spec = importlib.util.spec_from_file_location("vt_gen_body", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == path, \
        "loaded %s, not %s - a second copy of gen_body is shadowing this one" % (module.__file__, path)
    return module


WORKTREE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "..", "..", "..", ".."))


def load_emit_registry():
    """emit-registry.py, by explicit path, with its __file__ asserted - the same rule as gen_body, and
    for the same reason: a module named import once loaded a different copy and every count looked fine."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "emit-registry.py")
    spec = importlib.util.spec_from_file_location("emit_registry", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == path, "loaded a copy of emit-registry that is not this one"
    return module


def sdk_headers_by_file(text, sdk):
    """The VideoToolbox headers as {path: text}, so a registry row can name the FILE and LINE its
    declaration is on - a source a reader can open, rather than the framework's name."""
    directory = os.path.join(sdk, "System/Library/Frameworks/VideoToolbox.framework/Headers")
    out = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.h"))):
        out[path] = open(path).read()
    return out


def main():
    gen_body = load_gen_body()
    sdk = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("VT_SDK", "")
    if not sdk:
        sys.exit("emit.py: pass an iPhoneOS*.sdk or set VT_SDK")
    headers = os.path.join(sdk, "System/Library/Frameworks/VideoToolbox.framework/Headers")
    text = "\n".join(open(f).read() for f in sorted(glob.glob(os.path.join(headers, "*.h"))))
    protocols, classes = gen_body.parse(text)

    out = os.path.join(WORK, ".agent-work", "generated", "vt")
    os.makedirs(out, exist_ok=True)
    summary, absent = {}, []
    for cls in gen_body.ORDER:
        entry = classes[cls]
        own = entry["own"]
        inherited = [(name, protocols[proto][name]) for proto in entry["protocols"]
                     for name in protocols[proto] if name not in own]
        # THIS CLASS'S OWN PROPERTY DECLARATIONS, as {name: prop}. Both users of an argument's name
        # resolve through it - the ivar block and the initialisers - and it is built HERE, between
        # `inherited` and `conformances`, because built a line below its first user every class after the
        # first was resolved against the PREVIOUS class's properties.
        known_properties = dict(own)
        for proto in entry["protocols"]:
            for property_name, property in protocols[proto].items():
                known_properties.setdefault(property_name, property)
        conformances = ' <%s>' % ', '.join(entry["protocols"]) if entry["protocols"] else ''

        header = ["@interface %s : NSObject%s\n" % (cls, conformances), ""]
        for name, prop in inherited:
            header.append(gen_body.prop_line(name, prop))
        if inherited and own:
            header.append("")
        for name, prop in own.items():
            header.append(gen_body.prop_line(name, prop))
        # the SDK's designated initialisers, declared as the SDK spells them - an application must be
        # able to call them, and check-declarations.py compares every one of these against the headers
        initialisers = gen_body.initialisers(text, cls)
        if initialisers:
            header.append("")
            for selector, arguments, _returns in initialisers:
                header.append(gen_body.init_signature(selector, arguments, _returns))
        header.append("@end\n")

        # an ivar block when the class carries a parameter the SDK declares no property for, so that KVC
        # finds it the way it finds the host's own _sourcePixelFormat
        ivars = []
        for selector, arguments, _returns in initialisers:
            for ivar_name, ivar_type in gen_body.ivars_for(arguments, known_properties, selector, cls):
                if (ivar_name, ivar_type) not in ivars:
                    ivars.append((ivar_name, ivar_type))
        value = ["@implementation %s%s\n" % (cls,
                                              "{%s}" % "".join(" %s %s;" % (ty, nm) for nm, ty in ivars)
                                              if ivars else "")]
        if inherited:
            value.append("#pragma mark - The protocol's own properties, implemented for this class\n")
            for name, prop in inherited:
                value.append(gen_body.body(name, prop))
            if own:
                value.append("\n#pragma mark - This class's own properties\n")
        for name, prop in own.items():
            value.append(gen_body.body(name, prop))
        if initialisers:
            value.append("\n#pragma mark - The SDK's designated initialisers\n")
            known = set(own) | {n for pr in entry["protocols"] for n in protocols[pr]}
            for selector, arguments, _returns in initialisers:
                value.append(gen_body.init_body(selector, arguments, known_properties, cls))
        value.append("@end\n")

        open(os.path.join(out, "%s.h" % cls), "w").write("\n".join(header))
        # the file-local typedefs the property macros need, when any of this class's accessors names a
        # type carrying a comma - see MACRO_TYPEDEFS. Emitted at the TOP of the .m, before the first
        # @implementation, because the macros are expanded inside it.
        # The store category, invoked once per class, BEFORE the implementation that reads through it.
        # Every CHARON_VALUE_PROPERTY and CHARON_SCALAR_PROPERTY expands to [self charon_valueForKey:],
        # and that selector is declared and implemented by this macro in VideoToolboxValueStore.h - so
        # without the invocation the macros compile to a call no @interface declares. A class whose
        # accessors are all hand-written needs none, so it is emitted only when one is a macro.
        spelled = [p['type'] + (' *' if p['obj'] else '')
                   for _n, p in list(own.items()) + inherited]
        uses_macro = any(not p['class'] and p['type'] not in gen_body.STRUCTS
                         and p['type'] != 'CVPixelBufferRef'
                         for _n, p in list(own.items()) + inherited)
        if uses_macro:
            value = ["CHARON_VIDEO_TOOLBOX_VALUE_STORE(%s)" % cls, ""] + value
        typedefs = gen_body.macro_typedefs(spelled)
        value = typedefs + value if any(line.startswith('typedef ') for line in typedefs) else value
        open(os.path.join(out, "%s.m" % cls), "w").write("\n".join(value))
        summary[cls] = {"protocols": entry["protocols"], "own": list(own),
                        "inherited": [name for name, _ in inherited],
                        "classProps": [name for name, prop in list(own.items()) + inherited
                                       if prop["class"]],
                        "unavailable_ios": entry["unavailable_ios"]}
        for name in entry["unavailable_ios"]:
            absent.append("%s.%s\tproperty\tobjc\t26.0\tAPI_UNAVAILABLE(ios)" % (cls, name))

    # The round-trip's table, so the class list in the differential is the SDK's seventeen and not a
    # list a hand wrote. The DATA is generated; the CALLING is not - cases-roundtrip.m reads this and
    # constructs each object, because what has to be generated is what the SDK declares and what cannot
    # be generated is a call.
    # One value per argument type. A POINTER is NULL - and CVPixelBufferRef is a pointer with no star,
    # so it is named: a fabricated buffer pointer would be retained by the accessor that reads it. A
    # STRUCT is a compound literal in the type's own shape, because a scalar will not convert to one.
    round_trip_values = {"NSInteger": "1920", "BOOL": "1", "float": "2", "OSType": "1"}

    def value_for(type_name):
        bare = re.sub(r"\s*_(?:Nullable|Nonnull|null_unspecified)\b|\s*__nonnull\b", "", type_name)
        if bare.endswith("*") or bare in ("id", "CVPixelBufferRef"):
            return "NULL"
        if bare == "CMTime":
            return "{0, 1, 0, 0, 0}"
        if bare == "CMVideoDimensions":
            return "{{1920, 1080}}"
        return round_trip_values.get(bare, "1")

    # A TYPED CALL per initialiser, generated rather than hand-written, and deliberately not
    # NSInvocation: setArgument:atIndex: takes a pointer to the value in its own size, and the sizes
    # here differ - BOOL is one byte, float four, NSInteger eight, CMTime a struct - so a size guessed
    # wrong corrupts the argument list silently and the round-trip reports a mismatch of its own making.
    # Every cast and every argument here is written in the type the SDK declares for that keyword, so
    # the compiler checks all seventeen.
    head = ["#pragma once", "",
            "// GENERATED by emit.py. One entry per designated initialiser the SDK declares: the class, the",
            "// selector, a TYPED call that constructs the object, and the scalar properties with the value",
            "// each must read back.",
            "//",
            "// The expectation is generated from the SAME argument list as the constructor, which is what",
            "// makes it a check: a value stored under the wrong key cannot report success.",
            "typedef struct { const char *property; long long value; } VTRoundTripValue;", "",
            "typedef struct {",
            "    const char *className;",
            "    const char *selector;",
            "    id (*construct)(Class, SEL);",
            "    const VTRoundTripValue *expected;",
            "    unsigned expectedCount;",
            "} VTRoundTripCase;", ""]
    constructors, rows, expected_arrays, count = [], [], [], 0
    for cls in gen_body.ORDER:
        entry = classes[cls]
        # this loop is outside the one that emits the value files, so it builds the per-class properties
        # again rather than reaching for a name the last iteration happened to leave behind
        known_properties = dict(entry["own"])
        for proto in entry["protocols"]:
            for property_name, property in protocols[proto].items():
                known_properties.setdefault(property_name, property)
        for selector, arguments, _returns in gen_body.initialisers(text, cls):
            spellings = [t for _k, t, _piece in arguments]
            cast = "id (*)(id, SEL%s)" % "".join(", " + t for t in spellings)
            call = "".join(", (%s)%s" % (t, value_for(original))
                            for t, (_k, original, _piece) in zip(spellings, arguments))
            constructors += ["static id VTConstruct%d(Class cls, SEL sel)" % count, "{",
                             "    return ((%s)objc_msgSend)((id)[cls alloc], sel%s);" % (cast, call), "}"]
            # what each SCALAR property must read back, under the PROPERTY's own name - the rename map
            # applied, so usePrecomputedFlow is expected as precomputedFlow - and only for a value that
            # is a word: a struct or a CFTypeRef is not in the table, and that is the shape comparison's
            expected, put = [], {}
            for keyword, type_name, _piece in arguments:
                key = gen_body.store_key(keyword, known_properties, cls, cls)
                # THE TWO PARSERS MUST AGREE, and a difference needs a REASON. The store's key comes
                # from store_key; the read-back's comes from readback_property, a second implementation
                # over the header text that calls neither store_key nor props_of. They agreed on the
                # fifteen classes whose argument IS a property name, and they differ on exactly the two
                # where the SDK declares no such property - which is what PRIVATE_KEYS and DECLARED_KEYS
                # exist for. A difference with neither reason is a FAILURE, and both keys are printed:
                # the dead store shipped because the store and the expectation were wrong in the SAME way,
                # so a cross-check that could not disagree was not a cross-check.
                read_back = gen_body.readback_property(text, cls, keyword)
                justified = (gen_body.is_private_key(cls, keyword)
                             or (cls, keyword) in gen_body.DECLARED_KEYS)
                if read_back != key and not justified:
                    raise SystemExit(
                        "%s %s: the store would write under %r and the header's own property for this "
                        "argument is %r, and the difference is justified by neither PRIVATE_KEYS nor "
                        "DECLARED_KEYS - a value written where nothing reads it"
                        % (cls, selector, key, read_back))
                if gen_body.is_private_key(cls, keyword):
                    continue
                bare = re.sub(r"\s*_(?:Nullable|Nonnull|null_unspecified)\b|\s*__nonnull\b", "", type_name)
                if bare.endswith("*") or bare in ("id", "CVPixelBufferRef", "CMTime",
                                                  "CMVideoDimensions"):
                    continue
                put[key] = value_for(type_name)
            # nothing more: only a property this initialiser SET has a value to read back
            # A CLASS property has no INSTANCE accessor to read it back through, and a property whose
            # getter differs from its name has to be read by the GETTER - defaultRevision and
            # precomputedFlow/usesPrecomputedFlow are the two that taught this, both by reading back as
            # the "no accessor" sentinel.
            for name, prop in entry["own"].items():
                if prop["obj"] or name not in put or prop["class"]:
                    continue
                if prop["type"] in ("CMTime", "CMVideoDimensions", "CVPixelBufferRef"):
                    continue
                expected.append('    {"%s", %s},' % (prop["getter"] or name, put[name]))
            expected_arrays.append("static const VTRoundTripValue vtExpected%d[] = {" % count)
            expected_arrays += expected + ["};"]
            rows.append('    {"%s", "%s", VTConstruct%d, vtExpected%d, %d},'
                        % (cls, selector, count, count, len(expected)))
            count += 1
    # The typed calls name CVPixelBufferRef, CMTime and the frame classes, which the HOST's build does
    # not declare - it must not include the port's header. So they live inside the port's build, and the
    # host's build gets one stub and seventeen defines, which is what lets ONE table be read by both.
    # The EXPECTED ARRAYS are plain data - a property name and a number - so they are OUTSIDE the guard:
    # the table below names them in both builds, and inside it the host's build would have no
    # vtExpected0 to point at. Only the typed calls are inside, because only they name the port's types.
    tail = expected_arrays + ["#ifdef CHARON_HOST_DIFFERENTIAL"] + constructors + [
        "#else",
        "static id VTConstructNotBuilt(Class cls, SEL sel)",
        "{",
        "    (void)cls; (void)sel; return nil;",
        "}"]
    tail += ["#define VTConstruct%d VTConstructNotBuilt" % n for n in range(count)]
    tail += ["#endif", "",
             "static const VTRoundTripCase vtRoundTripCases[] = {"] + rows + [
        "};", "",
        "#define VT_ROUND_TRIP_CASES %d" % count, ""]
    open(os.path.join(out, "roundtrip-cases.h"), "w").write("\n".join(head + tail))

    # THE MUTANTS' ANCHORS, generated from the same emission that produced the accessors. They were
    # written by hand against - (VTFrameProcessorFrame *)nextFrame, and every generated accessor is a
    # MACRO now, so all sixteen anchors had stopped existing and the run reported them as survivors. An
    # anchor that does not apply is a RED run, not a skip - mutate.py already counts it as survived.
    #
    # Two kinds, and both are one line that exists exactly once in the class's own file:
    #   value  a store line putting a value under one property's key, moved to another property's key -
    #          the defect a value differential exists for
    #   shape  a class property's accessor, + turned into an instance method - where a class property
    #          LIVES, which is what the shape comparison asks
    mutant_rows = []
    for cls in gen_body.ORDER:
        # the same per-class properties the value file used, built again because this loop is outside the
        # one that built them: reaching for a name left over from the last iteration is how every class
        # after the first was once resolved against the PREVIOUS class's declarations
        known_properties = dict(classes[cls]["own"])
        for proto in classes[cls]["protocols"]:
            for property_name, property in protocols[proto].items():
                known_properties.setdefault(property_name, property)
        source = "VideoToolboxValue26.m" if cls == "VTMotionBlurConfiguration" else "%s.m" % cls
        body = open(os.path.join(out, "%s.m" % cls)).read()
        entry = classes[cls]
        known = dict(entry["own"])
        for proto in entry["protocols"]:
            for name, prop in protocols[proto].items():
                known.setdefault(name, prop)
        # a value mutant: the first stored scalar, moved to another property's key
        scalars = [n for n, pr in known.items() if not pr["obj"]
                   and pr["type"] not in ("CMTime", "CMVideoDimensions", "CVPixelBufferRef")
                   and n in [gen_body.store_key(k, known_properties, cls, cls) for _s, a, _r in gen_body.initialisers(text, cls)
                             for k, _t, _p in a]]
        for other in scalars[1:2]:
            line = 'CharonValueSet(self, @(%s), @"%s");' % (scalars[0], scalars[0])
            if body.count(line) == 1:
                mutant_rows.append("%s\t%s\t%s\t%s"
                                   % (cls, source, line, line.replace('@"%s"' % scalars[0],
                                                                       '@"%s"' % other)))
                break
        # a DROP mutant: the first value the initialiser sets, not set at all. The other two kinds need a
        # second set scalar or a class property, and NINE of the seventeen have neither - so without this
        # they had no mutant at all, and a class with no mutant is a SKIPPED check rather than a passing
        # one. Dropping the assignment leaves the property reading 0 where the expectation says otherwise,
        # which is the round-trip's own arithmetic and needs no host.
        for line in body.split("\n"):
            if not line.startswith("    CharonValueSet(self, @(") or not line.rstrip().endswith(");"):
                continue
            # UNIQUE in the file, or mutate.py refuses it and the run goes red. A class with TWO
            # initialisers stores the same first argument twice, so the first line is not an anchor; the
            # next one that occurs once is.
            if body.count(line) != 1:
                continue
            mutant_rows.append("%s\t%s\t%s\t" % (cls, source, line))
            break
        # The OLD-KEY mutant, and it is the one that must exist: a declared entry makes store_key write the
        # PROPERTY, so the cross-key generator above - which only fires when the two disagree - now skips
        # the class entirely. Without this, the fix that the entry made would leave nothing behind to
        # catch a return to the argument's own name, which is the exact text that shipped twice.
        for (declared_class, declared_argument), (declared_property, _g, _l) in gen_body.DECLARED_KEYS.items():
            if declared_class != cls:
                continue
            for selector, arguments, _returns in gen_body.initialisers(text, cls):
                for keyword, _type_name, _piece in arguments:
                    if keyword != declared_argument:
                        continue
                    key = gen_body.store_key(keyword, known_properties, selector, cls)
                    if key == keyword or key != declared_property:
                        continue
                    line = 'CharonValueSet(self, @(%s), @"%s");' % (keyword, key)
                    if body.count(line) == 1:
                        mutant_rows.append("%s\t%s\t%s\t%s"
                                           % (cls, source, line,
                                              line.replace('@"%s"' % key, '@"%s"' % keyword)))
        # a CROSS-KEY mutant: the exact swap that shipped as a dead store, generated rather than written
        # down. DECLARED_KEYS is class-scoped, and the bug was applying one class's entry to another - so
        # for every class whose OWN key for an argument differs from the entry some OTHER class claims for
        # it, the store line is rewritten to that other key. The mutant and the defect are the same text,
        # which is the point: the thing that shipped is the thing the run must go red on.
        for (other_class, other_keyword), (other_property, _getter, _line) in gen_body.DECLARED_KEYS.items():
            if other_class == cls:
                continue
            for selector, arguments, _returns in gen_body.initialisers(text, cls):
                own_key = {k: gen_body.store_key(k, known_properties, selector, cls)
                           for k, _t, _p in arguments}
                if other_keyword not in own_key or own_key[other_keyword] == other_property:
                    continue
                line = 'CharonValueSet(self, @(%s), @"%s");' % (other_keyword, own_key[other_keyword])
                if body.count(line) == 1:
                    mutant_rows.append("%s\t%s\t%s\t%s"
                                       % (cls, source, line,
                                          line.replace('@"%s"' % own_key[other_keyword],
                                                       '@"%s"' % other_property)))
        # a shape mutant: the first class property's accessor, moved to the instance
        for name, prop in entry["own"].items():
            if not prop["class"]:
                continue
            getter = prop["getter"] or name
            for sign in ("+ ", "- "):
                line = "%s(%s)%s" % (sign, prop["type"] + (" *" if prop["obj"] else ""), getter)
                if body.count(line) == 1:
                    mutant_rows.append("%s\t%s\t%s\t%s"
                                       % (cls, source, line, line.replace(sign, "- " if sign == "+ " else "+ ", 1)))
                    break
            break
    with open(os.path.join(out, "mutants.tsv"), "w") as handle:
        handle.write("\n".join(mutant_rows) + "\n")
    print("  %d mutants generated from the emitted accessors" % len(mutant_rows))
    print("  %d initialisers over %d classes in the round-trip's table, each with a typed call"
          % (count, len([c for c in gen_body.ORDER if gen_body.initialisers(text, c)])))
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=1, sort_keys=True)
    with open(os.path.join(out, "unavailable.tsv"), "w") as handle:
        handle.write("\n".join(absent) + "\n")
    # THE REGISTRY ROWS AND THE FACTS FILE, from the same parse that produced the value files, so a row
    # cannot describe a class the value file does not build. Without this the library exports seventeen
    # classes and the registry records none of them, and backports.lua answers "built, but no entry in
    # registry/" for every one - the gate failing on the family this series exists to build.
    registry = load_emit_registry()
    rows = registry.build_rows(gen_body, sdk_headers_by_file(text, sdk), protocols, classes,
                               gen_body.ORDER)
    registry_dir = os.path.join(WORKTREE, "packages", "a", "apple-backports", "registry", "VideoToolbox")
    facts_dir = os.path.join(WORKTREE, "packages", "a", "apple-backports", "facts", "VideoToolbox")
    written = registry.write(registry_dir, facts_dir, rows, gen_body.ORDER)
    for name, count in written:
        print("  registry %s: %d rows" % (name, count))
    print("  registry rows: %d over %d class(es)" % (len(rows), len(gen_body.ORDER)))
    print("emitted %d classes to %s" % (len(summary), out))
    print("  %d accessors, %d class properties, %d properties the SDK marks API_UNAVAILABLE(ios)"
          % (sum(len(s["own"]) + len(s["inherited"]) for s in summary.values()),
             sum(len(s["classProps"]) for s in summary.values()), len(absent)))


if __name__ == "__main__":
    main()
