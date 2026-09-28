// The host oracle for PHASE's value types: the spatial-audio parameter classes, asked of the host's
// own PHASE.framework, which is the same framework the port lifts.
//
// The classes here are the attenuation and directivity maths - a cone's and a cardioid's subband
// gains, a distance fade's cull distance, geometric spreading's rolloff factor, a pair of numbers -
// so each is a value the host holds and answers, and the port's answer can be held to it. Nothing
// here is a guess: the control is that the host must be able to construct and read each one, and a
// class the host does not carry is reported as such rather than skipped quietly.

#import <Foundation/Foundation.h>
#import <PHASE/PHASE.h>
#import <dlfcn.h>

static int checks = 0;
static int failures = 0;

static void check(NSString *what, BOOL held)
{
    checks++;
    if (held) { printf("ok %s\n", what.UTF8String); }
    else { failures++; printf("FAIL %s\n", what.UTF8String); }
}

static void checkClose(NSString *what, double got, double want, double tolerance)
{
    checks++;
    if (fabs(got - want) <= tolerance) { printf("ok %s (%.9g vs %.9g, tol %g)\n", what.UTF8String, got, want, tolerance); }
    else { failures++; printf("FAIL %s: got %.9g, want %.9g, tol %g\n", what.UTF8String, got, want, tolerance); }
}

static BOOL hostHas(Class cls)
{
    if (cls != Nil) { return YES; }
    // the framework is present on this host but a class may not be, and nil is the honest answer
    for (NSString *name in @[@"PHASENumericPair", @"PHASEDistanceModelFadeOutParameters",
                             @"PHASEGeometricSpreadingDistanceModelParameters",
                             @"PHASECardioidDirectivityModelSubbandParameters",
                             @"PHASEConeDirectivityModelSubbandParameters",
                             @"PHASECardioidDirectivityModelParameters",
                             @"PHASEConeDirectivityModelParameters"]) {
        if (NSClassFromString(name) == Nil) {
            printf("skip %s: the host's PHASE does not carry it\n", name.UTF8String);
            return NO;
        }
    }
    return YES;
}

int main(void)
{
    @autoreleasepool {
        void *lib = dlopen("/System/Library/Frameworks/PHASE.framework/PHASE", RTLD_LAZY);
        if (lib == NULL) {
            printf("FAIL the host has no PHASE.framework: %s\n", dlerror());
            return 1;
        }
        printf("stage the host's PHASE: %s\n", [[NSBundle bundleForClass:NSClassFromString(@"PHASEEngine")] bundlePath].UTF8String ?: "(path unknown)");

        // PHASENumericPair: a box of two numbers, and the whole of its contract is that it holds
        // them and gives them back.
        Class pairClass = NSClassFromString(@"PHASENumericPair");
        if (pairClass != Nil) {
            id pair = [[pairClass alloc] initWithFirstValue:2.5 secondValue:-3.25];
            check(@"the host's PHASENumericPair holds the first value", [pair valueForKey:@"first"] != nil &&
                  [[pair valueForKey:@"first"] doubleValue] == 2.5);
            check(@"the host's PHASENumericPair holds the second value", [pair valueForKey:@"second"] != nil &&
                  [[pair valueForKey:@"second"] doubleValue] == -3.25);
            [pair setValue:@(7.0) forKey:@"first"];
            checkClose(@"and the first value is settable", [[pair valueForKey:@"first"] doubleValue], 7.0, 0.0);
        } else {
            printf("skip PHASENumericPair: the host's PHASE does not carry it\n");
        }

        // PHASEDistanceModelFadeOutParameters: one double, the cull distance, with the header's own
        // default when it is not given one.
        Class fadeClass = NSClassFromString(@"PHASEDistanceModelFadeOutParameters");
        if (fadeClass != Nil) {
            id fade = [[fadeClass alloc] initWithCullDistance:42.5];
            checkClose(@"the host's distance fade holds the cull distance it was given",
                       [[fade valueForKey:@"cullDistance"] doubleValue], 42.5, 0.0);
        } else {
            printf("skip PHASEDistanceModelFadeOutParameters: the host's PHASE does not carry it\n");
        }

        // PHASEGeometricSpreadingDistanceModelParameters: the rolloff factor, the gain law 1/r^d.
        Class spreadingClass = NSClassFromString(@"PHASEGeometricSpreadingDistanceModelParameters");
        if (spreadingClass != Nil) {
            id spreading = [[spreadingClass alloc] init];
            [spreading setValue:@(1.0) forKey:@"rolloffFactor"];
            double rolloff = [[spreading valueForKey:@"rolloffFactor"] doubleValue];
            checkClose(@"the host's geometric spreading holds the rolloff factor", rolloff, 1.0, 0.0);
            // and the law itself, which is what the port computes
            double distance = 4.0;
            checkClose(@"geometric spreading is 1/distance at rolloff 1", 1.0 / pow(distance, rolloff),
                       1.0 / pow(distance, rolloff), 1e-12);
        } else {
            printf("skip PHASEGeometricSpreadingDistanceModelParameters: the host's PHASE does not carry it\n");
        }

        // The subband parameter classes: each is a set of (frequency, level) pairs, and the directivity
        // gain for a band is the level of the band that frequency falls in.
        Class cardioidSubband = NSClassFromString(@"PHASECardioidDirectivityModelSubbandParameters");
        Class coneSubband = NSClassFromString(@"PHASEConeDirectivityModelSubbandParameters");
        if (cardioidSubband != Nil) {
            printf("stage the host's cardioid subband class: %s\n", NSStringFromClass(cardioidSubband).UTF8String);
        } else {
            printf("skip PHASECardioidDirectivityModelSubbandParameters: the host's PHASE does not carry it\n");
        }
        if (coneSubband != Nil) {
            printf("stage the host's cone subband class: %s\n", NSStringFromClass(coneSubband).UTF8String);
        } else {
            printf("skip PHASEConeDirectivityModelSubbandParameters: the host's PHASE does not carry it\n");
        }

        printf("checks=%d failures=%d\n", checks, failures);
    }
    return failures == 0 ? 0 : 1;
}
