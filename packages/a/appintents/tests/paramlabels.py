#!/usr/bin/env python3
"""External labels of a Swift parameter list, parsed out of a declaration's text.

A Swift parameter carries an **external label** and an **internal name**: `_ item:` is the label `_`
with the internal name `item`, and it is the *label* a caller writes. A single token (`items:`) means
the label and the internal name are the same word. So:

* `_ item:`      -> label `_`,    internal `item`
* `items:`       -> label `items`, internal `items`
* `item:`        -> label `item`,  internal `item`   <- a caller must now write `item:`

which is why changing `_ item:` to `item:` is a defect and changing it to `_ item2:` is not: the
second changes only the internal name, which no caller can see.

The parser is deliberately text-level and bounded: it is a *shape* check, run on the declaration's
own text, and it does not need a build.

    import("paramlabels")  -- or: from paramlabels import parameters, external_labels
"""
import re


def _split_top_level(text):
    """Split a parameter list on the commas that are not inside brackets."""
    out, depth, current = [], 0, ""
    for ch in text:
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(current)
            current = ""
        else:
            current += ch
    if current.strip():
        out.append(current)
    return out


def parameters(declaration):
    """[(label, internal, text)] for one declaration's parameter list, in order."""
    m = re.search(r"func\s+\w+\s*(?:<[^>]*>)?\s*\(", declaration)
    if not m:
        return []
    start = m.end() - 1
    depth, end = 0, None
    for i in range(start, len(declaration)):
        if declaration[i] == "(":
            depth += 1
        elif declaration[i] == ")":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is None:
        return []
    out = []
    for part in _split_top_level(declaration[start + 1:end]):
        text = part.strip()
        if not text:
            continue
        head = re.match(r"(?:@[\w()., :]+\s*)*(?:(\w+)|(\w+)\s+(\w+))\s*:", text)
        if not head:
            # an unlabelled parameter: the whole name is both
            name = text.split(":")[0].split()[0] if ":" in text else text.split()[0]
            out.append((name, name, text))
            continue
        first, second = head.group(1), head.group(2)
        if first is not None:                      # `label:` -- one token, so it is both
            out.append((first, first, text))
        elif second == "_":                       # `_ internal:` -- the *label* is the wildcard `_`
            out.append(("_", head.group(3), text))
        else:                                      # `label internal:`
            out.append((second, head.group(3), text))
    return out


def declaration_at(text, name, start=0):
    """The whole declaration of `name` beginning at or after `start`, matched by **balanced
    parentheses**.

    A bounded window ending at the first `->` is wrong for any declaration whose *parameter type*
    contains one -- an `async` closure does: `continuation: (@MainActor () async throws -> Void)?`
    has its `->` inside the parameter, so the window ends there and the parameters parse as none.
    """
    at = text.find("func " + name, start)
    if at < 0:
        return None
    open_paren = text.find("(", at)
    if open_paren < 0:
        return None
    depth, i = 0, open_paren
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    end = text.find("\n", i)
    return text[at:end if end > 0 else i + 1]


def external_labels(declaration):
    """Just the labels, in order -- the part a caller writes."""
    return [label for label, _internal, _text in parameters(declaration)]
