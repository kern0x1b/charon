#!/usr/bin/env python3
"""Write the Intents registry from what the built code carries, not from a list.

An entry that says a member is implemented is worth nothing unless something checks it, and
modules/apple/backports.lua's check_registry is what checks it: it reads the classes, the
selectors and the symbols the package's libraries really export and refuses an entry that names
none of them. Writing eight hundred entries by hand would be eight hundred chances to claim a
member the library does not carry, so they are written from the generator's own report of what
it emitted, and every member the SDK declares and this delivery does not carry is written as
`absent` with the reason it is not there - a class of a later group of the same delivery, or a
header that marks the member unavailable - so that nothing is claimed in one direction and
missed in the other.

The rows come from the corpus (coordination/corpus/sdk-26.2-surface.tsv, the SDK 26.2 surface
after iOS 6.1); the `introduced` of each is the corpus's own, which is the availability the SDK's
headers give, and the release an object file is carried from is the one measure-intents.lua
measured against the armv7 release caches. The two disagree for one class of this framework
(INPaymentStatusResolutionResult: the header says 10.0, the caches say 10.3), and the caches
decide the object file while the header decides the entry, which is what each of them is for.

Usage:
    tools/intents/gen-registry.py --corpus <surface.tsv> --report <report.json>... \\
        --out <registry/Intents/ios10.json> --facts <facts/Intents/Intents.md> --release 10.0.1
"""

import argparse
import collections
import json
import os
import re

HAND_WRITTEN = {
    "INParameter",
    "INIntent", "INIntentResolutionResult", "INInteraction", "INImage", "INSpeakableString",
    "INVocabulary", "INPreferences", "INExtension", "INPaymentMethod", "INRideCompletionStatus",
}

# The class of the iOS 11.0 group that is hand written, and what it answers.
# repeated in facts/Intents/Intents.md, which the entries point at.
HAND_WRITTEN_EFFECT = {
    "INIntent": "init makes a UUID string identifier, which is the key the interaction store of "
                "this port keeps a donation under and the value the system writes itself at "
                "donation time; intentDescription is the class's own words with the framework's IN "
                "prefix and Intent suffix off, computed once and kept, since the SDK does not "
                "document how the framework derives it; setImage:forParameterNamed: and "
                "imageForParameterNamed: keep a real map of the intent's images by parameter name "
                "and keyImage returns the first parameter that has one, in parameter name order so "
                "the answer is the same on every call; the coding and copying walk the whole ivar "
                "chain, so a subclass keeps the identifier, the description and the images its "
                "parent has; donationMetadata is not answered and says so in its own entry",
    "INIntentResolutionResult": "needsValue, notRequired and unsupported each answer a new result "
                                "of the class that was asked, carrying the status the name says; "
                                "the three answers a typed resolution result is built from - a "
                                "resolved value, values to disambiguate, a value to confirm - are "
                                "read back through the four accessors of "
                                "CharonIntentsResolution.h, which is where a port reads what it "
                                "resolved, because on a release with Siri the system is the reader",
    "INInteraction": "initWithIntent:response: copies the intent and the response and makes a "
                     "UUID string identifier, and the direction is outgoing; "
                     "donateInteractionWithCompletion: stamps the date interval with the moment of "
                     "the donation, archives the interaction into this application's own store "
                     "under Application Support and calls the handler with nil, or with the error "
                     "the write failed with; the three deletion methods remove by identifier, by "
                     "group identifier and all of them, and say so the same way; the two "
                     "charon_interactions accessors read the store back, newest last",
    "INImage": "imageNamed: resolves the name in the app's own asset catalogue through UIKit and "
               "carries the image's data, and answers no image for a name the app has none of; "
               "systemImageNamed: answers no image, because the system images are SF Symbols and "
               "this release has no set of them; imageWithImageData: carries the data it is given; "
               "imageWithURL: and imageWithURL:width:height: read the URL and carry what it holds, "
               "with the size when one is given; the data, the name and the size are carried by "
               "the coding and the copy",
    "INSpeakableString": "the three initialisers keep the phrase, the pronunciation hint and the "
                         "vocabulary identifier they are given, copying each; the deprecated "
                         "initWithIdentifier: keeps the identifier as well and the identifier "
                         "accessor answers the vocabulary identifier, which is what the header's "
                         "own deprecation message says it should be used for; "
                         "initWithSpokenPhrase: keeps the phrase alone and invents no vocabulary "
                         "identifier for it; INSpeakable's own properties are carried and read",
    "INVocabulary": "sharedVocabulary is one instance for the process; setVocabularyStrings:ofType: "
                    "replaces the phrases of that type in this application's own store, in the "
                    "order they were offered; setVocabulary:ofType: keeps the spoken phrase of "
                    "each speakable value it is given; removeAllVocabularyStrings empties the "
                    "store; charon_vocabularyStringsOfType: reads a type back, which is where a "
                    "port reads what it offered, because on a release with Siri the system is the "
                    "reader",
    "INPreferences": "siriAuthorizationStatus answers INSiriAuthorizationStatusRestricted, which "
                     "is the header's own wording for a system where Siri services are restricted "
                     "and the user cannot change the answer; requestSiriAuthorization: answers the "
                     "handler with that same status instead of waiting for a prompt this release "
                     "cannot show, and does nothing for a handler of nil; siriLanguageCode answers "
                     "the language the release itself is set to, which is the one a voice would "
                     "use, since this release has no Siri setting to read",
    "INExtension": "the class carries nothing but NSObject's, as its own surface is empty; the one "
                   "requirement it inherits from INIntentHandlerProviding, handlerForIntent:, "
                   "answers the instance of the loaded class that conforms to the intent's own "
                   "handling protocol and responds to -handleIntent:, and answers nil where there "
                   "is none, which is what a release with no assistant daemon to launch an "
                   "extension has to say",
    "INPaymentMethod": "the initialiser keeps the type, the name, the identification hint and the "
                       "icon, copying each of the three objects; applePayPaymentMethod is the one "
                       "object of that kind for the whole process, of the type the header gives "
                       "and with no name, hint or icon of its own, because this release has no "
                       "image of it and no name for it",
    "INRideCompletionStatus": "the six factory methods answer a real status: completed is completed "
                              "and not outstanding, the two with a payment amount carry it, the one "
                              "with a feedback type is outstanding and carries the type, canceled "
                              "by service and canceled by the user are both canceled and neither "
                              "missed the pickup, and canceledMissedPickup is canceled and missed "
                              "it; the five derived answers - isCompleted, isCanceled, "
                              "isMissedPickup, isOutstanding, paymentAmount and feedbackType - are "
                              "computed from that state, and completionUserActivity and "
                              "defaultTippingOptions are kept",
}

HAND_WRITTEN_EFFECT["INParameter"] = (
    "parameterForClass:keyPath: keeps the class and the key path, which are the whole of what "
    "the header's two properties say a parameter is; isEqualToParameter: compares those two, so "
    "two parameters are the same parameter when they name the same class and the same key path; "
    "setIndex:forSubKeyPath: and indexForSubKeyPath: keep a real index per sub key path, and a "
    "sub key path that was never given one answers NSNotFound, which is what an NSUInteger return "
    "has to say for no index; the class and the key path and the indices are carried by the "
    "coding and the copy"
)

# What the class is where the class is one of the ten hand written ones, and what it answers.
# Every one of these lines is measured against the code in packages/a/apple-backports/Intents/ and

HAND_WRITTEN_REASON = (
    "behaviour that is more than the class's own storage, written by hand in "
    "packages/a/apple-backports/Intents/CharonIntents100.m"
)

GENERATED_REASON = (
    "a data class of the framework: every property the SDK's header declares is kept in the "
    "class's own state with the ownership the header gives it, the initialisers the header "
    "declares keep every value they are given, NSSecureCoding and NSCopying carry the whole "
    "ivar chain, and a member whose type is a class of a later group has an entry of its own "
    "below that says so"
)

GENERATED_EFFECT = (
    "every member the header declares has a body that stores or returns the class's own state; "
    "the object file is generated from the SDK's own declarations by tools/intents/gen-intents.py "
    "and this entry is written from what that generator emitted, read back out of the emitted text"
)

LATER_GROUP = "a class of a group of this delivery that is not in this one"


# The one member a hand written class of this delivery does not answer, and why. SF Symbols
# arrived with iOS 13: this release has no set of them, there is no API on it that could be asked
# for one, and the answer for a name the system has no symbol for is no image - which is what the
# class's own imageNamed: answers for a name the app has none of. The entry says absent rather
# than implemented, so that nothing claims the framework's behaviour where there is none.
NOT_ANSWERED = {
    "+[INImage systemImageNamed:]":
        "the SF Symbols this names arrived with iOS 13, and no release this package covers has "
        "them: there is no API on this release that could be asked for one, and the header's own "
        "imageNamed: answers no image for a name the app has none of",
}

SOURCE = ("the header of iPhoneOS 16.4 for the contract, and the armv7 release caches for the "
          "release each object file is carried from (tools/intents/measure-intents.lua)")


def generator_property_names(selector):
    """The property names one answered selector answers: its own, and a getter's name off it."""
    body = selector.partition("[")[2].partition(" ")[2].rstrip("]").strip()
    if ":" in body or not body:
        return []
    found = [body]
    if body.startswith("is") and len(body) > 2 and body[2].isupper():
        found.append(body[2].lower() + body[3:])
    return found


def spellings(selector):
    """The property names one answered selector answers: its own name, and a getter's name off it."""
    sign, owner, rest = selector.partition("[")
    name = rest.partition(" ")[2].rstrip("]").strip()
    if ":" in name or not name:
        return []
    found = [name]
    if name.startswith("is") and len(name) > 2 and name[2].isupper():
        found.append(name[2].lower() + name[3:])
    return found


def load_corpus(path, framework):
    rows = []
    for line in open(path):
        fields = line.rstrip("\n").split("\t")
        if len(fields) < 5 or fields[0] != framework:
            continue
        rows.append({"kind": fields[1], "lang": fields[2], "api": fields[3],
                     "introduced": fields[4], "deprecated": fields[5]})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--report", action="append", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--facts", required=True)
    parser.add_argument("--release", required=True)
    parser.add_argument("--framework", default="Intents")
    parser.add_argument("--classes", required=True, nargs="+",
                        help="the class names this file carries, one per line, one file per group "
                             "that shares it (the two 10.x groups share ios10.json)")
    parser.add_argument("--hand-written", default="CharonIntents100.m",
                        help="the file this group's hand written classes are in")
    parser.add_argument("--no-protocols", action="store_true",
                        help="this group writes no protocol row: another group's file already has it")
    parser.add_argument("--reason", required=True,
                        help="why a member whose type is a class of a later group is absent")
    options = parser.parse_args()

    answered = {}
    for path in options.report:
        for name, report in json.load(open(path)).items():
            answered.setdefault(name, {"properties": set(), "dynamic": set(), "methods": set()})
            for kind in ("properties", "dynamic", "methods"):
                answered[name][kind] |= set(report[kind])
            # A property answered by an accessor of its own - the ones a category of the SDK's own
            # header declares, which clang will not let a class implementation synthesise - is
            # answered just the same, and the registry has to say so.
            for method in list(answered[name]["methods"]):
                for spelling in generator_property_names(method):
                    answered[name]["properties"].add(spelling)

    classes = sorted(name for name in answered if name not in HAND_WRITTEN)
    carried = sorted(set(answered) | HAND_WRITTEN)
    # Only the classes of this group are this file's business: a class of another group of the
    # same delivery is that group's entry, and a member of one of those is skipped with it.
    group = set()
    for path in options.classes:
        group |= {line.strip() for line in open(path) if line.strip()}

    # What the hand written classes answer, read back out of the same text the compiler
    # compiled: a hand written class is no less checked than a generated one, so it goes through
    # the generator's own answer_of() and not through a second reading of the text.
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "gen_intents", os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen-intents.py"))
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)

    # <repository>/tools/intents/gen-registry.py -> <repository>/packages/a/apple-backports/Intents
    here = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "..", "..", "packages", "a", "apple-backports", "Intents")) + "/"
    hand_text = open(here + options.hand_written, errors="replace").read()
    hand_lines = hand_text.split("\n")
    for name in group | HAND_WRITTEN:
        block, start = [], None
        for index, line in enumerate(hand_lines):
            if line.startswith("@implementation %s" % name) and \
                    line[len("@implementation %s" % name):].strip() in ("", "{"):
                start = index
                continue
            if start is not None:
                if line.startswith("@implementation ") or line.startswith("@end"):
                    break
                block.append(line)
        if not block:
            continue
        answered.setdefault(name, {"properties": set(), "dynamic": set(), "methods": set()})
        report = generator.answer_of(block, name)
        for kind in ("properties", "dynamic", "methods"):
            answered[name][kind] |= set(report[kind])
        for method in list(answered[name]["methods"]):
            for spelling in generator_property_names(method):
                answered[name]["properties"].add(spelling)

    # A member of a hand written class is claimed only where the class's own @implementation
    # shows the accessor or the @synthesize. modules/apple/backports.lua's check_registry marks a
    # member built as soon as its owner class is exported, so a green gate says nothing about a
    # member's own accessor, and an entry that claims one the file does not have is exactly the
    # silent fake the rules forbid. This is the check that refuses to write it.
    hand_written = {name for name in HAND_WRITTEN}

    entries, missing = [], collections.Counter()
    for row in load_corpus(options.corpus, options.framework):
        api, kind, intro = row["api"], row["kind"], row["introduced"]
        owner = None
        if kind == "method":
            found = re.match(r"^[-+]\[([A-Za-z_0-9]+) ", api)
            owner = found.group(1) if found else None
        elif kind == "property":
            owner = api.split(".")[0]
        if kind == "constant" or kind == "enum":
            # A case of an enumeration and the type it belongs to are the header's own: the
            # compiler writes them into the application and the package carries nothing of them,
            # so registry/README.md gives them no entry. The lift brings the type down where
            # every API that uses it is implemented.
            continue
        if kind == "protocol":
            # A protocol is the framework's, not one group's: it is written once, in the file of
            # the group whose classes first conform to it, because two files naming one protocol
            # stop the build with both names.
            if options.no_protocols:
                missing["protocol of another group"] += 1
                continue
            entries.append({"api": api, "kind": "protocol", "introduced": intro,
                            "minimum": "6.0", "status": "implemented", "facts": options.facts,
                            "reason": "the protocol is the SDK's own declaration, carried by the "
                                      "header once the availability of its members is lowered, and "
                                      "the members are the entries of this file",
                            "source": SOURCE})
            continue
        if kind == "typealias":
            continue
        if kind == "swift" or row["lang"] == "swift":
            # The Swift-only rows of this framework are the swift-runtime's own module and not
            # this package's; they are in the delivery of the Swift side of AppIntents.
            continue
        if owner is not None and owner not in group:
            missing["another group"] += 1
            continue
        if owner is not None and owner not in answered:
            # A member of a class this delivery does not carry is not this file's entry: it is
            # the entry of the group that carries that class, and writing it here as absent
            # would say the framework never has it.
            missing["later group"] += 1
            continue
        if owner is not None and owner in answered:
            report = answered[owner]
            if kind == "property":
                spelled = api.split(".")[1]
                if spelled in report["properties"]:
                    entries.append(implemented(api, "property", intro, owner, options.facts,
                                               where="%s's own @implementation synthesises it"
                                                     % owner if owner in hand_written else None))
                    continue
                if api.split(".")[1] in report["dynamic"]:
                    entries.append(absent(api, "property", intro, options.reason, options.facts))
                    missing["dynamic"] += 1
                    continue
            if kind == "method":
                if api in NOT_ANSWERED:
                    entries.append(absent(api, "method", intro, NOT_ANSWERED[api], options.facts))
                    missing["not answered"] += 1
                    continue
                if api in report["methods"]:
                    entries.append(implemented(api, "method", intro, owner, options.facts,
                                               where="%s's own @implementation answers it"
                                                     % owner if owner in hand_written else None))
                    continue
                if api.endswith("] init") or api == "-[%s init]" % owner:
                    entries.append(absent(api, "method", intro,
                                          "the header marks the class's -init unavailable, so a port "
                                          "cannot call it and the class answers the initialiser "
                                          "the header does declare", options.facts))
                    missing["init"] += 1
                    continue
                entries.append(absent(api, "method", intro,
                                      "an initialiser that takes a value of a class this delivery "
                                      "does not carry is not given a body, because a body that "
                                      "dropped that value would answer with a class that looks "
                                      "filled and is not", options.facts))
                missing["skipped"] += 1
                continue
        if kind == "class":
            if api in group:
                entry = {"api": api, "kind": "class", "introduced": intro, "minimum": "6.0",
                         "status": "implemented", "facts": options.facts, "source": SOURCE}
                if api in HAND_WRITTEN_EFFECT:
                    entry["reason"] = HAND_WRITTEN_REASON
                    entry["effect"] = HAND_WRITTEN_EFFECT[api]
                else:
                    entry["reason"] = GENERATED_REASON
                    entry["effect"] = GENERATED_EFFECT
                entries.append(entry)
                continue
            missing["another group"] += 1
            continue
        # A member of a class this delivery does carry and does not answer: a class of a later
        # group of this same delivery, or a member the SDK's own header marks unavailable. It is
        # written as absent with that reason rather than left out, so that nothing is claimed in
        # one direction and missed in the other.
        reason = options.reason
        if owner in hand_written:
            # A member of a hand written class whose accessor the file does not show: the reason
            # says so, and the count says how many, so a delivery cannot quietly claim one.
            reason = ("this is a member of a hand written class and %s's @implementation shows no"
                      " accessor of that name for it, so nothing in the package answers it; the"
                      " header's declaration alone is not an implementation" % owner)
            missing["hand written without an accessor"] += 1
        entries.append(absent(api, kind, intro, reason, options.facts))
        missing["unanswered member"] += 1

    entries.sort(key=lambda entry: (entry["kind"], entry["api"]))
    document = {"framework": options.framework, "entries": entries}
    with open(options.out, "w") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")
    tally = collections.Counter(entry["status"] for entry in entries)
    print("%s: %d entries (%s), %d not carried: %s" %
          (options.out, len(entries), ", ".join("%s %d" % pair for pair in sorted(tally.items())),
           sum(missing.values()), dict(missing)))
    return 0


def implemented(api, kind, introduced, owner, facts, where=None):
    return {"api": api, "kind": kind, "introduced": introduced, "minimum": "6.0",
            "status": "implemented", "facts": facts,
            "reason": ("a member of %s, which %s" % (owner, where or
                       "the class's own generated implementation answers")),
            "source": SOURCE}


def absent(api, kind, introduced, reason, facts):
    return {"api": api, "kind": kind, "introduced": introduced, "status": "absent",
            "reason": reason,
            "effect": "the class is there and does not implement this: respondsToSelector: answers "
                      "no, and a port that reached it would not find it",
            "facts": facts}


if __name__ == "__main__":
    raise SystemExit(main() or 0)
