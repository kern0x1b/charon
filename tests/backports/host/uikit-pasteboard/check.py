#!/usr/bin/env python3
"""The one reader the harness judges every run with: the clean run's, and each plant's.

    check.py <output-of-the-harness>

It reads what the port asked of the release's stand-in and says whether it is what the port must ask.
It is written once and run on EVERY output - the clean run and both plants - because a check that is
only pointed at the clean run cannot notice a plant, and a comment that says the plants go through it
has to be true.
"""
import sys

path = sys.argv[1]
lines = [l.rstrip("\n") for l in open(path) if l.strip()]


def only(prefix):
    return [l for l in lines if l.startswith(prefix)]


def need(ok, why, detail=None):
    print(("  ok   " if ok else "  FAIL ") + why + ("" if ok or detail is None else f"  {detail}"))
    return 0 if ok else 1


bad = 0
stored = only("setObjects: asked the release setValue|")
options_calls = only("setObjects:localOnly: asked the release setItems")
# every field the reader depends on, as a needle, so a plant that corrupts any one of them is caught
bad += need(any("setItems:options: asked the release setItems|2" in l for l in lines),
            "the 10.0 member hands both items to the release's own -setItems:")
bad += need(any("setItems:options: recorded 1 2030-01-01" in l for l in lines),
            "the two option keys are read and recorded: YES and the date the caller sent")
bad += need(len(stored) == 2, "-setObjects: stores through the release's own -setValue:forPasteboardType:",
            f"it asked for {len(stored)} values, and it must ask for two")
bad += need(any("|charon.string.type.one|plain" in l for l in stored),
            "-setObjects: stored the string under the FIRST entry of the string list", stored)
bad += need(any("|charon.url.type.one|https://example.invalid/x" in l for l in stored),
            "-setObjects: stored the URL under the FIRST entry of the URL list", stored)
bad += need(not any("charon.string.type.two" in l or "charon.url.type.two" in l for l in stored),
            "-setObjects: stored under no entry but the first", stored)
bad += need(any("setObjects:localOnly: asked the release setValue|charon.string.type.one|third" in l for l in lines),
            "the options path stores the objects it was given")
bad += need(any("setObjects:localOnly: recorded 1 2031-02-02" in l for l in lines),
            "the second member records its own two options")
bad += need(not options_calls,
            "the options path never calls the release's -setItems:, so the board is not emptied", options_calls)
bad += need(len(lines) >= 6,
            f"the run printed {len(lines)} lines, the fewest a verdict can rest on - fewer and nothing was read")
sys.exit(1 if bad else 0)
