#!/usr/bin/env python3
# check-constants.py : what every generator of the per-release constant files must assert, and what
# mine did not - so three of them lost files and names and the gate found them.
#
# The rule, once: write the new file, check it is non-empty and holds the names it is supposed to,
# check no name is defined twice across the whole folder, and only then remove the old one. This is
# that check, runnable on its own against a tree, and usable as a library by a generator.
#
#   usage: check-constants.py [FOLDER] [REGISTRY]
#   exit 0 when every name a registry claims is defined exactly once, and no name is defined twice.

import collections
import json
import os
import re
import sys

# A definition is a file-scope exported constant. A local inside a function that happens to be
# assigned a string is not one, and the "claimed by no registry" half of the check has to ignore it.
DEFINITION = re.compile(r'^(?:NSString \*const|CIFormat)\s+(\w+)\s*=\s*(.*);\s*$')


def definitions(folder):
    """Every name a source under `folder` defines, and where it is defined."""
    where = collections.defaultdict(list)
    for name in sorted(os.listdir(folder)):
        if not name.endswith('.m'):
            continue
        path = os.path.join(folder, name)
        with open(path) as source:
            for line in source:
                match = DEFINITION.match(line)
                if match:
                    where[match.group(1)].append(name)
    return where


def claimed_names(registry_glob):
    """Every name a registry claims as a constant, whatever framework file holds it."""
    claimed = set()
    for path in registry_glob:
        with open(path) as registry:
            content = json.load(registry)
            # a registry file is either one object with 'entries' or a bare list of them
            entries = content['entries'] if isinstance(content, dict) else content
            for entry in entries:
                if entry.get('kind') == 'constant':
                    claimed.add(entry['api'])
    return claimed


def registry_files(directory):
    """Every registry file, whether it sits beside the frameworks or inside one."""
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if os.path.isdir(path):
            for inner in sorted(os.listdir(path)):
                if inner.endswith('.json'):
                    yield os.path.join(path, inner)
        elif name.endswith('.json'):
            yield path


def check(folder, registry_glob, package=None):
    """The invariant, over a folder and the registry that claims its names.

    - a name defined twice **in this folder** is a duplicate symbol at link time;
    - a name this folder's registry claims and **no source in the package** defines is a row the gate
      will call "listed as implemented, but nothing of that name is built" - the one my generators kept
      producing, seventeen names at a time, because they wrote the new files and removed the old ones
      without checking the new ones were whole;
    - a name this folder defines that **no** registry claims is a definition nobody accounts for.
    """
    where = definitions(folder)
    everywhere = where
    if package:
        everywhere = {}
        for name in sorted(os.listdir(package)):
            if os.path.isdir(os.path.join(package, name)) and name not in ('registry', 'facts'):
                everywhere.update(definitions(os.path.join(package, name)))
    claimed = claimed_names(registry_glob)
    claimed_anywhere = claimed_names(registry_files(os.path.join(os.path.dirname(folder), 'registry'))) \
        if os.path.isdir(os.path.join(os.path.dirname(folder), 'registry')) else set(claimed)

    problems = []

    twice = {name: files for name, files in where.items() if len(files) > 1}
    for name, files in sorted(twice.items()):
        problems.append('defined in %s: %s' % (', '.join(sorted(files)), name))

    missing = sorted(claimed - set(everywhere))
    for name in missing:
        problems.append('claimed by a registry and defined nowhere in the package: %s' % name)

    unclaimed = sorted(set(where) - claimed_anywhere)
    for name in unclaimed:
        problems.append('defined here and claimed by no registry: %s' % name)

    for line in problems:
        print('constants: ' + line)
    print('constants: %d defined in this folder, %d claimed by its registry, %d problems'
          % (len(where), len(claimed), len(problems)))
    return not problems


def assert_write(path, expected):
    """What a generator must assert about a file it has just written, before it touches anything else.

    `expected` is the set of names the file is supposed to hold. It raises rather than returns, so a
    generator cannot carry on past a file that came out short.
    """
    if not os.path.exists(path):
        raise AssertionError('%s was not written' % path)
    if os.path.getsize(path) == 0:
        raise AssertionError('%s is empty' % path)
    held = set()
    with open(path) as source:
        for line in source:
            match = DEFINITION.match(line)
            if match:
                held.add(match.group(1))
    short = set(expected) - held
    if short:
        raise AssertionError('%s is short %d names: %s' % (path, len(short), ', '.join(sorted(short)[:5])))
    return held


def assert_no_duplicates(folder, names):
    """What a generator must assert about a set of names before it removes the files they were in."""
    where = definitions(folder)
    twice = {name: where[name] for name in sorted(names) if len(where.get(name, [])) > 1}
    if twice:
        raise AssertionError('still defined in more than one file: %s'
                             % ', '.join('%s in %s' % (n, ', '.join(v)) for n, v in list(twice.items())[:5]))


def carried_frameworks(libraries):
    """The folder-to-framework map the recipe declares, so a folder is held against its own registry
    and not against every registry in the tree."""
    mapping = {}
    with open(libraries) as recipe:
        for line in recipe:
            match = re.search(r'folder\s*=\s*"([^"]+)"', line)
            if match:
                # the library is named ModelIOBackports and its folder is ModelIO: the framework a
                # folder's registry sits under is that name without the Backports suffix, lowercased
                mapping[match.group(1)] = None
    with open(libraries) as recipe:
        for line in recipe:
            name = re.search(r'name\s*=\s*"(\w+)"', line)
            folder = re.search(r'folder\s*=\s*"([^"]+)"', line)
            if name and folder and name.group(1).endswith('Backports'):
                mapping[folder.group(1)] = name.group(1)[:-len('Backports')]
    return mapping


# The folders whose sources hold the constants their registry claims: each library's own folder. A
# library whose constants live in another folder is checked with that folder named on the command line.
# The folders this band writes, and where each one's constants live. A library whose constants are
# defined in another folder is checked with that folder named: the recipe says which folder a library's
# sources are in, not where its constants are defined, and the constants follow the definition.
CARRIED = {'Graphics': 'CoreImage', 'ModelIO': 'ModelIO'}


if __name__ == '__main__':
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    wanted = sys.argv[1:] or sorted(CARRIED)
    failed = 0
    for folder in wanted:
        framework = CARRIED.get(folder, folder)
        directory = os.path.join(root, folder)
        if not os.path.isdir(directory):
            print('%s: no such folder' % folder)
            failed = 1
            continue
        registry = os.path.join(root, 'registry', framework)
        files = sorted(registry_files(registry)) if os.path.isdir(registry) else []
        if not files:
            print('%s: no registry under registry/%s' % (folder, framework))
            failed = 1
            continue
        print('--- %s, against registry/%s' % (folder, framework))
        if not check(directory, files, root):
            failed = 1
    sys.exit(failed)
