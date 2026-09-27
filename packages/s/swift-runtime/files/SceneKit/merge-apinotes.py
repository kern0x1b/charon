#!/usr/bin/env python3
"""Merge a clang apinote's duplicate top-level keys into one, and write it out.

The SDK's SceneKit.apinote has two top-level `Protocols:` keys, one at line 26 and one at line
141, and a YAML mapping cannot have the same key twice, so Swift's importer refuses the module
outright for every target (measured 2026-09-27 against iPhoneOS16.4.sdk,
cccc080d0cbe42c2a85b1369aba6e290):

    .../SceneKit.apinotes:141:1: error: duplicated mapping key 'Protocols'
    sk.swift:1:8: error: could not build Objective-C module 'SceneKit'

Clang accepts the file, which is why the backports' own Objective-C sources build. This
rewrites it with one `Protocols:` key holding both lists, in their own order, and every other
section exactly where it was.

The merge is a block parse keyed on the top-level keys, because the file is a list of `- Name:`
items with nested mappings and its own comments: a line at column 0 that is not a comment, a
list item or the `---` document marker, and ends in a colon, starts a section, and everything
up to the next such line belongs to it.

The rewrite is refused unless three checks agree: the same number of `- Name:` entries in and
out, the same set of sections as the block parse found, and - when PyYAML is installed - that
the result parses as a mapping with the same sections the original parses as.

Usage: merge-apinotes.py <in> <out>
"""
import sys


def top_level_key(line):
    """The section a line starts, or None. A top-level key is at column 0, is not a comment and
    not a list item, and ends in a colon. The `---` the file opens with is a document marker."""
    if not line or line[0] in " \t#-" or line.rstrip() == "---":
        return None
    stripped = line.rstrip()
    return stripped[:-1] if stripped.endswith(":") else None


def sections(lines):
    """(name, index of the key line or None, body) for every section, in order."""
    blocks = []
    for index, line in enumerate(lines):
        name = top_level_key(line)
        if name is not None:
            blocks.append([name, index, []])
        elif blocks:
            blocks[-1][2].append(line)
        else:
            blocks.append([None, None, [line]])
    return blocks


def list_lines(body):
    """The lines of a block that belong to a list: the entries, the lines nested under them, the
    blank lines and the comments. Anything else - a line at column 0 that is not one of those -
    is left to the caller, so that nothing this parser does not understand is dropped."""
    kept = []
    for line in body:
        if not line.strip() or line.lstrip().startswith("#") or line.startswith((" ", "-")):
            kept.append(line)
    return kept


def merge(lines, key):
    """The file with every block naming `key` folded into the first one, in order."""
    blocks = sections(lines)
    out = []
    folded = []
    seen = False
    for name, index, body in blocks:
        if name != key:
            if index is not None:
                out.append(lines[index])
            out.extend(body)
            continue
        if not seen:
            seen = True
            out.append(lines[index])
            folded = list_lines(body)
            continue
        folded.extend(list_lines(body))
    # the folded list goes where the first block's own list was
    result = []
    seen = False
    for name, index, body in blocks:
        if name != key:
            if index is not None:
                result.append(lines[index])
            result.extend(body)
        elif not seen:
            seen = True
            result.append(lines[index])
            result.extend(folded)
    return result


def count_entries(lines):
    return sum(1 for line in lines if line.startswith("- Name:"))


def parsed_sections(path):
    """The sections a YAML loader sees, or an empty set when PyYAML is not installed: a loader
    keeps the last of a duplicated key, so this is the set the result has to match."""
    try:
        import yaml
    except ImportError:
        return set()
    with open(path) as handle:
        loaded = yaml.safe_load(handle)
    return set(loaded) if isinstance(loaded, dict) else set()


def main():
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        return 2
    source, target = sys.argv[1], sys.argv[2]
    original = open(source).read().split("\n")
    keys = [key for key, _, _ in sections(original) if key]
    duplicates = sorted({key for key in keys if keys.count(key) > 1})
    if not duplicates:
        sys.stderr.write("no duplicate top-level key in %s: it is written through\n" % source)
        open(target, "w").write("\n".join(original))
        return 0

    entries_before = count_entries(original)
    expected = set(keys) | parsed_sections(source)
    merged = original
    for key in duplicates:
        merged = merge(merged, key)
    entries_after = count_entries(merged)
    if entries_after != entries_before:
        sys.stderr.write("refused: the merge changed the entry count, %d `- Name:` in and %d out\n"
                         % (entries_before, entries_after))
        return 1
    merged_keys = [key for key, _, _ in sections(merged) if key]
    if set(merged_keys) != set(keys) or len(merged_keys) != len(set(merged_keys)):
        sys.stderr.write("refused: the merge changed the sections, %s became %s\n"
                         % (sorted(set(keys)), sorted(merged_keys)))
        return 1
    open(target, "w").write("\n".join(merged))
    with open(target) as handle:
        seen = yaml_sections(handle) if _has_yaml() else None
    if seen is not None and seen != expected:
        sys.stderr.write("refused: the merged file parses as %s, not %s\n"
                         % (sorted(seen), sorted(expected)))
        return 1
    sys.stderr.write("merged the duplicate top-level %s of %s: %d `- Name:` entries in and %d out, "
                     "sections %s%s\n"
                     % (", ".join(duplicates), source, entries_before, entries_after,
                        sorted(set(merged_keys)),
                        "" if seen is None else "; the result parses as a mapping with the sections %s" % sorted(seen)))
    return 0


def _has_yaml():
    try:
        import yaml  # noqa: F401
        return True
    except ImportError:
        return False


def yaml_sections(handle):
    import yaml
    loaded = yaml.safe_load(handle)
    return set(loaded) if isinstance(loaded, dict) else set()


if __name__ == "__main__":
    sys.exit(main())
