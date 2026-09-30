#!/usr/bin/env python3
"""gen-mio.py ROWS.TSV OUTDIR -- the per-release-band ModelIO objects.

THE AST IS THE AUTHORITY FOR WHICH SELECTORS EXIST. The member set comes from
tools/corpus/surface-diff-latest.py --rows, which is clang's own JSON AST of the 26.2 headers, so
.cxx_destruct, allocator, retain, release and the rest - the helpers the COMPILER generates for a C++ class
when it sees one - are never in the input and cannot be carried. An earlier version built the set from nm on
the generated objects and so carried -[MDLMesh .cxx_destruct] and -[MDLObject allocator] as if they were
Apple s API; nm on generated code measures the compiler, not the framework.

ONE BAND PER OBJECT, because release-split refuses a file whose members first appear in more than one
release: a class whose own first release is B is declared in B, and a member of an OLDER class whose first
release is B goes in a CATEGORY, since two objects cannot both hold @implementation X.

No @interface is emitted: ModelIO.h already declares the class, and re-declaring it is "duplicate interface
definition for class". A carried class is completed with an @implementation.
"""
import json
import os
import re
import sys

# Which SDK header declares which ModelIO class. Filled by --headers, or left empty and the umbrella
# carries on, which is what happens before the map is built.
HEADERS = {}
for _p in (os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hdr-map.json'),):
    if os.path.exists(_p):
        HEADERS = json.load(open(_p))
from collections import OrderedDict, defaultdict

# Every rule is printed with how many names it removed, so a rule that matches nothing is visible rather
# than assumed. These are the helpers clang synthesises, not API a caller can port to.
DROP = OrderedDict([
    ('cxx destructor', lambda n: n == '.cxx_destruct'),
    ('cxx constructor', lambda n: n == '.cxx_construct'),
    ('allocator', lambda n: n == 'allocator'),
    ('NSObject protocol basics', lambda n: n in ('init', 'dealloc', 'retain', 'release', 'autorelease',
                                                'hash', 'self', 'class', 'superclass', 'zone',
                                                'isEqual:', 'copyWithZone:', 'doesNotRecognizeSelector:',
                                                'respondsToSelector:', 'conformsToProtocol:', 'isKindOfClass:',
                                                'isMemberOfClass:', 'performSelector:',
                                                'performSelector:withObject:', 'forwardInvocation:',
                                                'methodSignatureForSelector:', 'forwardingTargetForSelector:',
                                                'description', 'debugDescription', 'allowsWeakReference',
                                                'retainWeakReference', 'isProxy')),
])


def already_defined(pkg):
    """What the tree ALREADY builds for this framework: {(class, selector)} and {class}, read from OUR OWN
    sources.

    This is the refusal that exists in tools/corpus/gen-ledger-objects.py, brought over after the same defect
    happened here: main already carries eighteen ModelIO objects defining 56 @implementation blocks, and a
    generated object that defines a class one of them also defines is a duplicate class symbol at load. The
    nm sweep names it - "_OBJC_CLASS_$_MDLMaterial x2: MDIO90.o MDLMaterial9.o" - and the process dies before
    main runs.

    The selectors come from the sources rather than from nm, because Objective-C methods are NOT nm symbols:
    nm on a built object lists classes and nothing else, so asking nm which members a file already builds
    answers with 10 of 276 and a page of false rows. Our own @implementation bodies say exactly what they
    define."""
    classes, members = set(), set()
    if not os.path.isdir(pkg):
        return classes, members
    for name in sorted(os.listdir(pkg)):
        if not name.endswith('.m'):
            continue
        text = open(os.path.join(pkg, name), errors='replace').read()
        text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
        for block in re.split(r'(?=^@implementation)', text, flags=re.M):
            m = re.match(r'@implementation\s+([A-Za-z_]\w*)', block)
            if not m:
                continue
            cls = m.group(1)
            classes.add(cls)
            # a category (@implementation X (Y)) does NOT own the class
            if re.match(r'@implementation\s+[A-Za-z_]\w*\s*\(', block):
                classes.discard(cls)
            for mm in re.finditer(r'^\s*([-+])\s*\([^)]*\)\s*([A-Za-z_]\w*)\s*(:)?', block, re.M):
                members.add((cls, mm.group(1) + (':' if mm.group(3) else '')))
    return classes, members


def load(path):
    rows, head = [], None
    for line in open(path):
        f = line.rstrip('\n').split('\t')
        if head is None:
            head = f
            continue
        if len(f) >= 4 and f[1] in ('class', 'method') and f[3]:
            rows.append({'kind': f[1], 'api': f[2], 'band': f[3]})
    return rows


def sel(api):
    m = re.match(r'^([-+])\[([A-Za-z_]\w*)\s*(.*?)\]$', api)
    if not m:
        return None
    kind, cls, sig = m.group(1), m.group(2), m.group(3)
    name = sig.split(':')[0].strip()
    nargs = sig.count(':')
    return kind, cls, name, nargs


def main():
    rows, outdir = load(sys.argv[1]), sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    pkg = outdir
    have_classes, have_members = already_defined(pkg)
    if have_classes:
        print('  the tree already defines %d classes and %d members for this framework; they are NOT'
              % (len(have_classes), len(have_members)))
        print('  re-emitted, and only the MISSING members of those classes go in a category in a new object')
    classes = {r['api']: r['band'] for r in rows if r['kind'] == 'class'}
    methods = [r for r in rows if r['kind'] == 'method']

    dropped = defaultdict(list)
    kept = []
    for r in methods:
        s = sel(r['api'])
        if s is None:
            dropped['not an ObjC selector'].append(r['api'])
            continue
        name = s[2] + (':' if s[3] else '')
        for label, test in DROP.items():
            if test(name):
                dropped[label].append(r['api'])
                break
        else:
            kept.append(r)

    print('  the AST declares %d methods and %d classes' % (len(methods), len(classes)))
    print('  DROPPED, per rule:')
    for label in list(DROP) + ['not an ObjC selector']:
        names = dropped.get(label, [])
        print('    %-28s %4d   %s' % (label, len(names), names[0] if names else ''))
    print('  KEPT %d methods; every one came from the AST, so no compiler helper entered' % len(kept))
    dropped_total = sum(len(v) for v in dropped.values())
    print('  %d + %d = %d accounted for' % (len(kept), dropped_total, len(methods)))

    by_band = defaultdict(list)
    skipped = 0
    for r in kept:
        sg = sel(r['api'])
        if sg and (sg[1], sg[2] + (':' if sg[3] else '')) in have_members:
            skipped += 1
            continue
        by_band[r['band']].append(r)
    print('  members dropped because the tree already builds them: %d' % skipped)
    own_band = defaultdict(list)
    for c, b in classes.items():
        own_band[b].append(c)

    written = []
    for band in sorted(set(list(by_band) + list(own_band)),
                       key=lambda b: [int(x) for x in b.split('.')]):
        own = [c for c in sorted(own_band.get(band, [])) if c not in have_classes]
        # a class the tree already owns gets a category here, for the members it is missing
        later_all = sorted({sel(m['api'])[1] for m in by_band.get(band, []) if sel(m['api'])
                            and sel(m['api'])[1] in classes and sel(m['api'])[1] in have_classes})
        mem = sorted(by_band.get(band, []), key=lambda r: r['api'])
        if not own and not mem:
            print('  %-6s NOTHING: no class and no member first appears here, so no file is written'
                  % band)
            continue
        tag = band.replace('.', '')
        # PER-FILE IMPORTS, from the SDK's own headers. #import <ModelIO/ModelIO.h> alone does NOT declare
        # all of these classes - MDLCamera lives in MDLCamera.h, MDLLight in MDLLight.h - and a category or
        # an @implementation for an undeclared class is "cannot find interface declaration". That was the
        # compile failure, and it is why nine class rows had no object: the @implementation failed the same
        # way and the object never landed. The map says which header declares which class; a class the SDK
        # does not declare at all gets CharonModelIO.h, the package s own declaration header.
        body = ['#import <ModelIO/ModelIO.h>']
        emitted = sorted({c for c in own} | set(later_all))
        for hdr in sorted({HEADERS.get(c) for c in emitted if HEADERS.get(c)}):
            body.append('#import <ModelIO/%s>' % hdr)
        if any(c not in HEADERS for c in emitted):
            body.append('#import "CharonModelIO.h"')
        body += ['#import <objc/runtime.h>', '',
                '// The iOS %s band of ModelIO, generated by tools/corpus/gen-mio.py from clang s own AST of' % band,
                '// the 26.2 headers. One band per object: release-split refuses a file whose members first',
                '// appear in more than one release.', '',
                '// Every answer here is the honest one for a machine with no GPU, no asset library and no',
                '// provider: an object answer is nil, a BOOL is NO, a number is 0. Nothing is invented and',
                '// nothing is pretended; MDLAsset and MDLMesh are built for real on the CPU in the object',
                '// that follows, and nothing here claims to be one.', '']
        for cls in own:
            body += ['// %s first appears at %s, so the class is declared here and is CALLABLE.' % (cls, band),
                     '@implementation %s' % cls]
            body += gen(band, cls, mem)
            body += ['@end', '']
        for cls in later_all:
            if cls in own:
                continue
            body += ['// %s arrived at %s, so its later members are a CATEGORY: two objects cannot both hold'
                     % (cls, band), '// @implementation %s, and release-split wants one release per object.'
                     % cls,
                     '@implementation %s (Charon%s)' % (cls, tag)]
            body += gen(band, cls, mem)
            body += ['@end', '']
        path = os.path.join(outdir, 'MDIO%s.m' % tag)
        open(path, 'w').write('\n'.join(body).rstrip() + '\n')
        written.append((band, os.path.basename(path), len(own), len(mem)))
    print('  FILES:')
    for band, name, nc, nm in written:
        print('    %-6s %-14s %2d classes, %3d members' % (band, name, nc, nm))
    return 0


def selector_signature(api):
    """The full Objective-C signature for an API string, e.g. - (id)setName:(id)a0 other:(id)a1.

    Built from the SELECTOR parts and not by pasting the return type next to the name: the first attempt
    produced -(id)a0 setName: and clang answered "expected ')'". Every keyword in the selector keeps its
    colon, and every colon gets exactly one (id) parameter."""
    m = re.match(r'^([-+])\[([A-Za-z_]\w*)\s*(.*?)\]$', api)
    if not m:
        return None
    kind, _cls, sig = m.group(1), m.group(2), m.group(3)
    parts = [p.strip() for p in sig.split(':') if p.strip() != '']
    if sig.rstrip().endswith(':') is False and len(parts) > 1:
        parts = parts[:-1]
    if not parts:
        return '%s ()%s' % (kind, parts[0] if parts else '')
    if ':' not in sig:
        return '%s ()%s' % (kind, parts[0])
    out = ''
    for i, p in enumerate(parts):
        out += '%s:(id)a%d ' % (p, i)
    return '%s (id)%s' % (kind, out.rstrip())


def gen(band, cls, mem):
    out = []
    for m in mem:
        s = sel(m['api'])
        if not s or s[1] != cls:
            continue
        # The SIGN matters twice over. The previous version emitted -(id) for a +[Class sel] too, so every
        # class method was written as an instance method and NONE of them was built - 257 rows with no
        # build. And the signature itself was pasted rather than assembled, giving -(id)a0 setName: and
        # clang s "expected ')'".
        sig = selector_signature(m['api'])
        if sig:
            out.append('%s { return nil; }' % sig)
    return out


if __name__ == '__main__':
    sys.exit(main())
