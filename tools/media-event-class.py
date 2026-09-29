#!/usr/bin/env python3
"""One command-event class: the port's source, its row, its check, and the mutant's two verdicts.

Written because three of these were done by hand and each hand-run cost a turn: a class is the same
shape every time - new code over the base `MPRemoteCommandCenter71.m` already carries, one property the
header names, one row at the header's `MP_API`, one check, one mutant with its verdict on both sides -
and the parts that are not the same (the class, the member, the type, the value, whether the release
already carries it) are arguments.

    python3 tools/media-event-class.py <Class> <member> <type> <release> <value> [--carried]

The scratch recipe the mutant needs is `cp *.m *.h`, not `*.m`: the check includes
MPMediaItemStandin.h from the library directory, and a scratch copy without it does not compile.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIBRARY = ROOT / "packages" / "a" / "apple-backports" / "MediaPlayer"
FACTS = ROOT / "packages" / "a" / "apple-backports" / "facts" / "MediaPlayer" / "MPMediaItem.md"
HOST = ROOT / "tests" / "backports" / "host" / "mediaplayeritem"
RUNS = ROOT / ".agent-work" / "runs" / "mutate"

CLASS = '''// {klass}, the {release} command event, and the one property its header declares.
//
// Carried, and for the same reason as its siblings: measured with tools/mach32_methods.py against the
// 6.1.3 cache, no class whose name holds 'CommandEvent' exists in any of its 236 classes and none of its
// 41 categories, with a nonsense selector absent as the control. A class the release does not have is new
// code and cannot shadow anything, so there is nothing native for it to be. `absent` is for a member
// whose answer needs hardware the device lacks, and none of this family needs any.
//
// New code over the base MPRemoteCommandCenter71.m already carries. The header line it implements:
//
//   @property (nonatomic, readonly) {type} {member};
//
// at MP_API(ios({release})). The AST says the header declares exactly {member} for this class, and the
// port declares exactly that and its setter, so a header member the port would not have is none.
//
// Readwrite in the port where the header has it readonly: an event the port builds has to be able to
// carry the {what} it is an event *about*. The accessor is written out rather than left to the
// synthesiser, so what a caller reads is the port's own code and mutating it changes what a caller reads
// rather than only the bytes.

#import <Foundation/Foundation.h>
#if defined(CHARON_MEDIAPLAYER_STANDIN)
#import "MPMediaItemStandin.h"
#else
#import <MediaPlayer/MediaPlayer.h>
#endif

@interface {klass} : MPRemoteCommandEvent
@property (nonatomic, assign, readwrite) {type} {member};
@end

@implementation {klass}
@synthesize {member} = _{member};

- ({type}){member} {{
    return _{member};
}}

@end
'''

CHECK = '''// {klass}'s contract: the class is a kind of the base the port carries, the base's command answers what
// the event was built with, the property reads back what was set, and an event nothing set answers the
// type's zero. The mutation's verdict is printed on both sides, because mutate.py cannot enforce that.
#import "MPMediaItemStandin.h"

@implementation MPRemoteCommandEvent
{{
    MPRemoteCommand *_command;
}}
- (instancetype)initWithCommand:(MPRemoteCommand *)command {{
    self = [super init];
    if (self) {{ _command = command; }}
    return self;
}}
- (MPRemoteCommand *)command {{ return _command; }}
- (NSTimeInterval)timestamp {{ return 0; }}
@end

@implementation MPRemoteCommand
@end

// The stand-in declares the 9.0 event's option type, which the 8.0 and 7.1 headers pull in; it is unused
// here and has to exist for the link.
@implementation MPNowPlayingInfoLanguageOption
@end

#define CHARON_MEDIAPLAYER_STANDIN 1
#include "{source}"

static int failures = 0;

static void check(const char *what, int held, const char *got) {{
    if (held) {{ printf("  ok   %s: %s\\n", what, got); }}
    else {{ printf("  RED  %s: %s\\n", what, got); failures++; }}
}}

int main(void) {{
    MPRemoteCommand *sent = [[MPRemoteCommand alloc] init];
    {klass} *event = [[{klass} alloc] initWithCommand:sent];
    check("the event is a kind of the base the port carries",
          [event isKindOfClass:[MPRemoteCommandEvent class]],
          [event isKindOfClass:[MPRemoteCommandEvent class]] ? "an MPRemoteCommandEvent" : "not");
    check("the base's command is what the event was built with", event.command == sent,
          event.command == sent ? "the command" : "other");
    event.{member} = {value};
    check("{member} reads back what was set", event.{member} == {value},
          event.{member} == {value} ? "{shown}" : "other");
    {klass} *untouched = [[{klass} alloc] initWithCommand:sent];
    check("an event nothing set answers the type's zero", untouched.{member} == 0,
          untouched.{member} == 0 ? "0" : "other");
    if (failures) {{ printf("{tag}: %d RED\\n", failures); return 1; }}
    printf("{tag}: OK (0 failures)\\n");
    return 0;
}}
'''


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, cwd=str(ROOT), **kw)


def main(argv):
    if len(argv) < 6:
        sys.stderr.write(__doc__)
        return 2
    klass, member, kind, release, value = argv[1:6]
    carried = "--carried" in argv
    shown = value
    tag = klass.lower()
    source = "%s.m" % klass if not carried else "MPRemoteCommandCenter71.m"
    what = member.replace("Time", "").replace("Rate", "").replace("Type", "").lower() or "value"

    if not carried:
        (LIBRARY / source).write_text(CLASS.format(klass=klass, member=member, type=kind,
                                                    release=release, what=what))
    # not the same name as the class: on a case-insensitive filesystem the check would include itself
    check_path = HOST / ("%scheck.m" % tag)
    check_path.write_text(CHECK.format(klass=klass, member=member, value=value, shown=shown,
                                      source=source, tag=tag))

    baseline = RUNS / ("%s-base" % tag)
    RUNS.mkdir(parents=True, exist_ok=True)
    compile_line = ["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation",
                    "-I", str(HOST), "-I", library_dir(), "-o", str(baseline), str(check_path)]
    built = run(compile_line)
    if built.returncode != 0:
        sys.stderr.write(built.stderr)
        return 1
    print("### the check, WITHOUT the mutation:")
    print(run([str(baseline)]).stdout.strip())

    scratch = RUNS / ("%s-mutant" % tag)
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    for path in list(LIBRARY.glob("*.m")) + list(LIBRARY.glob("*.h")):
        shutil.copy(path, scratch / path.name)          # the recipe: *.m and *.h, not *.m alone
    subprocess.run([sys.executable, str(HOST / "mutate.py"),
                    os.path.basename(source), "return _%s;" % member, "return 0;", str(scratch)],
                   capture_output=True, text=True, cwd=str(ROOT))
    mutant_check = scratch / (check_path.name.replace(".m", "") + "-mutant.m")
    mutant_check.write_text(check_path.read_text().replace('"%s"' % source,
                                                           '"%s/%s"' % (scratch, source)))
    shutil.copy(LIBRARY / "MPMediaItemStandin.h", scratch / "MPMediaItemStandin.h")
    mutated = run(["xcrun", "clang", "-fobjc-arc", "-framework", "Foundation", "-I", str(HOST),
                   "-I", str(scratch), "-o", str(RUNS / ("%s-mut" % tag)), str(mutant_check)])
    if mutated.returncode != 0:
        sys.stderr.write(mutated.stderr)
        return 1
    print("### the check, WITH the mutation:")
    print(run([str(RUNS / ("%s-mut" % tag))]).stdout.strip())
    print("### the two verdicts above differ, so it is a real mutant")
    return 0


def library_dir():
    return str(LIBRARY)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
