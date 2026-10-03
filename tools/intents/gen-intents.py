#!/usr/bin/env python3
"""Emit the Intents backport's data classes from the SDK's own declarations.

The Intents surface of SDK 26.2 is 3440 rows for the port, 308 of them classes.
Writing them by hand would take a month and get most of them wrong in the same
way, so they are generated from what the compiler itself says a class is: the
Objective-C AST of the SDK the port compiles against, which is the one
description of the contract that cannot be a guess.

What is generated:

  * one object file per release the release caches measure a class symbol first
    exported in, because an object carries API of exactly one release
    (modules/apple/backports.lua's check_releases). The release is read from the
    file the caller passes, which tools/intents/measure-intents.lua measured
    against the real caches; the header's own availability annotation is not used
    for it, and it is wrong where the two disagree (INPaymentStatusResolutionResult
    is exported by iOS 10.3, and the header says 10.0).
  * for each class: an ivar per stored property, the synthesised properties, the
    setters with the ownership the header declares, every declared initialiser,
    NSSecureCoding and NSCopying where the header asks for them, the resolution
    result's value / values to disambiguate / value to confirm, and a body for
    every other method the header declares.
  * the properties a conformed protocol requires and the class does not declare
    itself, so a class really conforms (INSpeakable's spokenPhrase and the rest).

What is not generated, because a generated body would be the silent fake the
rules forbid: INIntent's identifier and its image parameters, INInteraction's
donation and deletion, INVocabulary's store, INPreferences' answers for a
release with no Siri, INImage's ways of being made, INPaymentMethod's Apple Pay
method, INRideCompletionStatus' derived answers, and INIntentResolutionResult's
needsValue / notRequired / unsupported. Those are hand written in
CharonIntents100.m and this generator leaves their classes out.

A member whose type is an Intents class of a group this delivery does not carry
is left out with `@dynamic` and takes a registry entry of its own that says so,
rather than answering nil or zero: the mark stays on the header, so a port
cannot call it, and respondsToSelector: says no instead of crashing.

Usage:
    tools/intents/gen-intents.py --sdk <iPhoneOS*.sdk> --dump <ast.json> \\
        --classes <file> --release <measured> --out <file.m>

    --dump is
        clang -target arm64-apple-ios<ver> -isysroot <sdk> -fsyntax-only
              -x objective-c -Wno-everything -Xclang -ast-dump=json umbrella.m
    where umbrella.m holds `#import <Intents/Intents.h>`, and --classes is one
    class name per line, the classes of exactly one release.
"""

import argparse
import json
import re
import sys

# The ten classes whose bodies are hand written in CharonIntents100.m.
HAND_WRITTEN = {
    "INParameter",
    "INIntent",
    "INIntentResolutionResult",
    "INInteraction",
    "INImage",
    "INSpeakableString",
    "INVocabulary",
    "INPreferences",
    "INExtension",
    "INPaymentMethod",
    "INRideCompletionStatus",
}

# The base every resolution result shares, and the factories that fill it.
RESOLUTION_BASE = "INIntentResolutionResult"

# Where an initialiser parameter goes when the header's own names differ. Each line names the
# class, the selector part and the property or properties the value belongs in, with the header's
# own words for why; a parameter not in this table and not named after a property stops the
# generator rather than being dropped. Every line was read off the header of iPhoneOS16.4 and is
# repeated in facts/Intents/Intents.md.
PARAMETER_PROPERTIES = {
    # INBillPayee and INPaymentAccount take the number of an account and expose it as
    # accountNumber; the class has exactly one NSString property, which is that one.
    ("INBillPayee", "initWithNickname:number:organizationName:", "number"): ["accountNumber"],
    ("INPaymentAccount", "initWithNickname:number:accountType:organizationName:", "number"): ["accountNumber"],
    ("INPaymentAccount",
     "initWithNickname:number:accountType:organizationName:balance:secondaryBalance:",
     "number"): ["accountNumber"],
    # INPriceRange: "the lowest of the two prices used to construct this range" is the header's
    # own comment on minimumPrice, and the highest is maximumPrice, and initWithPrice: gives one
    # price that is both ends of the range.
    ("INPriceRange", "initWithRangeBetweenPrice:andPrice:currencyCode:", "firstPrice"): ["minimumPrice"],
    ("INPriceRange", "initWithRangeBetweenPrice:andPrice:currencyCode:", "secondPrice"): ["maximumPrice"],
    ("INPriceRange", "initWithPrice:currencyCode:", "price"): ["minimumPrice", "maximumPrice"],
    # INInteraction's designated initialiser spells the response intentResponse.
    ("INInteraction", None, "response"): ["intentResponse"],
}


# Properties whose ownership is copy: the setter copies, the rest retain.
COPIED = re.compile(
    r"^(NSString|NSAttributedString|NSMutableString|NSDictionary|NSMutableDictionary|NSArray|"
    r"NSMutableArray|NSSet|NSMutableSet|NSOrderedSet|NSMutableOrderedSet|NSIndexSet|NSData|"
    r"NSDate|NSURL|NSUUID|NSCharacterSet|NSLocale|NSDateComponents|NSRegularExpression|"
    r"INSpeakableString|INImage|NSError)$")

# The SDK writes its macros in front of, after, or inside a type: API_AVAILABLE, API_UNAVAILABLE,
# NS_REFINED_FOR_SWIFT, API_DEPRECATED_WITH_REPLACEMENT, NS_SWIFT_NAME and the rest are all one
# word of capitals and underscores, and one of them carries a parenthesised argument. Every one
# is removed wherever it stands, because a type spelled with a macro in it does not compile.
MACRO = re.compile(r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b")


def clean(text):
    """A type as the compiler spells it, without the SDK's macros or its nullability."""
    text = re.sub(r"_\s*(Nonnull|Nullable)\b", "", text or "")
    while True:
        found = MACRO.search(text)
        if not found:
            return text.strip()
        end = found.end()
        if text[end:end + 1] == "(":
            depth, index = 0, end
            while index < len(text):
                if text[index] == "(":
                    depth += 1
                elif text[index] == ")":
                    depth -= 1
                    if depth == 0:
                        index += 1
                        break
                index += 1
            end = index
        text = text[:found.start()] + " " + text[end:]


def objects(text):
    """Every top-level JSON object of a clang -ast-dump=json stream, in order."""
    decoder = json.JSONDecoder()
    index, length, out = 0, len(text), []
    while index < length:
        while index < length and text[index] in " \t\r\n":
            index += 1
        if index >= length:
            break
        node, index = decoder.raw_decode(text, index)
        out.append(node)
    return out


def top_level(path):
    """The translation unit's own declarations, in order.

    clang writes one JSON object for the whole translation unit, so the declarations are its
    `inner`, one entry per header.
    """
    found = []
    for node in objects(open(path, "r", errors="replace").read()):
        if node.get("kind") == "TranslationUnitDecl":
            found.extend(node.get("inner") or [])
        else:
            found.append(node)
    return found


def base_type(qual):
    """The name a type is written with, its pointers and qualifiers off."""
    text = spelled(qual)
    if text.startswith("void (^") or text.startswith("block"):
        return "block"
    text = re.sub(r"\bvoid\s*\(\s*\^[^)]*\)\s*\([^)]*\)", "block", text)
    text = re.sub(r"<[^<>]*>", "", text)
    text = text.replace("*", "")
    text = re.sub(r"\([^()]*\)", "", text)
    text = text.replace("const", "").replace("volatile", "").replace("struct", "").strip()
    return text.split()[0] if text.split() else text


def spelled(qual):
    """A type as a definition spells it: the macros off, nullability kept, spacing even.

    A lightweight generic parameter is the caller's type and not this package's: an
    INObjectSection<ObjectType> is an INObjectSection here, and an array of them keeps its
    array. A bare ObjectType - a property of a bare generic - is whatever the caller passes.
    """
    text = re.sub(r"\s+", " ", clean(qual)).strip() or "id"
    if "ObjectType" in text:
        text = re.sub(r"<\s*ObjectType\s*>", "", text)
        text = re.sub(r"\bObjectType\b", "id", text)
    return text


# A class that must be an object file of its own, with the measurement that says why.
#
# INPaymentMethodResolutionResult is the one class of its group that a release *below* the group's
# own already exports: the armv7s cache of iOS 10.3.4 has it, the arm64e cache of 16.0 has it, and
# the 94 classes beside it in IN16_0.m it does not. One object that defines both is what
# modules/apple/backports.lua's band() refuses - "an object carries API that arrived in one
# release, so split it" - and it refused it in the armv7 band at 10.3.4 while the 6.1.3 gate, which
# links the deployment band alone, did not. A one-class object is consistent in every band: the
# release that has it re-exports the object, and every release that does not keeps it.
#
# Measured, not guessed: tools/intents/measure-group.lua walks the group's own release cache and
# the one below and names the classes the two disagree about. The 16.0 group against the 10.3.4
# armv7s cache names exactly this one.
ALONE_REASON = """
%(name)s is an object file of its own because a release below this group's own already
exports it: the armv7s cache of iOS %(below)s has it, and the caches of this group's own
release do not have the classes it would share an object with. One object that defines
both is what the band check refuses, and a one-class object is consistent in every band:
the release that has it re-exports the object, and every release that does not keeps it.
The measurement is tools/intents/measure-group.lua, and the reason is the comment above
ALONE in the generator that wrote this file.
"""

ALONE = {
    "INPaymentMethodResolutionResult": "10.3",
}

# Why a member is not answered, one cause per way the generator leaves one out. The registry
# writes the reason from these, so a reason names the cause and not the owner's group - which is
# what N3 was about: an entry said "a class of a later group" for a member whose class this
# delivery carries, for a member that is not an initialiser at all, and for a factory that
# returns an array rather than a result.
CAUSES = {
    "later_group":
        "the class this member's type names is in a later group of this same delivery",
    "forward_only_class":
        "the class this member's type names is a class the SDK's headers only forward declare, so "
        "no header of the port's own SDK defines it and a body would not compile against one",
    "deferred_value":
        "an initialiser that takes a value of a class this delivery does not carry is not given a "
        "body, because a body that dropped the value would answer with a class that looks filled "
        "and is not",
    "chain_nonnull":
        "the superclass's designated initialiser takes a parameter the SDK does not mark nullable "
        "and nothing in the headers says where a subclass would get one, so the port refuses to "
        "chain rather than make a call the SDK forbids",
    "chain_no_designated":
        "the superclass declares this value read-only and offers no designated initialiser to keep "
        "it in, so there is no chain to make",
    "unavailable":
        "the header marks the initialiser unavailable, so a port cannot call it",
    "collection_factory":
        "a factory that answers an array of resolution results is a collection the framework's "
        "system builds, and there is no system here to read the values out of one",
    "class_property":
        "a property of the class's own type on the class is the class's own identity, which the "
        "runtime holds, and there is no storage for it to keep",
    "foreign_class":
        "the type is a class of a framework this package does not carry, and no header of the "
        "port's own SDK declares it, so there is nothing to keep the value in",
    "not_declared":
        "the SDK's own headers do not declare this member, so there is nothing to answer",
    "unanswered":
        "a member of a class of a later group of this same delivery",
}

# The same causes in the short form a @dynamic line in the generated source can carry. CAUSES is a
# sentence for the registry's `reason`; a source comment needs a phrase, and the two are kept
# beside each other so a cause cannot be added to one and not the other.
CAUSE_LABELS = {
    "later_group": "a class of a later group",
    "forward_only_class": "a class the headers only forward declare",
    "class_property": "a property of the class's own type",
    "unanswered": "a class of a later group",
}

# The enumerations whose zero case is the one that says nothing, measured from the host: its own
# framework logs "Success resolution with <Enum>Unknown will be reformed to notRequired." for a
# success carrying that case (observed on the host's own Intents, 2026-09-27, for
# INCarSignalOptions, INTaskStatus, INRadioType, INRelativeReference, INRelativeSetting,
# INTaskPriority, INVisualCodeType, INWorkoutGoalUnitType and INWorkoutLocationType).
NEUTRAL_ENUMERATIONS = {
    "INCallDestinationType", "INCallRecordType", "INCallRecordTypeOptions", "INCarAudioSource",
    "INCarDefroster", "INCarSeat", "INCarSignalOptions", "INDateSearchType",
    "INLocationSearchType", "INMediaAffinityType", "INNoteContentType", "INPhotoAttributeOptions",
    "INRadioType", "INRelativeReference", "INRelativeSetting", "INTaskPriority", "INTaskStatus",
    "INTemporalEventTriggerTypeOptions", "INVisualCodeType", "INWorkoutGoalUnitType",
    "INWorkoutLocationType",
}


def neutral_enumeration(name):
    """The enumerations the host's rule was measured over, kept for the record and for the
    differential's label - the *value* decides, not membership of this list."""
    return name in NEUTRAL_ENUMERATIONS


# A member whose body is a derivation the header describes rather than a store, written here with
# the header's own words for what it builds: a generated body could only put the parameter under
# a name of the generator's making, which is not a member of the class.
EXTRA_METHODS = {
    ("INObjectCollection", "initWithItems:"): [
        "- (instancetype)initWithItems:(NSArray *)items",
        "{",
        "    // The header's own two properties say what a collection of items is: allItems is the",
        "    // items, and sections is them under one section with no title. Collation is not",
        "    // indexed, because the items arrive in the order they were given and nothing here",
        "    // sorts them.",
        "    INObjectSection *section =",
        "        [[INObjectSection alloc] initWithTitle:nil items:items ?: [NSArray array]];",
        "    if ((self = [super init])) {",
        "        _sections = @[section];",
        "        _allItems = [items copy] ?: [NSArray array];",
        "        _usesIndexedCollation = NO;",
        "    }",
        "    return self;",
        "}",
    ],
    # The four singleton accessors. Each of these headers names the accessor and says to use it -
    # "@c Use the @c defaultStore singleton" - so the accessor is the class's whole surface and the
    # one object for the process is what it answers. dispatch_once is the tree's own spelling of
    # one instance for the process: packages/a/apple-backports/Intents/CharonIntents100.m's
    # +[INVocabulary sharedVocabulary] is this body.
    ("INRelevantShortcutStore", "defaultStore"): [
        "+ (INRelevantShortcutStore *)defaultStore",
        "{",
        "    // The header's own note is to use this singleton, so it is one object for the process.",
        "    static INRelevantShortcutStore *shared;",
        "    static dispatch_once_t once;",
        "    dispatch_once(&once, ^{",
        "        shared = [[INRelevantShortcutStore alloc] init];",
        "    });",
        "    return shared;",
        "}",
    ],
    ("INUpcomingMediaManager", "sharedManager"): [
        "+ (INUpcomingMediaManager *)sharedManager",
        "{",
        "    // The header's own note is to use this singleton, so it is one object for the process.",
        "    static INUpcomingMediaManager *shared;",
        "    static dispatch_once_t once;",
        "    dispatch_once(&once, ^{",
        "        shared = [[INUpcomingMediaManager alloc] init];",
        "    });",
        "    return shared;",
        "}",
    ],
    ("INVoiceShortcutCenter", "sharedCenter"): [
        "+ (INVoiceShortcutCenter *)sharedCenter",
        "{",
        "    // The header's own note is to use this singleton, so it is one object for the process.",
        "    static INVoiceShortcutCenter *shared;",
        "    static dispatch_once_t once;",
        "    dispatch_once(&once, ^{",
        "        shared = [[INVoiceShortcutCenter alloc] init];",
        "    });",
        "    return shared;",
        "}",
    ],
    # The three classes of this group whose header marks +new unavailable. NS_UNAVAILABLE is a
    # compile-time attribute and the runtime never sees it, so the class keeps the +new it
    # inherits, and the release answers it: measured on the host's own Intents, all three are
    # answered, all three return an object with no exception, and all three are answered by
    # NSObject's own +new - their metaclass chain declares the selector there and nowhere else
    # (tools/intents/probe-host-absent.sh against registry/Intents/ios12.json, control 100 rows
    # found and 55 answered in the same process). So the answer is NSObject's and not a new one,
    # and it is reached through its IMP for the same reason the -init of each of these three
    # classes is: the header forbids naming the selector.
    ("INShortcut", "new"): [
        "+ (instancetype)new",
        "{",
        "    // The header marks this class's +new unavailable, which the runtime never sees:",
        "    // measured, +[INShortcut new] is answered and returns an object, and what answers",
        "    // it is NSObject's own +new. So the method is defined here and that one is reached",
        "    // through its IMP, because the header forbids naming the selector.",
        "    Class parent = [NSObject class];",
        "    SEL selector = @selector(new);",
        "    IMP forward = parent ? class_getMethodImplementation(parent, selector) : NULL;",
        "    return forward ? ((id (*)(id, SEL))forward)(self, selector) : nil;",
        "}",
    ],
    ("INVoiceShortcut", "new"): [
        "+ (instancetype)new",
        "{",
        "    // The header marks this class's +new unavailable, which the runtime never sees:",
        "    // measured, +[INVoiceShortcut new] is answered and returns an object, and what",
        "    // answers it is NSObject's own +new. So the method is defined here and that one is",
        "    // reached through its IMP, because the header forbids naming the selector.",
        "    Class parent = [NSObject class];",
        "    SEL selector = @selector(new);",
        "    IMP forward = parent ? class_getMethodImplementation(parent, selector) : NULL;",
        "    return forward ? ((id (*)(id, SEL))forward)(self, selector) : nil;",
        "}",
    ],
    ("INVoiceShortcutCenter", "new"): [
        "+ (instancetype)new",
        "{",
        "    // The header marks this class's +new unavailable, which the runtime never sees:",
        "    // measured, +[INVoiceShortcutCenter new] is answered and returns an object, and",
        "    // what answers it is NSObject's own +new. So the method is defined here and that one",
        "    // is reached through its IMP, because the header forbids naming the selector. The",
        "    // header's note is to use +sharedCenter; +new is answered anyway, and this answers",
        "    // it the way the release does.",
        "    Class parent = [NSObject class];",
        "    SEL selector = @selector(new);",
        "    IMP forward = parent ? class_getMethodImplementation(parent, selector) : NULL;",
        "    return forward ? ((id (*)(id, SEL))forward)(self, selector) : nil;",
        "}",
    ],
    ("INFocusStatusCenter", "defaultCenter"): [
        "+ (INFocusStatusCenter *)defaultCenter",
        "{",
        "    // The header's own note is to use this singleton, so it is one object for the process.",
        "    static INFocusStatusCenter *shared;",
        "    static dispatch_once_t once;",
        "    dispatch_once(&once, ^{",
        "        shared = [[INFocusStatusCenter alloc] init];",
        "    });",
        "    return shared;",
        "}",
    ],
    ("INRelevantShortcutStore", "setRelevantShortcuts:completionHandler:"): [
        "- (void)setRelevantShortcuts:(NSArray<INRelevantShortcut *> *)shortcuts",
        "    completionHandler:(void (^ __nullable)(NSError * __nullable error))completionHandler",
        "{",
        "    // The header's own note is that a new set replaces every one provided before, so the",
        "    // whole set is replaced here rather than added to. This release runs no assistant",
        "    // daemon to read the set, so it is kept in the class's own state and the handler is",
        "    // answered with no error, which is what the framework reports for a set it took.",
        "    _relevantShortcuts = [shortcuts copy] ?: [NSArray array];",
        "    if (completionHandler) {",
        "        completionHandler(nil);",
        "    }",
        "}",
    ],
    ("INUpcomingMediaManager", "setSuggestedMediaIntents:"): [
        "- (void)setSuggestedMediaIntents:(NSOrderedSet<INPlayMediaIntent *> *)intents",
        "{",
        "    // The header calls these the intents to suggest. This release runs no assistant daemon",
        "    // to read them, so they are kept in the class's own state in the order they were given.",
        "    _suggestedMediaIntents = [intents copy] ?: [NSOrderedSet orderedSet];",
        "}",
    ],
    ("INUpcomingMediaManager", "setPredictionMode:forType:"): [
        "- (void)setPredictionMode:(INUpcomingMediaPredictionMode)mode",
        "    forType:(INMediaItemType)type",
        "{",
        "    // One mode per media item type, which is what the selector says: it takes the type, so",
        "    // the mode asked about a type is that type's own. Nothing here predicts anything -",
        "    // there is no assistant daemon on this release - so the mode is kept to be read back.",
        "    NSNumber *key = [NSNumber numberWithInteger:(NSInteger)type];",
        "    if (!_predictionModes) {",
        "        _predictionModes = [[NSMutableDictionary alloc] init];",
        "    }",
        "    if (mode == INUpcomingMediaPredictionModeDefault) {",
        "        [_predictionModes removeObjectForKey:key];",
        "    } else {",
        "        [_predictionModes setObject:[NSNumber numberWithInteger:(NSInteger)mode] forKey:key];",
        "    }",
        "}",
    ],
    ("INVoiceShortcutCenter", "setShortcutSuggestions:"): [
        "- (void)setShortcutSuggestions:(NSArray<INShortcut *> *)suggestions",
        "{",
        "    // Suggestions replace the ones before, as the header's discussion says they are shown",
        "    // to the user in the Shortcuts app - which this release has no app for. They are kept",
        "    // in the class's own state in the order they were offered.",
        "    _shortcutSuggestions = [suggestions copy] ?: [NSArray array];",
        "}",
    ],
    ("INVoiceShortcutCenter", "getAllVoiceShortcutsWithCompletion:"): [
        "- (void)getAllVoiceShortcutsWithCompletion:",
        "    (void (^)(NSArray<INVoiceShortcut *> * _Nullable, NSError * _Nullable))completionHandler",
        "{",
        "    // This release runs no assistant daemon and has no Shortcuts app, so no shortcut was",
        "    // ever added to Siri: the answer is an empty array and no error, which is what the",
        "    // framework reports when the app has none. A nil handler is not called.",
        "    if (completionHandler) {",
        "        completionHandler([NSArray array], nil);",
        "    }",
        "}",
    ],
    ("INVoiceShortcutCenter", "getVoiceShortcutWithIdentifier:completion:"): [
        "- (void)getVoiceShortcutWithIdentifier:(NSUUID *)identifier",
        "    completion:(void (^)(INVoiceShortcut * _Nullable, NSError * _Nullable))completionHandler",
        "{",
        "    // The same empty store as getAllVoiceShortcutsWithCompletion:, read by the identifier",
        "    // this release was never given one for: nil and no error. A nil handler is not called.",
        "    if (completionHandler) {",
        "        completionHandler(nil, nil);",
        "    }",
        "}",
    ],
    # INFile: the header says a file holds its data and the name and uniform type identifier it
    # was given, and that data made from a URL memory maps on access - so the URL is kept and the
    # data is read through it rather than cached twice. -init is NS_UNAVAILABLE in the header and
    # the generator emits a body for it anyway (see own_init_unavailable), which is why these two
    # can allocate.
    ("INFile", "fileWithData:filename:typeIdentifier:"): [
        "+ (INFile *)fileWithData:(NSData *)data",
        "    filename:(NSString *)filename",
        "    typeIdentifier:(NSString * __nullable)typeIdentifier",
        "{",
        "    // Data in memory: there is no URL, and the header's own fileURL property answers nil.",
        "    INFile *file = [[INFile alloc] init];",
        "    file->_data = [data copy];",
        "    file->_filename = [filename copy];",
        "    file->_typeIdentifier = [typeIdentifier copy];",
        "    return file;",
        "}",
    ],
    ("INFile", "fileWithFileURL:filename:typeIdentifier:"): [
        "+ (INFile *)fileWithFileURL:(NSURL *)fileURL",
        "    filename:(NSString * __nullable)filename",
        "    typeIdentifier:(NSString * __nullable)typeIdentifier",
        "{",
        "    // A file on disk: the URL is kept so the data property memory maps it on access, and a",
        "    // filename the caller gave is kept as it is - the header makes it nullable here, so no",
        "    // name is invented for a file whose caller offered none.",
        "    INFile *file = [[INFile alloc] init];",
        "    file->_fileURL = [fileURL copy];",
        "    file->_filename = [filename copy];",
        "    file->_typeIdentifier = [typeIdentifier copy];",
        "    return file;",
        "}",
    ],
    # The accessors the two factories above fill. They are readonly in the header, so nothing
    # synthesises them: with the fields in EXTRA_IVARS a body reads them directly.
    ("INFile", "data"): [
        "- (NSData *)data",
        "{",
        "    // A file made from a URL memory maps its contents on access, as the header says, so the",
        "    // bytes are read where they are rather than copied into a second copy of the file.",
        "    if (!_data && _fileURL) {",
        "        _data = [NSData dataWithContentsOfURL:_fileURL];",
        "    }",
        "    return _data;",
        "}",
    ],
    ("INFile", "filename"): [
        "- (NSString *)filename",
        "{",
        "    return _filename;",
        "}",
    ],
    ("INFile", "typeIdentifier"): [
        "- (NSString *)typeIdentifier",
        "{",
        "    return _typeIdentifier;",
        "}",
    ],
    ("INFile", "fileURL"): [
        "- (NSURL *)fileURL",
        "{",
        "    // A file made from data was never on disk, and the header's property is nullable.",
        "    return _fileURL;",
        "}",
    ],
    ("INSendMessageAttachment", "attachmentWithAudioMessageFile:"): [
        "+ (INSendMessageAttachment *)attachmentWithAudioMessageFile:(INFile *)audioMessageFile",
        "{",
        "    // The header names this the audio message file of the attachment, and it is the class's",
        "    // only property, so the attachment is that file and nothing else.",
        "    INSendMessageAttachment *attachment = [[INSendMessageAttachment alloc] init];",
        "    attachment->_audioMessageFile = [audioMessageFile copy];",
        "    return attachment;",
        "}",
    ],
    ("INSendMessageAttachment", "audioMessageFile"): [
        "- (INFile *)audioMessageFile",
        "{",
        "    return _audioMessageFile;",
        "}",
    ],
    ("INMediaDestination", "libraryDestination"): [
        "+ (instancetype)libraryDestination",
        "{",
        "    // The header's own two properties say what this is: a destination whose type is the",
        "    // library's and whose playlist name is none, which is the difference between it and",
        "    // +playlistDestinationWithName:.",
        "    INMediaDestination *destination = [[INMediaDestination alloc] init];",
        "    destination->_mediaDestinationType = INMediaDestinationTypeLibrary;",
        "    return destination;",
        "}",
    ],
    ("INMediaDestination", "playlistDestinationWithName:"): [
        "+ (instancetype)playlistDestinationWithName:(NSString *)playlistName",
        "{",
        "    // The same destination type as +libraryDestination with the name kept, which is the one",
        "    // difference the header's two properties can express.",
        "    INMediaDestination *destination = [[INMediaDestination alloc] init];",
        "    destination->_mediaDestinationType = INMediaDestinationTypePlaylist;",
        "    destination->_playlistName = [playlistName copy];",
        "    return destination;",
        "}",
    ],
    ("INMediaDestination", "mediaDestinationType"): [
        "- (INMediaDestinationType)mediaDestinationType",
        "{",
        "    return _mediaDestinationType;",
        "}",
    ],
    ("INMediaDestination", "playlistName"): [
        "- (NSString * __nullable)playlistName",
        "{",
        "    return _playlistName;",
        "}",
    ],
    ("INUserContext", "becomeCurrent"): [
        "- (void)becomeCurrent",
        "{",
        "    // The header marks this unavailable in an extension and calls it nothing else: it tells",
        "    // the system that this context is the current one, and there is no system on this",
        "    // release to tell - no assistant daemon reads a user context - so there is nothing to do",
        "    // and nothing to record. Saying so is the whole of the answer; inventing a current",
        "    // context that nothing reads would be a value that looks filled and is not.",
        "}",
    ],
    ("INAddTasksTargetTaskListResolutionResult",
     "confirmationRequiredWithTaskListToConfirm:forReason:"): [
        "+ (instancetype)confirmationRequiredWithTaskListToConfirm:(INTaskList * __nullable)taskListToConfirm",
        "    forReason:(INAddTasksTargetTaskListConfirmationReason)reason",
        "{",
        "    // The same answer the typed task-list factories build, with the task list to confirm as",
        "    // the value to confirm. The reason is one case of its own enumeration and the class",
        "    // exposes no reader for it, so it is not stored - see CharonIntentsResolution.h's",
        "    // charon_unsupportedReason for why a swallowed reason is a different answer.",
        "    return [self charon_resolutionWithStatus:CharonIntentsResolutionConfirmationRequired",
        "                                resolvedValue:nil",
        "                          valuesToDisambiguate:nil",
        "                                 valueToConfirm:taskListToConfirm];",
        "}",
    ],
    ("INFocusStatusCenter", "requestAuthorizationWithCompletionHandler:"): [
        "- (void)requestAuthorizationWithCompletionHandler:",
        "    (void (^ __nullable)(INFocusStatusAuthorizationStatus status))completionHandler",
        "{",
        "    // The same answer packages/a/apple-backports/Intents/CharonIntents100.m gives for",
        "    // +[INPreferences requestSiriAuthorization:]: this release has no Focus setting to ask",
        "    // about and no prompt to show, so it answers the handler with Restricted rather than",
        "    // leaving the handler waiting for a system that will never call it. A nil handler is not",
        "    // called.",
        "    if (completionHandler) {",
        "        completionHandler(INFocusStatusAuthorizationStatusRestricted);",
        "    }",
        "}",
    ],

    ("INCar", "maximumPowerForChargingConnectorType:"): [
        "- (NSMeasurement<NSUnitPower *> *)maximumPowerForChargingConnectorType:",
        "    (INCarChargingConnectorType)chargingConnectorType",
        "{",
        "    // The header's own two methods are a pair: this one reads what the setter wrote for",
        "    // that connector type, and answers nil for a type nothing was set for. NSMeasurement",
        "    // and NSUnitPower are Foundation's own and are carried by this delivery (minimum 6.0),",
        "    // so the value has somewhere real to be kept.",
        "    NSNumber *key = [NSNumber numberWithInteger:(NSInteger)chargingConnectorType];",
        "    return [_maximumPowerByConnectorType objectForKey:key];",
        "}",
    ],
    ("INCar", "setMaximumPower:forChargingConnectorType:"): [
        "- (void)setMaximumPower:(NSMeasurement<NSUnitPower *> *)power",
        "    forChargingConnectorType:(INCarChargingConnectorType)chargingConnectorType",
        "{",
        "    // One maximum per connector type, which is what the selector says. A nil power removes",
        "    // the entry rather than storing a nil, so the reader's nil means \"set to nothing\".",
        "    if (!_maximumPowerByConnectorType) {",
        "        _maximumPowerByConnectorType = [[NSMutableDictionary alloc] init];",
        "    }",
        "    NSNumber *key = [NSNumber numberWithInteger:(NSInteger)chargingConnectorType];",
        "    if (power) {",
        "        [_maximumPowerByConnectorType setObject:power forKey:key];",
        "    } else {",
        "        [_maximumPowerByConnectorType removeObjectForKey:key];",
        "    }",
        "}",
    ],
    # The bare -init of a class whose header declares it AVAILABLE, which the loop above never
    # reaches: it only visits selectors spelled initWith...:, so an initialiser with no argument
    # fell through to the group's reason and its row was written as absent with the reason for a
    # header that marks a member unavailable. This header does not - INListCarsIntent.h:17 reads
    # `- (instancetype)init NS_DESIGNATED_INITIALIZER;` - and the release answers it: measured on
    # the host's own Intents, -[INListCarsIntent init] is declared by INListCarsIntent itself and
    # [[INListCarsIntent alloc] init] returns an object (tools/intents/probe-host-absent.sh against
    # registry/Intents/ios16.json).
    ("INListCarsIntent", "init"): [
        "- (instancetype)init",
        "{",
        "    // The header's own declaration is this class's designated initialiser and the class",
        "    // declares no property, so the whole of it is the superclass's own -init. INIntent",
        "    // declares none of its own, so this reaches NSObject's, which nothing in the chain",
        "    // marks unavailable - the selector can be spelled here, and no IMP is needed.",
        "    return [super init];",
        "}",
    ],
    # The second class of the same kind, and the reason the first entry is here at all rather than a
    # rule in the loop above. INGetRideStatusIntent.h:17 reads `- (instancetype)init
    # NS_DESIGNATED_INITIALIZER;` - declared, not marked unavailable - so its row was written as
    # absent with "the header marks the initialiser unavailable, so a port cannot call it", which is
    # false of this header. Its superclass is INIntent, which declares no -init of its own, so the
    # answer is the same chain and the body is the same body.
    ("INGetRideStatusIntent", "init"): [
        "- (instancetype)init",
        "{",
        "    // INGetRideStatusIntent.h:17 declares this the class's designated initialiser and marks",
        "    // nothing unavailable, so it is part of the class's API and not a marker on the way to",
        "    // the superclass's. The class declares no property, so the whole of it is INIntent's",
        "    // own -init, and INIntent declares none, so this reaches NSObject's - which nothing in",
        "    // the chain marks unavailable, so the selector can be spelled here and no IMP is needed.",
        "    return [super init];",
        "}",
    ],
    # INMediaDestination's two properties are readonly and its -init is NS_UNAVAILABLE, so the two
    # class methods below are the only way to make one and they fill these.
    "INMediaDestination": [
        "    INMediaDestinationType _mediaDestinationType;  // mediaDestinationType",
        "    NSString * _playlistName;  // playlistName",
    ],
}

# The state a hand-written body keeps that the class's own headers declare no property for, so it
# has no @synthesize and no coding or copying entry. Each field is named after the method that
# writes it, and the body says what it owns.

# The state a hand-written body keeps that the class's own headers declare no property for, so it
# has no @synthesize and no coding or copying entry. Each field is named after the method that
# writes it, and the body says what it owns.
EXTRA_IVARS = {
    "INRelevantShortcutStore": [
        "    NSArray * _relevantShortcuts;  // setRelevantShortcuts:completionHandler:",
    ],
    "INUpcomingMediaManager": [
        "    NSOrderedSet * _suggestedMediaIntents;  // setSuggestedMediaIntents:",
        "    NSMutableDictionary * _predictionModes;  // setPredictionMode:forType:, by media item type",
    ],
    "INVoiceShortcutCenter": [
        "    NSArray * _shortcutSuggestions;  // setShortcutSuggestions:",
    ],
    # INFile and INSendMessageAttachment are NOT here: their properties are readonly but they are
    # still the class's own, so the generator synthesises the ivar and the accessor for each, and a
    # second declaration of the same field is "duplicate member" at compile time. Their two
    # factories only fill what is already there. Listing them cost a red gate: IN16_0.m:1584-1588
    # and :3978, six errors, all of them this.
    # The header's two charging-power methods are a read/write pair keyed by connector type, so
    # the field is a dictionary and neither is a property the header declares.
    "INCar": [
        "    NSMutableDictionary * _maximumPowerByConnectorType;  // maximumPowerForChargingConnectorType:",
    ],
}


# Charon's OWN readers for the stores the headers ask to be written. They are not in
# EXTRA_METHODS because EXTRA_METHODS is consulted while walking the header's OWN declared
# methods, and a reader no header declares is never visited there: the four of these were
# written to EXTRA_METHODS and silently emitted nowhere. They are emitted from here instead,
# after the declared members, and only for a class this file generates.
CHARON_READERS = {
    # A reader for each store the headers ask to be written. A setter whose value nothing can read
    # back is a field that only grows, and a port that offered a shortcut has no way to see that it
    # did - which is the state this delivery is meant to keep. The name is Charon's own, so it
    # collides with nothing Apple has and it is hidden at the link, and each class row's `effect`
    # names it the way INVocabulary's names charon_vocabularyStringsOfType:.
    ("INRelevantShortcutStore", "charon_relevantShortcuts"): [
        "- (NSArray *)charon_relevantShortcuts",
        "{",
        "    // What setRelevantShortcuts:completionHandler: was last given, in the order it was",
        "    // given, or an empty array before anything was. Where a port reads back what it",
        "    // offered: on a release with Siri the system is the reader instead.",
        "    return _relevantShortcuts ?: [NSArray array];",
        "}",
    ],
    ("INUpcomingMediaManager", "charon_suggestedMediaIntents"): [
        "- (NSOrderedSet *)charon_suggestedMediaIntents",
        "{",
        "    // What setSuggestedMediaIntents: was last given, in the order it was given, or an empty",
        "    // ordered set before anything was.",
        "    return _suggestedMediaIntents ?: [NSOrderedSet orderedSet];",
        "}",
    ],
    ("INVoiceShortcutCenter", "charon_shortcutSuggestions"): [
        "- (NSArray *)charon_shortcutSuggestions",
        "{",
        "    // What setShortcutSuggestions: was last given, in the order it was given, or an empty",
        "    // array before anything was.",
        "    return _shortcutSuggestions ?: [NSArray array];",
        "}",
    ],
    ("INUpcomingMediaManager", "charon_predictionModeForType:"): [
        "- (INUpcomingMediaPredictionMode)charon_predictionModeForType:(INMediaItemType)type",
        "{",
        "    // What setPredictionMode:forType: recorded for that media item type, and the enumeration",
        "    // own zero case - Default - for a type nothing was set for, which is what a dictionary",
        "    // with no entry for it answers.",
        "    NSNumber *mode = [_predictionModes objectForKey:[NSNumber numberWithInteger:(NSInteger)type]];",
        "    return mode ? (INUpcomingMediaPredictionMode)[mode integerValue] : INUpcomingMediaPredictionModeDefault;",
        "}",
    ],
}


def has_attr(node, kind):
    """Whether a declaration carries an attribute: Unavailable, Designated, Optional, ..."""
    return any(child.get("kind") == kind for child in node.get("inner") or [])


def type_of(member):
    return (member.get("type") or {}).get("qualType") or "id"


def returns_of(method):
    return (method.get("returnType") or {}).get("qualType") or "id"


def parameters_of(method):
    return [(type_of(c), c.get("name") or "value")
            for c in method.get("inner") or [] if c.get("kind") == "ParmVarDecl"]


def setter_name(name):
    return "set" + name[0].upper() + name[1:] + ":"


def is_copy(member, kind):
    if member.get("copy"):
        return True
    if member.get("retain") or member.get("strong"):
        return False
    return bool(COPIED.match(base_type(kind)))


class Interface:
    """One @interface as the compiler sees it, and everything it declares."""

    def __init__(self, node):
        self.node = node
        self.name = node.get("name")
        self.file = (node.get("loc") or {}).get("file") or ""
        self.superclass = (node.get("super") or {}).get("name")
        self.protocols = [p.get("name") for p in node.get("protocols") or [] if p.get("name")]
        self.properties = [c for c in node.get("inner") or [] if c.get("kind") == "ObjCPropertyDecl"]
        self.methods = [c for c in node.get("inner") or [] if c.get("kind") == "ObjCMethodDecl"]

    def declared(self, name):
        return name in {p.get("name") for p in self.properties}

    def method(self, selector):
        for candidate in self.methods:
            if candidate.get("name") == selector:
                return candidate
        return None

    def spelled_selector(self, method):
        parts, index = [], 0
        parameters = parameters_of(method)
        for part in (method.get("name") or "").split(":")[:-1]:
            kind, parameter = parameters[index] if index < len(parameters) else ("id", "value")
            parts.append("%s:(%s)%s" % (part, spelled(kind), parameter))
            index += 1
        return " ".join(parts)


def conformed_by(interface, interfaces):
    """The protocols a class really conforms to, its own and its superclasses'.

    A subclass of INIntent writes `<NSCopying, NSSecureCoding>` nowhere: the conformance is
    inherited, so reading the class's own protocol list alone would have every subclass of a
    conforming base left without the coding and copying the header promises for it.
    """
    found, seen, name = [], set(), interface
    while name and name not in seen:
        seen.add(name)
        for protocol in name.protocols:
            if protocol not in found:
                found.append(protocol)
        name = interfaces.get(name.superclass)
    return found


SYNTHESISED = re.compile(r"^\s*@synthesize ([A-Za-z_][\w_]*)\s*=")
DYNAMIC = re.compile(r"^\s*@dynamic ([A-Za-z_][\w_]*)\s*;")
DEFINITION = re.compile(r"^\s*([-+]) \(([^)]*)\)(.*)$")
SELECTOR_PART = re.compile(r"([A-Za-z_][\w_]*):\(")


def definitions(lines):
    """The method definitions of a block, each one line, whether or not it spans several.

    A definition the SDK's own header is long for is written over several lines
    (-initWithType:name:identificationHint:icon:), and a reader that took one line at a time would
    see only its first keyword and report a selector no caller ever writes.
    """
    joined, current = [], None
    for line in lines:
        if current is not None:
            current += " " + line.strip()
            if line.rstrip().endswith("{") or line.rstrip().endswith(";"):
                joined.append(current)
                current = None
            continue
        if DEFINITION.match(line) and not line.rstrip().endswith("{"):
            current = line.strip()
    if current is not None:
        joined.append(current)
    return joined


def answer_of(lines, name, causes=None):
    """What the emitted @implementation of one class carries, read back out of the text.

    The registry is written from this, not from the declarations the generator read, so an entry
    can never say a member is implemented when the file does not implement it.
    """
    properties, dynamic, methods = set(), set(), set()
    for line in lines + definitions(lines):
        found = SYNTHESISED.match(line)
        if found:
            properties.add(found.group(1))
            continue
        found = DYNAMIC.match(line)
        if found:
            dynamic.add(found.group(1))
            continue
        found = DEFINITION.match(line)
        if found:
            spelled = found.group(3)
            selector = "".join(part.group(1) + ":" for part in SELECTOR_PART.finditer(spelled)) \
                or spelled.strip()
            if selector:
                methods.add("%s[%s %s]" % (found.group(1), name, selector))
    return {
        "properties": sorted(properties),
        "dynamic": sorted(dynamic),
        "methods": sorted(methods),
        "causes": causes or {},
    }


def collect(path):
    """Every real @interface, @protocol and typedef name in a dump.

    A category on a class is part of that class's surface, not a class of its own: INPerson's
    aliases and suggestionType are declared in `INPerson (INInteraction)` and the corpus counts
    them as INPerson's properties, so they are folded into the class here. A category carries no
    class symbol of its own, so folding it in does not put two names in the same object file.
    """
    interfaces, protocols, typedefs, categories, forward = {}, {}, set(), {}, set()
    for node in top_level(path):
        kind, name = node.get("kind"), node.get("name")
        if not name:
            continue
        if kind in ("TypedefDecl", "EnumDecl"):
            typedefs.add(name)
        elif kind == "ObjCInterfaceDecl":
            if not (node.get("inner") or []):
                forward.add(name)   # an @class declaration: no definition of it anywhere
            elif name not in interfaces or len(node["inner"]) > len(interfaces[name].node["inner"]):
                interfaces[name] = Interface(node)
        elif kind == "ObjCProtocolDecl":
            if name not in protocols or len(node.get("inner") or []) > len(protocols[name].get("inner") or []):
                protocols[name] = node
        elif kind == "ObjCCategoryDecl":
            owner = (node.get("interface") or {}).get("name")
            if owner:
                categories.setdefault(owner, []).append(node)
    for owner, found in categories.items():
        interface = interfaces.get(owner)
        if not interface:
            continue
        for node in found:
            for member in node.get("inner") or []:
                if member.get("kind") == "ObjCPropertyDecl":
                    # A property a category declares cannot be synthesised in the class's own
                    # @implementation ("property declared in category cannot be implemented in
                    # class implementation"), so it is marked and given a category of its own.
                    member = dict(member)
                    member["category"] = node.get("name")
                    interface.properties.append(member)
                elif member.get("kind") == "ObjCMethodDecl":
                    interface.methods.append(member)
    return interfaces, protocols, typedefs, forward


def property_names(members):
    """The names a property answers to: its own, and the getter the header gives it.

    INPerson's contactSuggestion is declared `getter=isContactSuggestion`, and the initialiser
    that sets it spells the parameter isContactSuggestion:, so matching only the property's own
    name would leave that value with nowhere to go.
    """
    found = {}
    for member in members:
        name = member.get("name")
        if not name or member.get("class"):
            continue
        found[name] = name
        getter = (member.get("getter") or {}).get("name")
        if getter and getter != name:
            found[getter] = name
    return found


def required_properties(protocol):
    """The properties a protocol requires, so a conformer really conforms."""
    return {member["name"]: member for member in protocol.get("inner") or []
            if member.get("kind") == "ObjCPropertyDecl" and member.get("name")
            and not has_attr(member, "OptionalAttr")}


# The frameworks the release itself carries, whose classes a backport may use. EventKit is not one
# of them: libIntentsBackports does not link it, so a type of its name that the headers only
# forward declare is a class this package does not carry.
SYSTEM = re.compile(r"^(NS|CL|CF|CG|UI|WK|CA|AV|SK|MK|QL|AL|SCN|PH|MP)[A-Z]")

def deferred_type(qual, known, carried, forward=()):
    """The class a type names that this delivery does not carry.

    Two ways a type names a class that is not here: an Intents class of a group this delivery
    does not carry, and a class the SDK's headers only @class forward declare and no header of
    the port's own SDK defines - INDateComponentsRange's EKRecurrenceRule, which is EventKit's
    and which the Intents header of iPhoneOS 16.4 names where iPhoneOS 26.2 names an
    INRecurrenceRule. A body that stored one would not compile against a forward declaration.
    """
    name = base_type(qual)
    if name in known and name not in carried:
        return name
    if name in forward and name not in carried and not SYSTEM.match(name):
        return name
    return None


def designated(interface, interfaces):
    """The initialiser the header marks as the class's own, and its parameters.

    A subclass's own designated initialiser is not what a subclass chains to: it chains to the
    one its *superclass* declares, which is where the state the superclass keeps is set.
    """
    seen, name = set(), interfaces.get(interface.superclass)
    while name and name.name not in seen:
        seen.add(name.name)
        for method in name.methods:
            if has_attr(method, "ObjCDesignatedInitializerAttr") and ":" in (method.get("name") or ""):
                return method
        name = interfaces.get(name.superclass)
    return None


def ancestor_property(interface, property, interfaces):
    """Where a property of a superclass is declared, and whether it can be written."""
    seen, name = set(), interfaces.get(interface.superclass)
    while name and name.name not in seen:
        seen.add(name.name)
        for member in name.properties:
            if member.get("name") == property:
                return member
        name = interfaces.get(name.superclass)
    return None


def inherited_readonly(interface, interfaces, spellings):
    """The read-only values of a superclass that this class's own initialisers name.

    A subclass initialiser that takes a value a superclass declares read-only has nowhere to put
    it: the superclass offers no designated initialiser that would take it (INReservation and
    INPerson declare none at all, so the chain ends at NSObject's -initWithCoder: and nothing in
    the SDK says where a coder would come from), and the property cannot be written from here.
    So the class keeps its own copy, in its own ivar, and answers the getter with it. A caller
    holding a superclass-typed pointer and sending the getter gets the subclass's answer, because
    the getter is the subclass's own - which is what a caller would see on the system, where the
    object is one object and the value is one value.
    """
    found = {}
    for method in interface.methods:
        selector = method.get("name") or ""
        if method.get("instance") is False or not selector.startswith("init") or ":" not in selector:
            continue
        for kind, parameter in parameters_of(method):
            name = spellings.get(parameter, parameter)
            member = ancestor_property(interface, name, interfaces)
            if member is None or not member.get("readonly") or member.get("category"):
                continue
            if ancestor_property_owner(interface, name, interfaces) == interface.name:
                continue
            found.setdefault(name, (type_of(member), member, member.get("name")))
    return found


def ancestor_property_owner(interface, property, interfaces):
    """Which class of the chain declares the property."""
    seen, name = set(), interfaces.get(interface.superclass)
    while name and name.name not in seen:
        seen.add(name.name)
        for member in name.properties:
            if member.get("name") == property:
                return name.name
        name = interfaces.get(name.superclass)
    return None


def zero_of(qual):
    kind = spelled(qual)
    if kind.rstrip().endswith("*") or kind == "id" or kind == "instancetype":
        return "nil"
    if kind == "BOOL":
        return "NO"
    return "0"


def initialiser(interface, method, states, spellings, interfaces):
    """The body of an initialiser: every parameter kept, in the state the class really has.

    A parameter that names a property of this class goes in that class's own ivar. One that
    names a writable property of a superclass goes through its setter, after the class's own
    state is in place. One that names a *read-only* property of a superclass - INRestaurantGuest's
    nameComponents, which is INPerson's - can only be kept by the superclass's own designated
    initialiser, so that is what is called, with the values this initialiser has and nil or zero
    for the arguments it does not: a subclass initialiser that does not offer them has no values
    for them, and that is what the object then holds.

    A parameter that names nothing the class or a superclass declares is looked up in
    PARAMETER_PROPERTIES, and if it has no line there the generator stops: a value silently not
    kept is the failure this whole package exists to avoid.
    """
    selector = method.get("name") or ""
    lines = ["- (instancetype)%s" % interface.spelled_selector(method), "{"]

    given, after, adopt, chained = {}, [], [], False
    for kind, parameter in parameters_of(method):
        # A parameter that is itself a resolution result is the whole state of this one: the class
        # answers what the result it was given answers, which is what a payee or a currency
        # amount that may be unsupported for a reason is asking for.
        if resolution_result(base_type(kind), interfaces):
            adopt.append(parameter)
            continue
        name = spellings.get(parameter, parameter)
        given[name] = (kind, parameter)
        if ("_" + name) in states:
            continue
        member = ancestor_property(interface, name, interfaces)
        if member is None:
            named = PARAMETER_PROPERTIES.get((interface.name, selector, parameter)) or \
                PARAMETER_PROPERTIES.get((interface.name, None, parameter)) or []
            if not named:
                raise SystemExit("%s: the parameter %s of %s names no property of the class or of"
                                 " a superclass, and PARAMETER_PROPERTIES says nowhere it goes, so"
                                 " this generator stops rather than drop it"
                                 % (interface.name, parameter, selector))
            for property_name in named:
                if ("_" + property_name) not in states:
                    raise SystemExit("%s: PARAMETER_PROPERTIES sends the parameter %s of %s to %s,"
                                     " which is not a property of the class"
                                     % (interface.name, parameter, selector, property_name))
                given.setdefault(property_name, (kind, parameter))
            continue
        if not member.get("readonly"):
            after.append((name, kind, parameter))
            continue
        chained = True

    if chained:
        parent = designated(interface, interfaces)
        if not parent:
            # The value is the superclass's, it is read-only, and the superclass offers no
            # initialiser to put it in - INReservation and INPerson declare none, so the chain
            # has nothing to call.
            return None
        # A parameter the header does not mark nullable cannot be handed a nil, and nothing in the
        # header says where the value would come from: the port refuses to chain rather than make
        # a call the SDK forbids. The facts file does not claim Apple does the same.
        for kind, parameter in parameters_of(parent):
            if spelled(kind).rstrip().endswith("*") and not _optional(parameters_of(parent), parameter):
                return None
        pieces = []
        keywords = (parent.get("name") or "").split(":")[:-1]
        for index, (kind, parameter) in enumerate(parameters_of(parent)):
            supplied = given.get(parameter)
            # A keyword is not a parameter name: INPriceRange's second keyword is andPrice for
            # a parameter called secondPrice, and a call has to spell the keyword.
            pieces.append("%s:%s" % (keywords[index] if index < len(keywords) else parameter,
                                     supplied[1] if supplied else zero_of(kind)))
        lines.append("    if ((self = [super %s])) {" % " ".join(pieces))
    elif own_init_unavailable(interface, interfaces):
        lines.append("    // The header marks this class's -init unavailable, so the superclass's own")
        lines.append("    // -init is called through CharonCoding.h's one definition of it.")
        lines.append("    if ((self = charon_intents_super_init(self, [%s class]))) {"
                     % interface.superclass)
    else:
        lines.append("    if ((self = [super init])) {")

    for name, (kind, parameter) in sorted(given.items()):
        if ("_" + name) not in states:
            continue
        copied = spelled(kind).rstrip().endswith("*")
        lines.append("        _%s = %s;" % (name, "[%s copy]" % parameter if copied else parameter))
    # What the class takes over from the result it was given is taken after this class's own
    # state is in place, so the inner one's answer is the answer of the object.
    for parameter in adopt:
        lines.append("        [self charon_adoptResolutionOf:%s];" % parameter)
    lines += ["    }"]
    for name, kind, parameter in after:
        copied = spelled(kind).rstrip().endswith("*")
        lines.append("    self.%s = %s;" % (name, "[%s copy]" % parameter if copied else parameter))
    lines += ["    return self;", "}"]
    return lines


def own_init_blocked_here(interface, interfaces):
    """Whether the -init a bare -init would chain to is the marked one, and not this class's own.

    own_init_unavailable walks the whole chain, which is the right question for an initialiser
    WITH arguments: such an initialiser stores its arguments in this class and then has to reach a
    superclass -init, and the whole chain is what decides whether that call may be spelled.  A bare
    -init stores nothing, so the question is narrower: the selector it forwards to is the nearest
    implementation in the chain, and only the one it would actually reach matters.
    """
    seen, name = set(), interface
    while name is not None and name.name not in seen:
        seen.add(name.name)
        declared = name.method("init")
        if declared is not None and has_attr(declared, "UnavailableAttr"):
            return name.name != interface.name or declared.get("params") == []
        name = interfaces.get(name.superclass)
    return False


def own_init_unavailable(interface, interfaces):
    """Whether the -init a [super init] would reach is marked unavailable in the SDK's header.

    The whole chain is walked, not the class and its direct superclass: a resolution result three
    levels up the chain is what declares it, and a [super init] one level below that is refused
    for the same reason.
    """
    seen, name = set(), interface
    while name is not None and name.name not in seen:
        seen.add(name.name)
        declared = name.method("init")
        if declared is not None and has_attr(declared, "UnavailableAttr"):
            return True
        name = interfaces.get(name.superclass)
    return False


def _optional(parameters, name):
    """Whether a parameter's declaration marks it nullable."""
    for kind, parameter in parameters:
        if parameter == name:
            return False
    return True


def resolution_result(name, interfaces):
    """Whether a class name is a resolution result, by the superclass chain the SDK gives it."""
    seen = set()
    while name and name not in seen:
        if name == RESOLUTION_BASE:
            return True
        seen.add(name)
        found = interfaces.get(name)
        name = found.superclass if found else None
    return False


def render(interface, protocols, carried, intents, interfaces, forward=()):
    """The @implementation of one generated class, and what it answers of the class's surface.

    The second value is what the registry is written from: the members with a body, the members
    left dynamic because their type is a class of a later group, and the initialisers left out
    for the same reason. Nothing here is claimed that the emitted code does not carry.
    """
    out, report = implementation(interface, protocols, carried, intents, interfaces, forward)
    return out, report or answer_of(out, interface.name, causes)


def implementation(interface, protocols, carried, intents, interfaces, forward=()):
    resolution = resolution_result(interface.superclass, interfaces)
    conformed = conformed_by(interface, interfaces)
    # A CLASS PROPERTY is dropped here, and it used to be dropped silently: the filter took
    # `not p.get("class")` and the property reached neither `stored`, nor `dynamic`, nor `skipped`,
    # so no cause was recorded for it and gen-registry.py fell back to the group's blanket reason.
    # That made a member whose class this delivery carries read "a class of a later group of this
    # same delivery", which is the false claim this generator's own history is about. It is the
    # eight rows INRelevantShortcutStore.defaultStore, INUpcomingMediaManager.sharedManager,
    # INVoiceShortcutCenter.sharedCenter and INFocusStatusCenter.defaultCenter came to have.
    #
    # They are the members the class_property cause already names - a singleton of the class's own
    # type is the class's own identity, which the runtime holds - so they are recorded as dynamic
    # under that cause rather than filtered away, and the registry says the cause instead of the
    # group. A class property is still not answered: the body belongs to the class, and one that
    # returns a fresh instance each call would not be the singleton the header's own comment asks
    # for. That is a separate change and it is not this one.
    class_properties = {p.get("name"): p for p in interface.properties
                        if p.get("name") and p.get("class")}
    own = {p.get("name"): p for p in interface.properties
           if p.get("name") and not p.get("class")}

    # clang dumps a property's accessors as declarations of their own, so every method in an
    # @interface is a declaration: the ones that are a property's getter or setter are never
    # given a body here, and the property is synthesised instead.
    accessors = set()
    for method in interface.methods:
        selector = method.get("name") or ""
        if selector in own and not parameters_of(method):
            accessors.add(selector)
        else:
            match = re.match(r"^set(%a[%w_]*):$", selector)
            if match and setter_name(match.group(1)) in own and len(parameters_of(method)) == 1:
                accessors.add(selector)

    stored, synthesised, dynamic, setters, skipped, members = [], [], [], [], [], []
    causes_by_name = {}
    dynamic_causes = {}
    for name, member in sorted(class_properties.items()):
        # A class property whose accessor EXTRA_METHODS writes a body for is ANSWERED by that body:
        # the four singleton accessors are the four, and each is the class's whole surface. One that
        # has no body stays dynamic under the class_property cause, which is what the filter used
        # to do to all of them silently.
        if not (interface.name, name) in EXTRA_METHODS:
            causes_by_name[name] = "class_property"
            dynamic.append((name, member.get("category"), "class_property"))
    for name, member in sorted(own.items()):
        kind = type_of(member)
        if base_type(kind) == interface.name:
            # A property of the class's own type on the class itself: the runtime already holds
            # the class, so there is no storage for an ivar to keep it in, and answering it with
            # one would be a value nothing had put there.
            causes_by_name[name] = "class_property"
            dynamic.append((name, member.get("category"), "class_property"))
            continue
        withheld = deferred_type(kind, intents, carried, forward)
        if withheld:
            cause = "forward_only_class" if (withheld in forward and not SYSTEM.match(withheld)) \
                    else "later_group"
            dynamic_causes[name] = cause
            causes_by_name[name] = cause
            dynamic.append((name, member.get("category"), cause))
            continue
        stored.append(("_" + name, spelled(kind), name))
        members.append((name, spelled(kind), member))
        if not member.get("category"):
            synthesised.append("    @synthesize %s = _%s;" % (name, name))
        if not member.get("readonly") and setter_name(name) not in accessors:
            setters.append((name, kind, member))

    # The read-only values of a superclass that this class's own initialisers take.  The
    # superclass offers no initialiser that could hold one - INReservation and INPerson declare
    # no designated initialiser at all, so the chain ends at NSObject's -initWithCoder: and
    # nothing in the SDK says where a coder would come from - and the property cannot be written
    # from here.  So the class keeps a copy in its own ivar, the initialiser stores the value it
    # was given in it, and the getter below answers with it.  A caller holding a superclass-typed
    # pointer and sending the getter gets this class's copy, because the getter is this class's
    # own: one object, one value, which is what a caller sees on the system.
    spellings = property_names(interface.properties)
    kept = {}
    for name, (kind, member, _) in sorted(inherited_readonly(interface, interfaces, spellings).items()):
        if name in own or ("_" + name) in {ivar for ivar, _, _ in stored}:
            continue
        kept[name] = kind
        stored.append(("_" + name, spelled(kind), name))

    inherited = []
    for protocol_name in conformed:
        protocol = protocols.get(protocol_name)
        # NSObject's own properties are the root superclass's and are not this class's to
        # synthesise: doing it would replace description, hash and the rest with ivars.
        if not protocol or protocol_name == "NSObject":
            continue
        for name, member in sorted(required_properties(protocol).items()):
            if member.get("class") or name in own or name in accessors or \
                    deferred_type(type_of(member), intents, carried, forward):
                continue
            kind = type_of(member)
            stored.append(("_" + name, spelled(kind), name))
            synthesised.append("    @synthesize %s = _%s;" % (name, name))
            inherited.append((name, kind, member))
            setters.append((name, kind, member))

    # A property a category of the class declares is carried by a category of Charon's own,
    # because clang will not let a class implementation synthesise one.
    by_category = {}
    for name, kind, member in members:
        if member.get("category"):
            by_category.setdefault(member["category"], []).append((name, kind, member))
    flat = [(name, kind) for name, kind, member in members if not member.get("category")]

    # Every ivar of the class, the ones a category declared included, is in one class extension
    # in this file, so the class's own initialisers can reach all of them and a category
    # implementation has a place to synthesise the properties a category declared.
    out = []
    # State a hand-written body keeps that the class's own headers declare no property for. The
    # extension above carries one ivar per declared property, so a body that stores a value the
    # header has no property for - the shortcuts a store was given, the suggestions a center was
    # offered, the prediction mode of one media item type - has nowhere to put it without this.
    extra = EXTRA_IVARS.get(interface.name)
    if stored or extra:
        out.append("@interface %s ()" % interface.name)
        out.append("{")
        if extra:
            out += extra
        if stored:
            width = max(len(kind) for _, kind, _ in stored)
            for ivar, kind, name in sorted(stored, key=lambda item: item[0]):
                out.append("    %-*s %s;  // %s" % (width, kind, ivar, name))
        out.append("}")
        out.append("@end")
        out.append("")
    # A field a hand-written body keeps is not a property the header declares, so it is in neither
    # `stored` nor `synthesised`: nothing synthesises it and the copy/coding helpers do not walk it.
    # Each body that writes one says so at the point it writes it.
    out += ["@implementation %s" % interface.name] + synthesised
    # Three fields: the name, the category it came from, and why it is dynamic. The unpacking here
    # took two until a class property made `dynamic` non-empty for the first time (see the class
    # property branch in implementation()), and the cause is now what the comment should name -
    # "a class of a later group" is one cause of several and is wrong for the rest.
    for name, category, cause in dynamic:
        if not category:
            out.append("    @dynamic %s;  // %s: see registry/Intents"
                       % (name, CAUSE_LABELS.get(cause, cause)))

    if interface.name in HAND_WRITTEN:
        return out + ["", "@end", ""], {"properties": [], "dynamic": [], "methods": [],
                                        "causes": {}}

    out.append("")
    deferred_names = {name for name, _, _ in dynamic}
    methods_written = set()
    states = {}
    for ivar, kind, name in stored:
        member = own.get(name)
        if member is None and name in kept:
            # a value this class keeps a copy of for a superclass: a pointer is copied, a value
            # is retained, which is the same rule is_copy() gives for the class's own
            states[ivar] = "copy" if kind.rstrip().endswith("*") else "retain"
            continue
        states[ivar] = "copy" if member and is_copy(member, kind) else "retain"
    spellings = property_names(interface.properties)

    for name, kind in sorted(kept.items()):
        out += ["- (%s)%s" % (kind, name), "{", "    return _%s;" % name, "}", ""]

    for name, kind, member in setters:
        kind = spelled(kind)
        copied = is_copy(member, kind) and kind.rstrip().endswith("*")
        assigned = "[%s copy]" % name if copied else name
        out += ["- (void)set%s:(%s)%s" % (name[0].upper() + name[1:], kind, name), "{",
                "    _%s = %s;" % (name, assigned), "}", ""]

    # A class whose own header marks -init NS_UNAVAILABLE still answers one, and the SYSTEM does:
    # measured on the host's own Intents through class_getMethodImplementation - a compile-time call
    # does not build, which is the point - INMessage, INPerson, INBillDetails, INBalanceAmount,
    # INCurrencyAmount, INCallRecord, INCar and INFile each returned an object, no exception, with
    # respondsToSelector:init 1 and every property present and nil.  So the port emits -init too:
    # the marker is a compile-time marker, and refusing to define the method leaves a caller that
    # sends it reaching a NULL IMP.  The superclass's own -init is called through its IMP rather
    # than by name, for the same reason the marker exists.
    own_init = own_init_unavailable(interface, interfaces)
    if own_init and (interface.method("init") is not None or own_init_blocked_here(interface, interfaces)):
        out += ["- (instancetype)init", "{",
                "    // The header marks this class's -init unavailable.  The system still answers one:",
                "    // measured, [[%s alloc] init] returns an object with every property nil.  So the"
                % interface.name,
                "    // method is defined here, and the superclass's own -init is reached through its",
                "    // IMP, because the header forbids naming the selector.",
                "    Class parent = [%s class];" % interface.superclass,
                "    SEL selector = @selector(init);",
                "    IMP forward = parent ? class_getMethodImplementation(parent, selector) : NULL;",
                "    return forward ? ((id (*)(id, SEL))forward)(self, selector) : nil;",
                "}", ""]

    for method in interface.methods:
        selector = method.get("name") or ""
        if method.get("instance") is False or has_attr(method, "UnavailableAttr"):
            continue
        if not selector.startswith("init") or ":" not in selector:
            continue
        if re.match(r"^(initWithCoder:)$", selector):
            continue
        # An initialiser is not given a body when it takes a value this delivery does not carry:
        # one whose name is a member left dynamic, or one whose type is a class the headers only
        # forward declare (INDateComponentsRange's initWithEKRecurrenceRule: takes EventKit's
        # class, where the property of the same name takes the INRecurrenceRule of iOS 11). A body
        # that dropped the value would answer with a class that looks filled and is not.
        if any(parameter in deferred_names or
               deferred_type(kind, intents, carried, forward)
               for kind, parameter in parameters_of(method)):
            # An initialiser that takes a value this delivery does not carry cannot be given a
            # body without dropping that value, so it is left out and the registry says so; the
            # header's mark stays on it, so a port cannot call it and nothing crashes.
            skipped.append((selector, "deferred_value"))
            continue
        written = EXTRA_METHODS.get((interface.name, selector), False)
        if written is False:
            body = initialiser(interface, method, states, spellings, interfaces)
            if body is None:
                # The generator will not write a body that drops a value: the initialiser is left
                # out, and the registry entry says which of the two reasons it was.
                skipped.append((selector, "chain_nonnull" if initialiser(interface, method, states,
                                                                           spellings, interfaces) is None
                                else "deferred_value"))
                continue
            out += body
            out.append("")
        elif written:
            out += written + [""]

    for method in interface.methods:
        # The name under which a cause is recorded and under which EXTRA_METHODS is keyed. The
        # initialiser loop above leaves its own `selector` behind, so it is set here too: a lookup
        # that read the previous loop's value matched the wrong method, and the method it belonged
        # to was emitted twice.
        selector = method.get("name") or ""
        # A member the header marks UNAVAILABLE is not answered, and the cause is the mark: a port
        # cannot call it, so there is nothing to answer. These were falling through to the group's
        # blanket reason, which is what made +[INShortcut new] and the six -init rows read "a class
        # of a later group of this same delivery" for classes this delivery carries.
        if has_attr(method, "UnavailableAttr") and (interface.name, selector) not in EXTRA_METHODS \
                and selector not in accessors and selector not in own:
            skipped.append((selector, "unavailable"))
            continue
        # An accessor whose return type is a class this package does not carry: there is
        # nothing to keep the value in and no header of the port's own SDK that declares the
        # class, so a body would not compile against one.  INDateComponentsRange's
        # -EKRecurrenceRule is the one: it returns EventKit's EKRecurrenceRule, which the Intents
        # header only forward declares, while the property of the same name takes iOS 11's
        # INRecurrenceRule.  It was falling through to the group's blanket reason and the
        # registry wrote "a class of a later group of this same delivery", which is not what
        # stops it.
        # The guard below skips a member whose return type is a class this package does not carry,
        # and it runs BEFORE the hand-written hook is consulted. A body written by hand is not
        # generated from that type, so it is not subject to the guard: INCar's two charging-power
        # methods return NSMeasurement<NSUnitPower *>, which is Foundation's and is carried by the
        # Foundation package, but it is not in this framework's own class list, so both were
        # dropped as foreign_class and their rows fell back to the group's blanket reason.
        # An initialiser the loop above ALREADY emitted from this table must not be emitted again:
        # EXTRA_METHODS holds both initialisers and plain methods, and a member in it that is an
        # initialiser was written by the loop above. Without this, -[INObjectCollection
        # initWithItems:] appears twice in IN16_0.m and the 6.1.3 gate stops on it.
        hand_written = (interface.name, selector) in EXTRA_METHODS \
            and not (selector.startswith("init") and ":" in selector)
        withheld = deferred_type(returns_of(method), intents, carried, forward)
        if withheld and not hand_written and method.get("instance") is not False \
                and not has_attr(method, "UnavailableAttr") \
                and (method.get("name") or "") not in accessors \
                and (method.get("name") or "") not in own \
                and spelled(returns_of(method)).rstrip().endswith("*"):
            skipped.append((method.get("name"), "foreign_class"))
            continue
        built = factory(interface, method, resolution, interfaces)
        if built is False:
            causes_by_name["%s[%s %s]" % ("+" if method.get("instance") is False else "-",
                                             interface.name, method.get("name") or "")] = \
                "collection_factory"
            continue
        # A hand-written body for a method that is not an initialiser. The hook existed only for
        # initialisers: it was consulted inside the `selector.startswith("init")` loop above, so a
        # declared, available method the generator has no rule for - a singleton's setter, a
        # completion handler, a factory with no storage to fill - could not be given a body at
        # all, and its registry row fell back to the group's blanket reason. It is consulted here
        # too, so one table names every body that is written by hand.
        if hand_written:
            built = EXTRA_METHODS[(interface.name, selector)]
        out += built
        out.append("")

    if "NSSecureCoding" in conformed:
        # A class whose header marks -init unavailable - its own, or the one [super init] would
        # reach, which is the superclass's - cannot spell [super init] in a file that reads that
        # header, so the superclass's own -init is called by name instead.
        parent = interfaces.get(interface.superclass)
        blocked = [interface, parent]
        own_init = next((candidate.method("init") for candidate in blocked
                         if candidate is not None and candidate.method("init") is not None
                         and has_attr(candidate.method("init"), "UnavailableAttr")), None)
        if own_init is not None:
            start = ["    // The header marks this class's -init unavailable, so the superclass's own",
                     "    // -init is called through CharonCoding.h's one definition of it.",
                     "    if ((self = charon_intents_super_init(self, [%s class])))" % interface.superclass]
        else:
            start = ["    if ((self = [super init]))"]
        out += ["+ (BOOL)supportsSecureCoding", "{", "    return YES;", "}", "",
                "- (instancetype)initWithCoder:(NSCoder *)coder", "{"] + start + \
               ["        charon_intents_decode(self, coder);",
                "    return self;", "}", "",
                "- (void)encodeWithCoder:(NSCoder *)coder", "{",
                "    charon_intents_encode(self, coder);", "}"]
        out.append("")
    if "NSCopying" in conformed:
        out += ["- (id)copyWithZone:(NSZone *)zone", "{",
                "    %s *copy = [[[self class] allocWithZone:zone] init];" % interface.name,
                "    charon_intents_copy(copy, self);", "    return copy;", "}"]
        out.append("")
    # Charon's own readers for this class's stores, inside the @implementation and after everything
    # the header declares. They are internal at the link (a name starting with charon_ is what
    # modules/apple/backports.lua's internal_symbol() calls internal), so they carry no API symbol,
    # and each class row's `effect` names one - the way INVocabulary's row names
    # charon_vocabularyStringsOfType:. They go HERE and not after the @end: emitted after it, clang
    # reads a method declaration with no @implementation in scope and stops the build with
    # "missing context for method declaration", which is what the first attempt did.
    for (owner, _reader), lines in sorted(CHARON_READERS.items()):
        if owner == interface.name:
            out += lines + [""]
    out += ["@end", ""]
    # A property the SDK declares in a category of the class is answered by accessors in a
    # category of Charon's own: clang will not synthesise such a property in the class's own
    # @implementation, nor in a category's, so the accessors are written and read the class
    # extension's ivars, which are declared in this same file.
    for category, found in sorted(by_category.items()):
        out.append("@implementation %s (Charon%s%s)" % (interface.name, interface.name, category))
        for name, where, cause in dynamic:
            if where == category:
                out.append("    @dynamic %s;  // %s: see registry/Intents"
                       % (name, CAUSE_LABELS.get(cause, cause)))
        for name, kind, member in sorted(found, key=lambda item: item[0]):
            getter = (member.get("getter") or {}).get("name") or name
            out += ["", "- (%s)%s" % (kind, getter), "{", "    return _%s;" % name, "}"]
            if not member.get("readonly"):
                copied = is_copy(member, kind) and kind.rstrip().endswith("*")
                out += ["", "- (void)set%s:(%s)%s" % (name[0].upper() + name[1:], kind, name), "{",
                        "    _%s = %s;" % (name, "[%s copy]" % name if copied else name), "}"]
        out += ["", "@end", ""]
    causes = dict(causes_by_name)
    for selector, cause in skipped:
        causes[selector] = cause
    report = answer_of(out, interface.name)
    report["causes"] = causes
    # A class property is answered by its +accessor, which is the only thing in the emitted text
    # that carries the name: there is no @synthesize for it and the header declares no ivar, so
    # answer_of() cannot see it. So it is matched here against the class's OWN declaration list and
    # against an accessor that was actually written - +name is the shape, and it has to be in the
    # emitted methods, so a class property with no accessor written is not claimed.
    written = set(entry.partition("[")[2].rpartition(" ")[2].rstrip("]")
                  for entry in report["methods"] if entry.startswith("+["))
    report["class_properties"] = sorted(name for name in class_properties
                                        if name in written)
    return out, report


# +successWithResolved…:, +successWithResolvedValue:, +disambiguationWith…ToDisambiguate:,
# +confirmationRequiredWith…ToConfirm: — the three answers a resolution result gives.
SUCCESS = re.compile(r"^successWithResolved(.*):$")
SUCCESS_VALUE = "successWithResolvedValue:"
DISAMBIGUATION = re.compile(r"^disambiguationWith(.*)ToDisambiguate:$")
DISAMBIGUATION_VALUE = "disambiguationWithValueToDisambiguate:"
CONFIRMATION = re.compile(r"^confirmationRequiredWith(.*)ToConfirm:$")
CONFIRMATION_VALUE = "confirmationRequiredWithValueToConfirm:"


def single_item_factory(interface, plural, interfaces=None):
    """The class's own factory for one item, for a factory that answers a collection of them.

    `+successesWithResolvedMediaItems:` and `+successWithResolvedMediaItem:` differ in a plural
    and a singular, so the singular is looked for by name among the class's own methods rather
    than spelled here - the generator has the class's declarations, and the spelling is Apple's.
    """
    stem = plural.split(":")[0]
    if not stem.startswith("successes"):
        return None
    rest = stem[len("successes"):]
    wanted = "success" + rest
    if rest.endswith("s"):
        wanted = "success" + rest[:-1]
    # The single-item factory is declared by the base and inherited by the four subclasses that
    # pluralise it, so the whole superclass chain is asked.
    seen, name = set(), interface.name
    while interfaces and name and name not in seen:
        seen.add(name)
        for candidate in interfaces[name].methods:
            if candidate.get("instance") is False and (candidate.get("name") or "") == wanted + ":":
                return candidate
        name = interfaces[name].superclass
    return None


def factory(interface, method, resolution, interfaces=None):
    """The body of a resolution result's class method, or nothing."""
    selector = method.get("name") or ""
    if not resolution or has_attr(method, "UnavailableAttr"):
        return []
    returns = spelled(returns_of(method))
    if (returns.rstrip().endswith("*") and "NSArray" in returns) \
            or selector.startswith("successesWithResolved"):
        # A factory that answers an **array** of resolution results is one result per item, each
        # made by this class's own single-item factory. That was measured on the host through
        # objc_msgSend into all five of them (macOS 26's Intents.framework), which answers:
        #   two items  -> __NSArrayM, count 2, each element an instance of the class asked
        #   one item   -> count 1, one element of the class
        #   empty      -> count 0, an array
        #   nil        -> count 0, an array - not nil, because a caller counts what it is given
        # and each element's resolvedValue is the item it was made from. So this is a map, and the
        # only shape the framework's own has.
        single = single_item_factory(interface, selector, interfaces)
        if not single:
            # No single-item factory to map with: nothing is emitted and the cause is recorded,
            # because a body returning nil would be a collection that looks full and is empty.
            return False
        keyword = (single.get("name") or "").split(":")[0]
        item = parameters_of(single)[0][1] if parameters_of(single) else "item"
        input = parameters_of(method)[0][1] if parameters_of(method) else "items"
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    // One result per item, each made by this class's own single-item factory",
                "    // +%s, and an empty array for an input that is nil or empty - the"
                % keyword,
                "    // host's own answer, measured on all five of these factories.",
                "    NSMutableArray *results = [NSMutableArray arrayWithCapacity:%s.count];" % input,
                "    for (id %s in %s) {" % (item, input),
                "        [results addObject:[self %s:%s]];" % (keyword, item),
                "    }",
                "    return results;",
                "}"]
    parameters = parameters_of(method)
    if not parameters or len(parameters) != 1:
        return []
    returns = spelled(returns_of(method))
    if returns not in ("instancetype", interface.name, interface.name + " *"):
        return []
    kind, name = parameters[0]
    if spelled(kind).rstrip().endswith("*"):
        value = "[%s copy]" % name
    elif spelled(kind) == "BOOL":
        value = "@(%s)" % name
    elif spelled(kind) in ("NSInteger", "NSUInteger", "int", "long", "short", "unsigned"):
        value = "[NSNumber numberWithInteger:(NSInteger)%s]" % name
    elif spelled(kind) in ("double", "float", "NSTimeInterval", "CGFloat"):
        value = "[NSNumber numberWithDouble:(double)%s]" % name
    else:
        value = "[NSNumber numberWith%s:%s]" % ({"char": "Char", "unsigned char": "UnsignedChar",
                                                 "long long": "LongLong"}.get(spelled(kind), "Integer"), name)
    if SUCCESS.match(selector) or selector == SUCCESS_VALUE:
        # The host's own rule, measured on its framework with objc_msgSend over every
        # enum-typed success factory: a success whose value is the enumeration's **zero** case
        # says nothing, and the system re-forms it as a notRequired; any other value is a value
        # the caller resolved, and the host leaves it a success. Seventeen enumerations measured,
        # and the decision is the value's, not the declared type's - a factory that answered
        # notRequired for every value of its type would throw away every real resolution.
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    // The host re-forms a success carrying the zero case of its type as a",
                "    // notRequired - a success with nothing to say - and leaves any other value a",
                "    // success (measured on the host's own Intents, 17 enumerations).",
                "    return [self charon_resolutionWithStatus:%s == 0 ? CharonIntentsResolutionNotRequired"
                % name,
                "                                                : CharonIntentsResolutionSuccess",
                " resolvedValue:%s valuesToDisambiguate:nil valueToConfirm:nil];" % value, "}"]
    if DISAMBIGUATION.match(selector) or selector == DISAMBIGUATION_VALUE:
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    return [self charon_resolutionWithStatus:CharonIntentsResolutionDisambiguation"
                " resolvedValue:nil valuesToDisambiguate:%s valueToConfirm:nil];" % value, "}"]
    if selector in ("unsupportedForReason:", "unsupportedWithReason:"):
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    return [self charon_resolutionWithStatus:CharonIntentsResolutionUnsupported"
                " resolvedValue:nil valuesToDisambiguate:nil valueToConfirm:nil"
                " unsupportedReason:%s];" % name, "}"]
    if CONFIRMATION.match(selector) or selector == CONFIRMATION_VALUE:
        return ["+ (%s)%s" % (returns, interface.spelled_selector(method)), "{",
                "    return [self charon_resolutionWithStatus:CharonIntentsResolutionConfirmationRequired"
                " resolvedValue:nil valuesToDisambiguate:nil valueToConfirm:%s];" % value, "}"]
    return []


def banner(name, classes, release, deferred):
    return """//
//  %(name)s
//  Intents
//
//  Generated by tools/intents/gen-intents.py from the Objective-C declarations of the
//  SDK's own headers, for the %(count)d classes the armv7 release caches measure as first
//  exported in iOS %(release)s. Do not edit: change the generator and run it again.
//
//  Every method the header declares here has a body that stores or returns the class's own
//  state, the coding and copying helpers walk the whole ivar chain so a subclass keeps its
//  parent's state, and %(deferred)d member(s) are left dynamic - a class property of the
//  class's own type, or a property of a class of a later group - and answered in
//  registry/Intents instead of with nil.
//
//  The classes whose behaviour is more than storage are hand written in
//  CharonIntents%(release)s.m, and the generator leaves them out.
//

#import <Intents/Intents.h>
#import <objc/runtime.h>
#import "../../../c/charon-coding/files/CharonCoding.h"
#import "CharonIntentsResolution.h"
#import "CharonIntents262.h"

// The SDK marks each class's initialiser as the designated one, in a header this package does not
// own and cannot add a marking to, so clang reads the -initWithCoder: and -copyWithZone: every
// class carries here as convenience initialisers of a class that has a designated one. The
// warning is about a convention and not about behaviour: the chain below is the header's own.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
""" % {"name": name, "count": classes, "release": release, "deferred": deferred}


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sdk", required=True)
    parser.add_argument("--dump", required=True)
    parser.add_argument("--dump-newer",
                        help="an AST of a newer SDK, for the names the port's own SDK does not "
                             "declare: those classes are the ones CharonIntents262.h declares, "
                             "and their contracts are read from the newer SDK's headers")
    parser.add_argument("--classes", required=True)
    parser.add_argument("--release", required=True)
    parser.add_argument("--carried", required=True,
                        help="a file of every class name this delivery carries, all groups")
    parser.add_argument("--intents", required=True,
                        help="a file of every Intents class name of SDK 26.2")
    parser.add_argument("--out", required=True)
    parser.add_argument("--report", help="a JSON file of what the emitted code answers")
    options = parser.parse_args()

    interfaces, protocols, _, forward = collect(options.dump)
    newer = None
    if options.dump_newer:
        # The names the port's SDK does not declare, and the newer SDK that does: the class is
        # the same, the contract is the newer header's, and the declaration the implementation
        # compiles against is the one in CharonIntents262.h.
        interfaces_before = set(interfaces)
        fresh, newer_protocols, _, newer_forward = collect(options.dump_newer)
        # Only for a class the port's own SDK does not have at all. A class both declare is
        # taken from the port's SDK: its declaration is the one the implementation compiles
        # against, and the newer one names members (INRelevantShortcut, INVoiceShortcut) the
        # port's headers do not, which would not build.
        for name, value in fresh.items():
            if name not in interfaces:
                interfaces[name] = value
        for name, value in newer_protocols.items():
            protocols.setdefault(name, value)
        newer = set(fresh) - set(interfaces_before)
    names = [line.strip() for line in open(options.classes) if line.strip()]
    carried = {line.strip() for line in open(options.carried) if line.strip()}
    intents = {line.strip() for line in open(options.intents) if line.strip()}
    missing = [name for name in names if name not in interfaces]
    if missing:
        print("not in the SDK's headers: %s" % ", ".join(missing), file=sys.stderr)
        return 1

    generated = [name for name in names if name not in HAND_WRITTEN]
    alone = [(name, ALONE[name]) for name in generated if name in ALONE]
    if alone:
        generated = [name for name in generated if name not in ALONE]
    banner_text = banner(options.out.rsplit("/", 1)[-1], len(generated), options.release, 0)
    out = [banner_text]
    answered, deferred = {}, 0
    for name in generated:
        interface = interfaces[name]
        body, report = render(interface, protocols, carried, intents, interfaces, forward)
        out.append("")
        out.extend(body)
        answered[name] = report
        deferred += len(report["dynamic"])
    out[0] = banner(options.out.rsplit("/", 1)[-1], len(generated), options.release, deferred)
    squeezed = []
    for line in out:
        if line == "" and squeezed and squeezed[-1] == "":
            continue
        squeezed.append(line)
    if alone:
        # One file per class that must be alone, named for the release below the group's own that
        # already exports it, so the name says which band re-exports the object and which keeps it.
        for name, below in alone:
            path = options.out.rsplit("/", 1)[0] + "/" + name + below + ".m"
            interface = interfaces[name]
            body, report = render(interface, protocols, carried, intents, interfaces, forward)
            text = [banner(path.rsplit("/", 1)[-1], 1, options.release, len(report["dynamic"]))]
            # The file says why it is alone, in a comment the compiler reads as a comment: a
            # line that starts with a hash at column zero is a preprocessing directive, and the
            # lines below are prose about the band check.
            for line in (ALONE_REASON % {"name": name, "below": below}).split("\n"):
                text.append("//  " + line)
            text.append("")
            text.extend(body)
            with open(path, "w") as handle:
                handle.write("\n".join(text).rstrip("\n") + "\n")
            print("%s: %s alone, %d members" % (path, name, len(report["methods"]) + len(report["properties"])))
            answered[name] = report
    with open(options.out, "w") as handle:
        handle.write("\n".join(squeezed).rstrip("\n") + "\n")
    if options.report:
        with open(options.report, "w") as handle:
            json.dump(answered, handle, indent=1, sort_keys=True)
            handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
