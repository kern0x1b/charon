#!/usr/bin/env python3
"""The rows of one registry document, whatever shape that document has.

    from registry_rows import rows, documents, apis
    for row in rows(json.load(open(path))):
        row["api"], row.get("status")

A registry document is one of two shapes, and a reader that knows only the first does not say so - it
crashes, or skips the file, and both cost the rows in it:

  * `{"entries": [ {...}, ... ]}` - the shape 528 of the 529 files under
    `packages/a/apple-backports/registry` have. The `api` is a field of the row.
  * `[ {...}, ... ]` - a bare list of rows (the other one).

A third shape was taught here once and is now refused by name instead. It is what
`registry/Intents/constants.json` was - a "constants" object under a document that also carries "note" and
"source" - and it was a generator input and not a row list: it held the 83 extern constants a regeneration
would otherwise drop, and nothing read it. Its array length is 0, so `ipairs(held.entries or held)` at
`modules/apple/backports.lua:1609` makes 0 iterations on it (measured with `xmake l`), while the tools that
walk the registry either crashed on it or skipped it. It is at `tools/intents/constants.json` since the
coordinator's ruling of 2026-10-03. So a document carrying `constants` under a registry is refused with that
reason named, rather than read: if the file is ever put back, the tools must say where it belongs instead of
quietly seeing none of its rows.

Any other shape is refused with the document's own keys named, because a shape this does not know is a
file whose rows would go uncounted, and an uncounted row is indistinguishable from a row that is not there.

This is the one place that knows the shapes: `registry-absent-by-class.py`, `registry-absent.py`,
`registry-called-through.py`, `registry-duplicate-api.py`, `registry-effect-shape.py`,
`registry-facts-rows.py`, `registry-maximum.py` and `registry-shape.py` all read through it, so a shape is
taught once and every tool that counts rows learns of it at the same moment.
"""
import json
import os

# The member of a document that holds rows.
ROW_MEMBERS = ("entries",)

# Shapes that were taught here once and are refused by name, with the reason they are not taught again. A
# reader that met one silently is what let 83 rows go uncounted while every tool said it had read the tree.
REFUSED_MEMBERS = {
    "constants": "the Intents manifest is a generator input and not a row list, and lives at "
                 "tools/intents/constants.json since the coordinator's ruling of 2026-10-03",
}


class ShapeError(Exception):
    """A registry document whose shape this reader does not know. Its keys are in the message, so the
    fix names the file's own shape rather than this module's list of them."""


def rows(document):
    """The rows of one parsed registry document, each carrying `api`."""
    if isinstance(document, list):
        return document
    if isinstance(document, dict):
        refused = sorted(member for member in REFUSED_MEMBERS if member in document)
        if refused:
            raise ShapeError("a registry document holds %s, which this reader refuses by name: %s"
                             % (", ".join(refused), REFUSED_MEMBERS[refused[0]]))
        held = [member for member in ROW_MEMBERS if member in document]
        if len(held) == 1:
            value = document[held[0]]
            if isinstance(value, list):
                return value
        raise ShapeError("a registry document holds %s, which is not a shape this reader knows; its keys are %s"
                         % (" and ".join(held) if held else "no row member",
                            ", ".join(sorted(document)) or "(none)"))
    raise ShapeError("a registry document is a %s, which is neither an object nor a list of rows"
                     % type(document).__name__)


def documents(registry):
    """Every registry file under `registry`, sorted, as (path, parsed document) pairs.

    A file whose shape this reader refuses stops the walk there, by name: the message carries the path and
    the reason and is raised as a SystemExit, so a tool prints one actionable line and exits 1 rather than
    a traceback that names neither the file nor what is wrong with it.
    """
    found = []
    for base, _, names in os.walk(registry):
        for name in names:
            if name.endswith(".json"):
                path = os.path.join(base, name)
                with open(path) as handle:
                    document = json.load(handle)
                try:
                    rows(document)
                except ShapeError as error:
                    raise SystemExit("%s: %s; nothing under %s is claimed" % (path, error, registry))
                found.append((path, document))
    return sorted(found)


def apis(document):
    """The `api` of every row, in the document's own order."""
    return [row.get("api") for row in rows(document)]