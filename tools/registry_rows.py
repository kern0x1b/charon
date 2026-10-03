#!/usr/bin/env python3
"""The rows of one registry document, whatever shape that document has.

    from registry_rows import rows, documents, apis
    for row in rows(json.load(open(path))):
        row["api"], row.get("status")

A registry document is one of three shapes, and a reader that knows only the first two does not say
so - it crashes, or skips the file, and both cost the rows in it:

  * `{"entries": [ {...}, ... ]}` - the shape 519 of the 529 files under
    `packages/a/apple-backports/registry` have. The `api` is a field of the row.
  * `[ {...}, ... ]` - a bare list of rows (9 files).
  * `{"constants": {"NAME": {...}}, "note": ..., "source": ...}` - what
    `registry/Intents/constants.json` is: the row's fields are the value and the `api` is the key,
    so its constants are rows like any other and the name has to be put back into the row before a
    reader can ask for `api`.

The first two shapes' rows are returned as they are; the third's are copied with `api` filled in, so
a caller cannot tell the difference and nothing is written back. Any other shape is refused with the
document's own keys named, because a shape this does not know is a file whose rows would go
uncounted, and an uncounted row is indistinguishable from a row that is not there.

This is the one place that knows the shapes: `registry-duplicate-api.py`, `registry-effect-shape.py`,
`registry-facts-rows.py`, `registry-maximum.py` and `registry-shape.py` all read through it, so a
fourth shape is taught once and every tool that counts rows learns of it at the same moment.
"""
import json
import os

# The members of a document that hold rows, and for each whether a row's `api` is a field of the row
# or the key the row is filed under. A document carrying two of them is refused, not guessed at.
ROW_MEMBERS = {"entries": True, "constants": False}


class ShapeError(Exception):
    """A registry document whose shape this reader does not know. Its keys are in the message, so the
    fix names the file's own shape rather than this module's list of them."""


def rows(document):
    """The rows of one parsed registry document, each carrying `api`."""
    if isinstance(document, list):
        return document
    if isinstance(document, dict):
        held = [member for member in ROW_MEMBERS if member in document]
        if len(held) == 1:
            member = held[0]
            value = document[member]
            if ROW_MEMBERS[member]:
                if isinstance(value, list):
                    return value
            elif isinstance(value, dict):
                # The row's fields are the value and its name is the key: the api goes back in, so a
                # caller asks every row for `api` the same way whichever shape it came from.
                return [dict(fields, api=name) for name, fields in sorted(value.items())]
        raise ShapeError("a registry document holds %s, which is not a shape this reader knows; its keys are %s"
                         % (" and ".join(held) if held else "no row member",
                            ", ".join(sorted(document)) or "(none)"))
    raise ShapeError("a registry document is a %s, which is neither an object nor a list of rows"
                     % type(document).__name__)


def documents(registry):
    """Every registry file under `registry`, sorted, as (path, parsed document) pairs."""
    found = []
    for base, _, names in os.walk(registry):
        for name in names:
            if name.endswith(".json"):
                path = os.path.join(base, name)
                with open(path) as handle:
                    found.append((path, json.load(handle)))
    return sorted(found)


def apis(document):
    """The `api` of every row, in the document's own order."""
    return [row.get("api") for row in rows(document)]