"""A NAME THAT IS IN NEITHER TABLE, so the rule can be shown refusing it.

    VT_SDK=<an iPhoneOS*.sdk> python3 decoy_test.py

`DECLARED_KEYS` is the one place a class may say that an argument is spelled differently from its
property, and it is the ONLY way past the check that the property exists. That makes it the place a
generator's own mistake would go to hide: add `charonNotAProperty` to the table, and every store line for
it looks justified - the value lands under a key no accessor reads, and the differential reports nothing,
because the expectation is derived from the same table.

So the table carries a DECOY, and this test requires `store_key()` to REFUSE it. A rule that cannot be
made to fail on a nonsense name is a rule that will pass one.

It is a control rather than a row, and the difference matters: a row in the table would break every
ordinary run, and a check that is only ever run by hand is a check that is not run. So the decoy lives
in its own file, is named in neither PRIVATE_KEYS nor DECLARED_KEYS at run time, and the failure is
printed on every run of this test.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# A class that does not exist, and an argument that is not a property of anything. Nothing in the SDK
# declares either, so a rule that accepts this accepts a mistake.
DECOY_CLASS = "VTDecoyFrameProcessorConfiguration"
DECOY_ARGUMENT = "charonNotAProperty"


def load_gen_body():
    path = os.path.join(HERE, "gen_body.py")
    spec = importlib.util.spec_from_file_location("vt_gen_body", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert os.path.abspath(module.__file__) == path, "loaded a gen_body.py that is not this one"
    return module


def main():
    gen_body = load_gen_body()
    bad = []
    if (DECOY_CLASS, DECOY_ARGUMENT) in gen_body.DECLARED_KEYS:
        bad.append("the decoy is IN DECLARED_KEYS, so nothing would refuse it")
    if DECOY_ARGUMENT in gen_body.PRIVATE_KEYS:
        bad.append("the decoy is in PRIVATE_KEYS, so it would be stored as a private key")
    if DECOY_CLASS in gen_body.ORDER:
        bad.append("the decoy class is in ORDER, so the generator would try to emit it")

    # The refusal, and the message: the rule must name the class and the argument, because "no
    # property" with neither is a message nobody can act on.
    try:
        gen_body.store_key(DECOY_ARGUMENT, {}, "the decoy", DECOY_CLASS)
        bad.append("store_key ACCEPTED a name in neither table - the rule cannot fail")
    except SystemExit as refusal:
        print("  the decoy is refused, as it must be:")
        for line in str(refusal).split(". "):
            print("      %s" % line.strip())
        for wanted in (DECOY_ARGUMENT, DECOY_CLASS):
            if wanted not in str(refusal):
                bad.append("the refusal does not name %r, so it cannot be acted on" % wanted)
    for line in bad:
        print("FAIL " + line)
    if bad:
        return 1
    print("decoy: %s.%s is in neither table, and store_key refuses it by name"
          % (DECOY_CLASS, DECOY_ARGUMENT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
