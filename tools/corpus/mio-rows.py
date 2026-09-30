#!/usr/bin/env python3
"""mio-rows.py ROWS.TSV -- the registry rows for exactly what the ModelIO objects build.

Two authorities, and they are different on purpose:
  - WHICH selectors exist comes from clang s AST (surface-diff-latest.py --rows), so a compiler-generated
    helper can never become a row;
  - minimum comes from the AST s OWN ios introduced, per member, because a class s band does not decide a
    member s band and release-split splits on the member.

The band is never taken from the object a member happens to sit in. That fallback is counted and printed,
and it must be ZERO: a non-zero count means the AST lookup missed and every such row would be filed under
the band of its file rather than its own.
"""
import re
import sys

NS_BASICS = {'init', 'dealloc', 'retain', 'release', 'autorelease', 'hash', 'self', 'class', 'superclass',
             'zone', 'isEqual:', 'copyWithZone:', 'description', 'debugDescription', 'allowsWeakReference',
             'retainWeakReference', 'isProxy'}


def sel(api):
    m = re.match(r'^([-+])\[([A-Za-z_]\w*)\s*(.*?)\]$', api)
    if not m:
        return None
    name = m.group(3).split(':')[0].strip()
    return m.group(1), m.group(2), name + (':' if ':' in m.group(3) else '')


def main():
    rows = []
    head = None
    for line in open(sys.argv[1]):
        f = line.rstrip('\n').split('\t')
        if head is None:
            head = f
            continue
        if len(f) >= 4 and f[1] in ('class', 'method') and f[3]:
            rows.append((f[1], f[2], f[3]))
    classes = [(a, b) for k, a, b in rows if k == 'class']
    methods = [(a, b) for k, a, b in rows if k == 'method']
    dropped = [a for a, _ in methods if (sel(a) or ('', '', a))[2] in NS_BASICS]
    kept = [(a, b) for a, b in methods if (sel(a) or ('', '', a))[2] not in NS_BASICS]

    out = [('api', 'kind', 'introduced', 'minimum', 'reason', 'effect', 'source', 'facts')]
    fallbacks = 0
    for api, band in sorted(classes, key=lambda r: ([int(x) for x in r[1].split('.')], r[0])):
        out.append((api, 'class', band, band,
                    'iOS 6.1.3 has no ModelIO.framework at all, so the class is carried: a hard reference to '
                    'one is a LOAD-FAIL and carrying it is what stops the kill',
                    'the class the release does not have, so a caller that allocates one gets this port s own; '
                    'what it DOES is the carried surface below and nothing beyond it',
                    'clang s own AST of the 26.2 headers as read by tools/corpus/surface-diff-latest.py --rows; '
                    'the ios introduced on the node is the band, and release-split places the object',
                    'facts/ModelIO/Surface.md'))
    for api, band in sorted(kept, key=lambda r: ([int(x) for x in r[1].split('.')], r[0])):
        s = sel(api)
        kind = 'selector' if api.rstrip(']').endswith(':') else 'method'
        out.append((api, kind, band, band,
                    'carried so a caller naming it is CALLABLE; the answer is the honest one for a machine with '
                    'no GPU, no asset library and no provider',
                    'the member implemented in the band object the generator wrote from the AST; an object '
                    'answer is nil, a BOOL is NO and a number is 0, and nothing is invented',
                    'clang s own AST of the 26.2 headers; the member list is the AST s ObjCMethodDecl list, so a '
                    'compiler helper such as .cxx_destruct can never become a row',
                    'facts/ModelIO/Surface.md'))
        if not band or band.count('.') != 1:
            fallbacks += 1
    path = sys.argv[1].rsplit('/', 1)[0] + '/mio-rows.tsv'
    with open(path, 'w') as fh:
        for r in out:
            fh.write('\t'.join(r) + '\n')
    print('  rows written: %d  (1 header + %d classes + %d members)' % (len(out), len(classes), len(kept)))
    print('  dropped by the NSObject-basics rule: %d   e.g. %s' % (len(dropped), dropped[0] if dropped else ''))
    print('  members with no usable AST band (must be 0): %d' % fallbacks)
    print('  bands present: %s' % sorted({r[2] for r in out[1:]}, key=lambda b: [int(x) for x in b.split('.')]))
    print('  file: %s' % path)
    return 0


if __name__ == '__main__':
    sys.exit(main())
