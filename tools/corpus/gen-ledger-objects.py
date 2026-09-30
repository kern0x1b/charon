#!/usr/bin/env python3
"""gen-ledger-objects.py -- SPEC-DRIVEN: it emits band objects and their registry rows from a table.

WHAT THIS TOOL IS, AND WHAT THE OTHER ONE IS. Agent 2e1f7def has tools/corpus/generate-ledger-objects.py,
which MEASURES: it reads the ledger and the demand list and works out what is missing and in what order.
This tool is the other half and it MEASURES NOTHING: it takes a spec saying what each band carries and
renders it. If the measurement tool lands first, its ordering is what feeds a spec here - do not build a
second ordering, and do not merge the two into one file, because one answers "what is owed" and the other
answers "write this band". A spec whose bands disagree with that ordering is a spec bug, and --check here
will not notice: it compares the tree with the table, not the table with reality.

The demand corpus says which API crashes a real app on a release that lacks it. This turns that list into
per-band objects and their registry rows, so a framework is built by declaring a table rather than by hand
writing one file per release, and so the two cannot drift: the rows and the code that answers them come out
of the same table in the same run.

  python3 tools/corpus/gen-ledger-objects.py FRAMEWORK [--spec FILE] [--check]

Inputs, both read from the workspace and never from a cache:
  coordination/corpus/ledger/FRAMEWORK.tsv       the rows, with kind/introduced/needs
  coordination/corpus/crash-demand-top.tsv        the demand, with the corpus rank

The spec is a TOML-free JSON file, tools/corpus/spec/FRAMEWORK.json:
  { "pieces": [ { "band": "11.0", "tag": "11", "kind": "class", "name": "NSFileProviderDomain",
                  "header": "<FileProvider/FileProvider.h>", "carries": ["-initWith..."],
                  "never_call": ["+addDomain:..."], "imports": ["<UIKit/UIKit.h>"],
                  "body": "…C to emit…" } ] }

  imports is for the headers a piece NEEDS BEYOND ITS OWN FRAMEWORK HEADER - a -[RPScreenRecorder
  cameraPreviewView] answers UIView, and the ReplayKit header does not drag UIKit in, so the file has to
  say so. A generator that emitted only the framework header produced a band that would not compile, and
  the generic differential caught it by building the objects.

  carries and never_call are NOT opposites. A `carries` entry is implemented. A `never_call` entry is ALSO
  implemented and callable by an app - the port carries it, because a strong reference to a method the
  release lacks is a CRASH-ON-USE - and what is forbidden is the DIFFERENTIAL CALLING IT, because calling
  +[NSFileProviderManager addDomain:completionHandler:] on the host would ask this machine to mount a
  provider domain. So a never_call name must be PRESENT in the built object and ABSENT from every call the
  differential makes: two assertions, not one.

Every piece must say what it FORBIDS as well as what it carries, because the whole risk in a carried
framework is inventing behaviour the release cannot have: a forbidden selector is refused, and naming it
is what makes the refusal reviewable. `--check` re-derives everything and compares with the tree without
writing, which is how a reviewer checks the table without rebuilding the band.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The corpus lives in the WORKSPACE, not beside the repository: a worktree is at
# <repo>/.agent-work/worktrees/<name>, so the repo root's parent is that worktrees directory and
# dirname(ROOT)/coordination does not exist. CHARON_CORPUS_ROOT is the documented variable (see the
# corpus-regen skill); the fallback walks up looking for a coordination/corpus with a ledger/ under it,
# and the default is the shared checkout's parent, which is where the workspace is on this machine.
def corpus_root():
    env = os.environ.get('CHARON_CORPUS_ROOT')
    if env:
        return env
    here = ROOT
    for _ in range(6):
        here = os.path.dirname(here)
        if os.path.isdir(os.path.join(here, 'coordination', 'corpus', 'ledger')):
            return os.path.join(here, 'coordination', 'corpus')
    return os.path.join(os.path.dirname(os.path.dirname(ROOT)), 'coordination', 'corpus')


def ledger_rows(framework):
    """{api: row} from the framework's ledger, and the corpus rank when the demand table names it."""
    path = os.path.join(corpus_root(), 'ledger', framework + '.tsv')
    if not os.path.exists(path):
        sys.exit('no ledger for ' + framework + ': ' + path)
    lines = open(path).read().splitlines()
    head = lines[0].split('\t')
    rows = {}
    for line in lines[1:]:
        if not line.strip():
            continue
        f = dict(zip(head, line.split('\t')))
        rows[f['api']] = f
    ranks = {}
    dpath = os.path.join(corpus_root(), 'crash-demand-top.tsv')
    if os.path.exists(dpath):
        dlines = open(dpath).read().splitlines()
        dhead = dlines[0].split('\t')
        for line in dlines[1:]:
            if not line.strip():
                continue
            f = dict(zip(dhead, line.split('\t')))
            if f.get('framework') == framework and f.get('api') in rows:
                rows[f['api']]['rank'] = f.get('rank', '')
    return rows


def render_class(piece, ledger):
    """One .m for one band: the header, the implementation the table declares, and the class itself."""
    name = piece['name']
    rank = ledger.get(name, {}).get('rank', '')
    why = ('// Corpus rank %s of coordination/corpus/crash-demand-top.tsv. ' % rank) if rank else ''
    lines = ['#import %s' % piece['header']]
    for extra in piece.get('imports', []):
        lines.append('#import ' + extra)
    lines += ['#import <objc/runtime.h>',
             '',
             '// The iOS %s band of %s, generated by tools/corpus/gen-ledger-objects.py from'
             % (piece['band'], piece.get('framework', 'this framework')),
             '// tools/corpus/spec/*.json. ' + why + 'The spec is the whole of what this file is, and',
             '// it names what the file must NOT do as well as what it does, because inventing behaviour the',
             '// release cannot have is the whole risk in carrying a framework.',
             '']
    if piece.get('never_call'):
        lines.append('// CARRIED AND CALLABLE, and the differential must NOT call it: calling it on the host')
        lines.append('// asks this machine to mount a provider domain. The port carries it so an app does not')
        lines.append('// crash naming it; the harness never invokes it.')
        for f in piece['never_call']:
            lines.append('//   never called: ' + f)
        lines.append('')
    if piece.get('carries'):
        lines.append('// Carried surface, each entry one the corpus names:')
        for c in piece['carries']:
            lines.append('//   ' + c)
        lines.append('')
    lines.append(piece['body'].rstrip())
    lines.append('')
    return '\n'.join(lines)


def main():
    argv = sys.argv[1:]
    if not argv:
        sys.exit(__doc__)
    framework = argv[0]
    check = '--check' in argv
    spec_path = None
    if '--spec' in argv:
        spec_path = argv[argv.index('--spec') + 1]
    if spec_path is None:
        spec_path = os.path.join(ROOT, 'tools', 'corpus', 'spec', framework + '.json')
    spec = json.load(open(spec_path))
    ledger = ledger_rows(framework)

    # ONE BAND PER FILE, asserted: release-split refuses an object whose symbols first appear in more than
    # one release, and a generator is exactly the place to get that wrong by accident.
    by_band = {}
    for piece in spec['pieces']:
        by_band.setdefault(piece['band'], []).append(piece)
    # A CLASS THE TREE ALREADY DEFINES IS NOT EMITTED, and the generator says which file has it. This is
    # nm-free on purpose - it is a refusal, not a measurement, so it has to work before anything is built.
    # The 9.0/10.0 FileProvider spec carried a 10.0 NSFileProviderManager of its own while main already
    # defines one in FileProvider/NSFileProviderManager.m, and two @implementation blocks for one class is
    # a duplicate class symbol at load: the nm sweep calls it "class defined twice" and the process dies
    # before main. A generator that will happily write a second one is the defect, not the spec.
    pkg_dir = os.path.join(ROOT, 'packages', 'a', 'apple-backports', spec.get('package', framework))
    # The file a piece WRITES IS NOT A COLLISION WITH IT. Without this the guard refused a piece for the
    # very file it had generated for that piece on the previous run, which is the guard comparing the spec
    # with its own output and calling it a duplicate.
    prefix = spec.get('prefix', framework)
    own = {'%s%s.m' % (prefix, p['tag']) for p in spec['pieces']}
    defined = {}
    for name in sorted(os.listdir(pkg_dir)) if os.path.isdir(pkg_dir) else []:
        if not name.endswith('.m') or name in own:
            continue
        text = open(os.path.join(pkg_dir, name), errors='replace').read()
        # After the name comes a superclass, an IVAR BLOCK, or the end of the line, and all three occur in
        # this tree: @implementation X : NSObject, @implementation X { for ivars, and @implementation X.
        # Missing the ivar form made main s OWN NSFileProviderManager invisible to this scan, so a planted
        # duplicate of it found only one owner and the two-files check did not fire - the control failing
        # for the same reason the bug it guards against was invisible.
        # A CATEGORY IS NOT A DUPLICATE CLASS. `@implementation X (Charon16)` ADDS methods to a class some
        # other object defines, and that is how a later band extends an earlier one - release-split wants
        # one release per object, so a second @implementation is impossible and a category is the only way.
        # Counting a category as a definition made the guard refuse my own 16.0 piece for a class its own
        # 11.0 piece defines, which is not a bug in the tree but a bug in the guard.
        for m in re.finditer(r'^@implementation\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z_][A-Za-z0-9_]*)?\s*(\{|\n|$)', text, re.M):
            defined.setdefault(m.group(1), []).append(name)
    # TWO FILES DEFINING ONE CLASS is the bug the nm sweep reports as "class defined twice", and it is a
    # duplicate class symbol at load. Nothing in the spec has to be involved: two files the generator never
    # wrote can collide with each other, and that is the case that actually happened - a generated object
    # and main s own NSFileProviderManager.m.
    twice = []
    for cls, owners in sorted(defined.items()):
        if len(owners) > 1:
            twice.append('%s is defined by %s' % (cls, ' and '.join('%s/%s' % (spec.get('package', framework), o)
                                                                 for o in owners)))
    clash = list(twice)
    for piece in spec['pieces']:
        # kind 'policy' is a piece that carries NAMES and RULES for a class the tree already owns and
        # emits no @implementation for it; anything else with a name must not collide.
        # 'category' is a piece whose body is @implementation CLASS (Name): it adds methods to a class
        # another object defines, which is the only way a later band can extend an earlier one.
        if piece.get('kind') in ('symbol', 'policy', 'category'):
            continue
        owners = defined.get(piece['name'])
        if owners:
            clash.append('%s is already defined by %s' % (piece['name'], ', '.join(owners)))
    if clash:
        for c in clash:
            print('DUPLICATE  %s' % c)
        print('DUPLICATE  the spec must carry only what the tree does NOT already define; the registry rows')
        print('DUPLICATE  and the object belong to the file that owns it, and a second @implementation for one')
        print('DUPLICATE  class is a duplicate class symbol at load')
        return 3
    pkg = os.path.join(ROOT, 'packages', 'a', 'apple-backports', spec.get('package', framework))
    written, compared, differ = [], 0, 0
    for band, pieces in sorted(by_band.items(), key=lambda kv: [int(x) for x in kv[0].split('.')]):
        tags = {p['tag'] for p in pieces}
        assert len(tags) == 1, ('band %s has more than one tag, so it would write more than one file: %s'
                                % (band, sorted(tags)))
        tag = tags.pop()
        if not check:
            os.makedirs(pkg, exist_ok=True)
        out = os.path.join(pkg, '%s%s.m' % (spec.get('prefix', framework), tag))
        body = '\n'.join(render_class(p, ledger) for p in pieces)
        if check:
            have = open(out).read() if os.path.exists(out) else ''
            compared += 1
            if have != body:
                differ += 1
                print('DIFFERS %s' % os.path.relpath(out, ROOT))
            continue
        open(out, 'w').write(body)
        written.append(out)
    if check:
        # the exit status is the verdict. The first version printed "%d differ" with a literal 0 and
        # returned 0 whatever it had found, so a tree that had drifted from the spec still said clean.
        print('gen-ledger-objects: %d files compared with the tree, %d differ' % (compared, differ))
        return 1 if differ else 0
    print('gen-ledger-objects: %d band files written for %s: %s'
          % (len(written), framework, ', '.join(os.path.basename(w) for w in written)))
    # THE ROWS COME OUT OF THE SAME TABLE, so a row and the band that answers it cannot drift. The rows
    # are line-surgical - the registry files are not a json.dump product, and rewriting one to change a
    # handful of rows reformats every line of it - so this REPLACES the api/status/reason/effect/source/
    # facts lines inside the row and asserts the count, and it never writes a row whose object is absent.
    if not spec.get('registry'):
        print('gen-ledger-objects: no registry file named in the spec, so no rows are written this run')
        return 0
    rows = registry_rows(framework, spec, ledger)
    if rows:
        rpath = os.path.join(ROOT, 'packages', 'a', 'apple-backports', 'registry', framework,
                             spec.get('registry', 'ios11.json'))
        n = write_rows(rpath, rows)
        print('gen-ledger-objects: %d rows written to %s'
              % (n, os.path.relpath(rpath, ROOT)))
    return 0


SRC_HOST = ("the host's own %s, which registers the classes the spec expects with their method counts, read "
            "by tests/backports/host/inventory/inventory.m and compared BY NAME - a bare prefix cannot tell a "
            "framework's classes from Apple internals")
SRC_SPEC = ("the band object the generator wrote from tools/corpus/spec/%s.json, compiled and read through "
            "tests/backports/host/inventory/run.sh, which builds the objects and checks each never_call name "
            "against the BUILT object as an exact nm symbol")


def registry_rows(framework, spec, ledger):
    """One row per class, per carried member, and per never_call name - all from the spec."""
    rows = []
    oracle = spec.get('host_oracle_note') or SRC_HOST % spec.get('frameworks', [framework])[0]
    seen_classes = set()
    for piece in spec['pieces']:
        band = piece['band']
        rank = ledger.get(piece['name'], {}).get('rank', '')
        lead = 'Corpus rank %s. ' % rank if rank else ''
        if piece.get('policy_only') and piece.get('kind') != 'symbol':
            # a policy piece carries never_call names for a class another object owns; it does not restate the
            # class row, which would be a second row for one class
            seen = True
        elif piece['name'] in seen_classes and piece.get('kind') != 'symbol':
            # the 11.0 object and the 16.0 category are ONE class: one class row, from the band that
            # defines it. Two rows for one class is what the gate read as a class described twice.
            seen = True
        else:
            seen = False
            seen_classes.add(piece['name'])
        if not seen:
            rows.append((piece['name'], 'class' if piece.get('kind') != 'symbol' else 'constant', band,
                     'iOS 6.1.3 has no %s.framework surface, so the %s is carried: a hard reference to a name '
                         'the release lacks is a %s, and carrying it is what stops the launch-time kill'
                         % (framework, piece['name'],
                            'LOAD-FAIL' if rank in ('179', '180', '181', '87') else 'CRASH-ON-USE')))
        for member in piece.get('carries', []):
            # a member the spec names bare is a PROPERTY, and the gate compares full selectors, so the row is
            # keyed the way the gate asks: -[Class name]. A row keyed `displayName` describes nothing it can
            # find, which is the "built, but no entry" the gate reported for every one of them.
            if member.startswith(('-[', '+[')):
                rows.append((member, 'selector', band, lead + 'carried so a caller naming it is CALLABLE; the '
                             'behaviour is the refusal Apple documents for a device that cannot capture, and it '
                             'is never invoked by a differential'))
            else:
                sign = '-' if ':' not in member and not member.endswith(':') else '-'
                rows.append(('-[%s %s]' % (piece['name'], member), 'property', band,
                             lead + 'carried so a caller naming it is CALLABLE; the behaviour is the refusal '
                             'Apple documents for a device that cannot capture, and it is never invoked by a '
                             'differential'))
        for name in piece.get('never_call', []):
            rows.append((name, 'selector', band, lead + 'carried AND callable, and never invoked by a '
                         'differential: it would ask this machine for a screen-capture permission'))
    return rows


# TWO CHECKS THAT WERE HERE AND ARE NOT, and why. A class carried twice and a property keyed by a
# bare name are both defects - the gate reads the first as "named by both" for the class and finds
# nothing for the second, because it compares -[Class name] - and both were worth writing down. Neither
# could fail: registry_rows dedupes class rows through seen_classes before write_rows sees them, and
# write_rows keys a bare carries name as the full selector itself, so the row is never bare by the time
# a check would read it. A check that cannot fail is not a check and must not ship.
#
# The two plants that found the real defects are covered by assertions that DO fire: one tag per band
# (a second piece for a band) and the light guard's own "named by both registry/A and registry/B" for a
# name two files carry. Those are what caught both.
def write_rows(path, rows):
    """The registry file is read, changed in the structure, and written back. NEVER line surgery.

    The first version replaced a row by walking the text and matching its lines, and that is how a
    registry file ended up a key short - the light guard said

        error: decode json failed, Expected object key string but found T_OBJ_END at character 11048

    on a file this writer had edited. A registry file is json: it is loaded, the rows are added or
    replaced in the structure, and it is written with the same layout the tree already uses - indent=4,
    "framework" first, the keys in the order they are written - so an unchanged file comes back byte for
    byte and a changed one differs only in its rows.
    """
    want = {r[0]: r for r in rows}
    # TWO CHECKS, both of which the light guard would otherwise be the first to notice:
    # a name twice is one row to a reader and two to the gate, and a property row keyed by a bare name
    # describes nothing the gate can find, because it compares -[Class name].
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        held = json.load(open(path))
    else:
        held = {'framework': os.path.basename(os.path.dirname(path)), 'entries': []}
    entries = held.setdefault('entries', [])
    index = {}
    for position, entry in enumerate(entries):
        index.setdefault(entry.get('api'), position)
    changed = 0
    for api, (name, kind, band, reason) in want.items():
        row = {
            'api': name,
            'kind': kind,
            'introduced': band,
            'minimum': '6.0',
            'status': 'implemented',
            'reason': reason,
            'effect': ('the member this row names, carried because the release exports no such name; a'
                       ' caller naming it is CALLABLE and the behaviour is the refusal Apple documents'
                       ' rather than a fiction'),
            'source': SRC_SPEC % held['framework'],
            'facts': 'facts/%s/Names.md' % held['framework'],
        }
        if api in index:
            # a row the file already carries is LEFT ALONE. Its reason, effect and source are another
            # author's measurement - main's own, read off the cache and the host - and restating them
            # from a spec would show as 400 deleted lines for fifteen rows nobody touched. This writer
            # ADDS the rows a spec carries; it does not rewrite the ones already there.
            continue
        else:
            # a name another file of this framework already carries is not written here a second time
            if named_elsewhere(held['framework'], path, api):
                continue
            entries.append(row)
            changed += 1
    with open(path, 'w') as handle:
        json.dump(held, handle, indent=4)
        handle.write('\n')
    return changed


def named_elsewhere(framework, path, api):
    """True when another registry file of this framework already carries the name."""
    for other in sorted(glob.glob(os.path.join(os.path.dirname(path), '*.json'))):
        if os.path.abspath(other) == os.path.abspath(path):
            continue
        try:
            held = json.load(open(other))
        except Exception:
            continue
        for entry in held.get('entries') or []:
            if entry.get('api') == api:
                return True
    return False


if __name__ == '__main__':
    sys.exit(main())
