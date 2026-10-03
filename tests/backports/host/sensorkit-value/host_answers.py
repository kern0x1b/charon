#!/usr/bin/env python3
"""host_answers.py - the port's answers must be the host's, over what the host actually said.

    python3 host_answers.py <the output of host-answers.m>

Reads the ten COUNT lines, the two PROPERTY lines and the INIT line, and holds the port to them:

  - both counts must be 0 for every one of the ten sentiment categories. 0 and not nil: the host
    answers an integer, and a count of nothing typed in a category is zero.
  - both speech properties must be nil for a metrics object with no session, which is what the header's
    own nullable means with nothing behind it.
  - -[SRSensorReader init] must raise. The port produces that raise, in SRSensorReader.m, and this
    line is the measurement it is held to; the whole of the eighteen classes whose headers close the
    pair is in tests/backports/host/unavailable-init, which is where that one is now held twice - to
    the source and to the compiled object - so a harness that quoted the header's NS_UNAVAILABLE
    without measuring what the framework does about it would be quoting rather than checking.

Prints the three verdicts and a summary; exits non-zero if the host answered something else, because a
golden file that no longer matches what the host says is a harness that has stopped being evidence.
"""
import sys


def main():
    if len(sys.argv) != 2:
        sys.exit("host_answers.py: pass the output of host-answers.m")
    counts, properties, init = {}, {}, None
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if parts[0] == "COUNT" and len(parts) == 4:
            counts[parts[1]] = (parts[2], parts[3])
        elif parts[0] == "PROPERTY" and len(parts) == 3:
            properties[parts[1]] = parts[2]
        elif parts[0] == "INIT" and len(parts) == 2:
            init = parts[1]

    failures = []
    if len(counts) != 10:
        failures.append("the host answered %d sentiment categories, and this harness expects 10"
                        % len(counts))
    for category, (word, emoji) in sorted(counts.items()):
        if word != "word=0" or emoji != "emoji=0":
            failures.append("category %s: the host answers %s and %s, and it must answer word=0 emoji=0"
                            % (category, word, emoji))
    for name in ("speechRecognition", "soundClassification"):
        if properties.get(name) != "nil":
            failures.append("%s: the host answers [%s], and it must answer nil"
                            % (name, properties.get(name)))
    if init is None:
        failures.append("the host said nothing about -[SRSensorReader init]")
    elif not init.startswith("RAISES"):
        failures.append("-[SRSensorReader init]: the host answers [%s], and it must raise" % init)

    print("HOST COUNTS   %d categories, every word and emoji count 0: %s"
          % (len(counts), "yes" if not [f for f in failures if "count" in f or "categories" in f] else "NO"))
    print("HOST PROPERTY %s and %s both nil: %s"
          % ("speechRecognition", "soundClassification",
             "yes" if properties.get("speechRecognition") == "nil"
             and properties.get("soundClassification") == "nil" else "NO"))
    print("HOST INIT     %s" % (init if init else "(the host said nothing)"))
    for failure in failures:
        print("FAIL " + failure)
    print("sensorkit-value-host: %d failures%s" % (len(failures), "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())