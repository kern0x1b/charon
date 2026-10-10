#!/usr/bin/env python3
"""Run test for the trace layer's property and method stubs: the generator writes the stubs for a fixture framework, the host
compiler builds them into a program, and the program calls each stub through the Objective-C runtime. Each call must log its
selector once to stderr and return the safe default: nil for an object, 0 for a scalar, NO for BOOL, a zeroed struct, and an
NSError in the framework's own domain for an NSError ** parameter. Setters must be the selector the property names (setScope:),
not a truncation of it. Run: python3 tests/gen/trace_run_test.py (needs the macOS command line tools; exits 1 on any failure)."""
import os
import shutil
import subprocess
import sys
import tempfile

TREE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(TREE, "tools"))
import gen  # noqa: E402

FRAMEWORK = "FixtureKit"
HEADER = """#import <Foundation/Foundation.h>

@interface FKThing : NSObject
@property (nonatomic, readwrite) NSInteger scope;
@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, copy) NSString *name;
- (BOOL)setLevel:(NSInteger)level error:(NSError **)error;
- (NSArray *)items;
- (void)reset;
@end

NSInteger FKCountThings(NSInteger count, NSError **error);
"""

PROGRAM = r"""
#import <FixtureKit/FixtureKit.h>
#include <stdio.h>

// the class itself is the framework's to define; every member is the trace layer's stub, in its category
@implementation FKThing
@end

static int failures = 0;

#define CHECK(cond, label) do { if (!(cond)) { failures++; printf("FAIL %s\n", label); } else { printf("ok   %s\n", label); } } while (0)

int main(void) {
    @autoreleasepool {
        FKThing *thing = [[FKThing alloc] init];
        CHECK([thing scope] == 0, "getter returns 0 for an integer property");
        [thing setScope:5];
        [thing setScope:6];
        CHECK([thing isEnabled] == NO, "getter with getter= returns NO for BOOL");
        [thing setEnabled:YES];
        NSError *error = nil;
        CHECK([thing setLevel:1 error:&error] == NO, "method with NSError ** returns NO");
        CHECK(error != nil && [[error domain] isEqualToString:@"FixtureKit.Unimplemented"] && [error code] == -1,
              "NSError ** is set in the framework's domain with code -1");
        CHECK([thing items] == nil, "method returning an object returns nil");
        [thing reset];
        CHECK([thing name] == nil, "readonly object property returns nil");
        NSError *countError = nil;
        CHECK(FKCountThings(3, &countError) == 0, "C function returns 0 for an integer result");
        CHECK(countError != nil && [[countError domain] isEqualToString:@"FixtureKit.Unimplemented"],
              "C function sets an NSError ** in the framework's domain");
    }
    return failures ? 1 : 0;
}
"""


def write_fixture(root):
    """A fixture SDK with the one header, and the spec snapshot the generator would write for it: the rows of the header's class."""
    headers = os.path.join(root, "sdk", "System", "Library", "Frameworks", FRAMEWORK + ".framework", "Headers")
    os.makedirs(headers)
    with open(os.path.join(headers, FRAMEWORK + ".h"), "w", encoding="ascii") as handle:
        handle.write(HEADER)
    rows = []
    for cls, kind, api, api_key, clean, avail in gen.members_of(HEADER):
        rows.append({"kind": kind, "api": api, "cls": cls, "key": gen.mangle(api), "introduced": "-", "decl": clean,
                     "availability": avail or "-", "hash": "0" * 16, "value_status": "-", "value": "-", "host_value": "-",
                     "value_source": "-", "owned": "-", "tbd": "-", "shape": "-", "measured": "-"})
    snap = os.path.join(root, "tree", gen.SNAP_ROOT, FRAMEWORK)
    os.makedirs(snap)
    statement = [s for s in gen.c_statements(HEADER, "FKCountThings")][0]
    returns, params, introduced, decl = gen.c_declaration(statement, "FKCountThings")
    with open(os.path.join(snap, "functions.tsv"), "w", encoding="ascii") as handle:
        handle.write("\t".join(gen.FUNCTION_COLUMNS) + "\n")
        handle.write("\t".join(["FKCountThings", introduced, "generable", "", returns, "; ".join(params), decl]) + "\n")
    with open(os.path.join(snap, "spec.%s.tsv" % gen.SDK_ID), "w", encoding="ascii") as handle:
        handle.write("\t".join(gen.SPEC_COLUMNS) + "\n")
        for r in rows:
            handle.write("\t".join(str(r.get(c, "-")) for c in gen.SPEC_COLUMNS) + "\n")
    return os.path.join(root, "sdk"), os.path.join(root, "tree"), rows


def main():
    root = tempfile.mkdtemp(prefix="charon-trace-run-")
    failed = 0
    try:
        sdk, tree, rows = write_fixture(root)
        args = type("Args", (), {"tree": tree, "framework": FRAMEWORK, "sdk": sdk, "all": False})()
        if gen.cmd_trace(args) != 0:
            print("FAIL the trace layer could not be generated")
            return 1
        stub_file = os.path.join(tree, gen.OUT_ROOT, FRAMEWORK, "trace", FRAMEWORK + "Defaults.m")
        program = os.path.join(root, "main.m")
        with open(program, "w", encoding="ascii") as handle:
            handle.write(PROGRAM)
        binary = os.path.join(root, "run")
        build = subprocess.run(["clang", "-fobjc-arc", "-DCHARON_TRACE_DEFAULTS", "-F", os.path.join(sdk, "System", "Library", "Frameworks"),
                                "-I", os.path.join(sdk, "System", "Library", "Frameworks", FRAMEWORK + ".framework", "Headers"),
                                "-framework", "Foundation", "-w", program, stub_file, "-o", binary],
                               capture_output=True, text=True)
        if build.returncode != 0:
            print("FAIL the stubs do not compile:\n" + build.stderr[-1200:])
            return 1
        run = subprocess.run([binary], capture_output=True, text=True)
        print(run.stdout, end="")
        logged = [line for line in run.stderr.splitlines() if line.startswith("unimplemented:")]
        expected = ["unimplemented: FixtureKit -[FKThing setScope:]", "unimplemented: FixtureKit -[FKThing scope]",
                    "unimplemented: FixtureKit -[FKThing isEnabled]", "unimplemented: FixtureKit -[FKThing setEnabled:]",
                    "unimplemented: FixtureKit -[FKThing setLevel:error:]", "unimplemented: FixtureKit -[FKThing items]",
                    "unimplemented: FixtureKit -[FKThing reset]", "unimplemented: FixtureKit -[FKThing name]",
                    "unimplemented: FixtureKit FKCountThings"]
        for line in expected:
            count = logged.count(line)
            if count != 1:
                failed += 1
                print("FAIL log line logged %d times, expected once: %s" % (count, line))
        extra = sorted(set(logged) - set(expected))
        if extra:
            failed += 1
            print("FAIL unexpected log lines: %s" % extra)
        if run.returncode != 0:
            failed += 1
            print("FAIL the program reported failures (exit %d)" % run.returncode)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print("trace run test: %s" % ("FAIL %d" % failed if failed else "OK"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
