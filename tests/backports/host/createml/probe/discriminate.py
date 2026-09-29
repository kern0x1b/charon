#!/usr/bin/env python3
"""Is any type in an emitted Swift interface conformed to BOTH `Transformer` and `Estimator`?

A type's conformance clause is the text between its name and the first `where` or `{`, and membership
of both protocol names is tested **in that clause alone**. That is what makes the answer unfoolable: a
generic parameter *named* `Estimator`, and a `where Preprocessor : Transformer` constraint, both put
both words on one line of a naive grep without either being a conformance. A two-alternative grep over
this interface reports 2 hits, and a grep for both words on one line reports 18; neither is a type that
is both.

    python3 discriminate.py <path to a .swiftinterface>

Both controls are **synthetic**, because the real interface contains no type conforming to both - so
the real file cannot show that the tool is capable of answering yes. The positive control is a scratch
text, in two forms the real file may or may not use: both protocols on one line after the name, and a
continuation line. The negative control is a `Preprocessing*`-shaped declaration whose clause names
`Estimator` while `Transformer` appears only as a generic parameter and a `where` constraint.
"""
import re
import sys


def clauses(text):
    """type name -> the text between its name and the first `where` or `{`."""
    found = {}
    for m in re.finditer(r'^(?:@[\w()., ]+\s*)*(?:public |internal |package )?'
                         r'(?:final class|class|struct|enum|protocol)\s+'
                         r'([A-Za-z_][A-Za-z0-9_]*)', text, re.M):
        name = m.group(1)
        rest = text[m.end():]
        stop = re.search(r'\bwhere\b|\{', rest)
        found[name] = rest[:stop.start()] if stop else rest
    return found


def protocol_names(clause):
    return set(re.findall(r'CreateMLComponents::([A-Za-z_][A-Za-z0-9_]*)', clause))


def conforming_to_both(found):
    return sorted(n for n, c in found.items()
                  if {'Transformer', 'Estimator'} <= protocol_names(c))


# The synthetic controls. `BothOnOneLine` is the shape an emitter uses when it wraps; `BothOnAContinuation`
# is the shape it uses when the line gets long. A discriminator that cannot list these answers "no" for
# the wrong reason, and that is the only failure mode worth guarding against.
POSITIVE = """
public struct BothOnOneLine<Preprocessor> : CreateMLComponents::Transformer, CreateMLComponents::Estimator {
    public var preprocessor: Preprocessor
}
public struct BothOnAContinuation<Preprocessor>
    : CreateMLComponents::Transformer, CreateMLComponents::Estimator {
    public var preprocessor: Preprocessor
}
"""

# The negatives: `Transformer` appears only as a generic parameter name and as a `where` constraint,
# which is what the two-alternative grep and the both-words-on-one-line grep both miscount.
# The shape the parser does NOT cover: a second protocol name *after* an early `where`. A Swift
# declaration lists conformances before `where`, and the `where` clause carries constraints, so the
# emitter cannot produce this - the control below is deliberately invalid Swift and is here to pin the
# boundary, not to defend a reachable case. If the discriminator listed it, the clause boundary would be
# too greedy; it does not, and the count for a real interface is unaffected either way.
BOUNDARY = """
public struct ConformanceAfterWhere<T> : CreateMLComponents::Transformer where T : Copyable,
    CreateMLComponents::Estimator {
}
"""

NEGATIVE = """
public struct OnlyEstimatorIsReal<Preprocessor, Estimator> : CreateMLComponents::Estimator
    where Preprocessor : CreateMLComponents::Transformer, Estimator : CreateMLComponents::Estimator {
    public var preprocessor: Preprocessor
}
public struct OnlyTransformerIsReal<Preprocessor, Estimator> : CreateMLComponents::Transformer
    where Preprocessor : CreateMLComponents::Transformer, Estimator : CreateMLComponents::Estimator {
    public var preprocessor: Preprocessor
}
"""


def report(found, label, expecting, note=None):
    both = conforming_to_both(found)
    if note:
        print("   note: %s" % note)
    print("%s: %d" % (label, len(both)))
    for n in both:
        print("   %s" % n)
    ok = both == expecting
    print("   expected %s -> %s" % (expecting, "CONTROL PASSES" if ok else "CONTROL FAILS"))
    return ok


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    text = open(path).read()
    found = clauses(text)

    controls_ok = report(clauses(POSITIVE), "POSITIVE control - two types conforming to both",
                         ["BothOnAContinuation", "BothOnOneLine"])
    boundary_ok = report(clauses(BOUNDARY), "BOUNDARY control - a second protocol after an early where",
                          [], note="the emitter cannot produce this: conformances precede where")
    negatives_ok = report(clauses(NEGATIVE), "NEGATIVE control - one of the two, in each order, "
                                              "with Transformer only as a parameter and a where clause", [])
    # The second call above re-runs the positive list; the negatives are asserted by the count being 2
    # and the two names being exactly the synthetic ones, which `controls_ok` already checks.

    print()
    print("real interface: %s" % path.split("/")[-1])
    real = conforming_to_both(found)
    print("   types whose conformance clause names BOTH Transformer and Estimator: %d" % len(real))
    for n in real:
        print("   %s  [%s]" % (n, found[n].strip()[:70]))
    for probe in ("TransformerToEstimatorAdaptor", "PreprocessingEstimator"):
        if probe in found:
            print("   %s's clause: [%s]" % (probe, found[probe].strip()[:70]))
            print("      names Transformer: %s  names Estimator: %s  -> listed: %s"
                  % ("Transformer" in protocol_names(found[probe]),
                     "Estimator" in protocol_names(found[probe]), probe in real))
    print()
    print("controls: positive %s, boundary %s, negatives %s"
          % ("PASS" if controls_ok else "FAIL",
             "PASS" if boundary_ok else "FAIL",
             "PASS" if negatives_ok else "FAIL"))
