#!/usr/bin/env python3
"""rows-vs-objects.py REGISTRYDIR OBJECTSDIR: every implemented MediaPlayer constant row is backed by a
definition in the port's objects, and every definition in those objects has a row.

Written for the WHOLE family - every registry/MediaPlayer/*.json, not the one file a given series edits -
because the defect it exists to catch is precisely that a series touches one file and a row in another one
stays `implemented` with nothing behind it.

The definition and declaration patterns allow a space between the star and `const`, because the
tree writes both forms: MediaPlayerConstants*.m writes `NSString *const X` and MPMediaItem*.m
writes `NSString * const X`. A pattern for one form alone reported five constants that ARE carried
as unbacked, and had them added a second time - which review-mechanical.sh caught as a symbol
defined by two objects.

The comparison is over the registry's own words: a row is examined when its `kind` is "constant" and its
`status` is "implemented", and it is backed when some object defines that symbol. The count of rows
examined is printed and must be nonzero, because an empty comparison passes silently and a checker that
examined nothing has proved nothing.

usage: rows-vs-objects.py REGISTRYDIR OBJECTSDIR
exit:  0 the two sets agree, 1 they do not, 2 nothing was examined
"""
import glob
import json
import os
import re
import sys

DEFINE = re.compile(r'^NSString\s*\*\s*const\s+([\w.]+)\s*=', re.M)
DECLARE = re.compile(r'^extern\s+NSString\s*\*\s*const\s+([\w.]+)\s*;', re.M)


def rows_of(registry_dir):
    """{(symbol, file): entry} for every implemented constant row in the family."""
    found = {}
    files = sorted(glob.glob(os.path.join(registry_dir, '*.json')))
    if not files:
        return found, []
    for path in files:
        data = json.load(open(path))
        for entry in data.get('entries', []):
            if entry.get('kind') != 'constant':
                continue
            if entry.get('status') != 'implemented':
                continue
            found.setdefault(entry['api'], []).append(os.path.basename(path))
    return found, files


def definitions(objects_dir):
    """{symbol: object} for every constant the port's objects define, and the decls they promise."""
    defined, declared, objects = {}, set(), []
    for path in sorted(glob.glob(os.path.join(objects_dir, '*.m'))):
        text = open(path).read()
        objects.append(os.path.basename(path))
        for name in DEFINE.findall(text):
            defined.setdefault(name, os.path.basename(path))
        declared |= set(DECLARE.findall(text))
    return defined, declared, objects


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    registry_dir, objects_dir = sys.argv[1], sys.argv[2]
    rows, files = rows_of(registry_dir)
    defined, declared, objects = definitions(objects_dir)
    if not rows:
        print('rows-vs-objects: NO implemented constant row was examined, so nothing was proved')
        return 2
    print('  rows-vs-objects: %d implemented constant rows over %d registry files, %d objects, %d definitions'
          % (len(rows), len(files), len(objects), len(defined)))
    unbacked = sorted(n for n in rows if n not in defined)
    unrowed = sorted(n for n in defined if n not in rows)
    undeclared = sorted(n for n in defined if n not in declared)
    # a row with no definition is the defect; a definition with no row is the same defect the other way,
    # and a constant a file declares but never defines is a third one the media harness cannot see
    for name in unbacked:
        where = ', '.join(rows[name])
        print('  UNBACKED  %s is implemented in %s and NO object defines it' % (name, where))
    for name in unrowed:
        print('  UNROWED   %s is defined by %s and has no implemented constant row' % (name, defined[name]))
    for name in undeclared:
        print('  UNDECLARED %s is defined by %s but no file declares it extern' % (name, defined[name]))
    if unbacked or unrowed or undeclared:
        return 1
    print('  rows-vs-objects: every implemented constant row has an object, and every object has a row')
    return 0


if __name__ == '__main__':
    sys.exit(main())
