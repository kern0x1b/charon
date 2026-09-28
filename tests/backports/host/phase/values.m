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

// The port's own classes, renamed by run.sh so they sit beside Apple's in this binary.
@interface charon_host_PHASECardioidDirectivityModelSubbandParameters : NSObject
- (instancetype)init;
- (double)frequency;
- (double)pattern;
- (double)sharpness;
@end

@interface charon_host_PHASEConeDirectivityModelSubbandParameters : NSObject
- (instancetype)init;
- (double)frequency;
- (double)innerAngle;
- (double)outerAngle;
- (double)outerGain;
@end

@interface charon_host_PHASEGeometricSpreadingDistanceModelParameters : NSObject
- (double)rolloffFactor;
- (void)setRolloffFactor:(double)rolloffFactor;
@end

@interface charon_host_PHASENumericPair : NSObject
- (instancetype)initWithFirstValue:(double)first secondValue:(double)second;
- (double)first;
- (double)second;
@end

// A fresh object of each kind, from the port and from the host, and the eight documented numbers
// compared between them. This is the half that fails when the port's defaults are wrong.
static void compareDefaults(void)
{
    Class portCardioid = NSClassFromString(@"charon_host_PHASECardioidDirectivityModelSubbandParameters");
    Class portCone = NSClassFromString(@"charon_host_PHASEConeDirectivityModelSubbandParameters");
    Class hostCardioid = NSClassFromString(@"PHASECardioidDirectivityModelSubbandParameters");
    Class hostCone = NSClassFromString(@"PHASEConeDirectivityModelSubbandParameters");

    if (portCardioid != Nil && hostCardioid != Nil) {
        id mine = [[portCardioid alloc] init];
        id theirs = [[hostCardioid alloc] init];
        check(@"the port's fresh cardioid subband has the same frequency default",
              [[mine valueForKey:@"frequency"] doubleValue] == [[theirs valueForKey:@"frequency"] doubleValue]);
        check(@"the port's fresh cardioid subband has the same pattern default",
              [[mine valueForKey:@"pattern"] doubleValue] == [[theirs valueForKey:@"pattern"] doubleValue]);
        check(@"the port's fresh cardioid subband has the same sharpness default",
              [[mine valueForKey:@"sharpness"] doubleValue] == [[theirs valueForKey:@"sharpness"] doubleValue]);
        printf("stage cardioid subband defaults: port %g/%g/%g, host %g/%g/%g\n",
               [[mine valueForKey:@"frequency"] doubleValue], [[mine valueForKey:@"pattern"] doubleValue],
               [[mine valueForKey:@"sharpness"] doubleValue],
               [[theirs valueForKey:@"frequency"] doubleValue], [[theirs valueForKey:@"pattern"] doubleValue],
               [[theirs valueForKey:@"sharpness"] doubleValue]);
    }
    if (portCone != Nil && hostCone != Nil) {
        id mine = [[portCone alloc] init];
        id theirs = [[hostCone alloc] init];
        const char *keys[4] = {"frequency", "innerAngle", "outerAngle", "outerGain"};
        for (int index = 0; index < 4; index++) {
            NSString *key = @(keys[index]);
            checkClose([NSString stringWithFormat:@"the port's fresh cone subband has the same %@ default", key],
                       [[mine valueForKey:key] doubleValue], [[theirs valueForKey:key] doubleValue], 0.0);
        }
    }
    Class portSpreading = NSClassFromString(@"charon_host_PHASEGeometricSpreadingDistanceModelParameters");
    if (portSpreading != Nil) {
        id mine = [[portSpreading alloc] init];
        checkClose(@"the port's fresh geometric spreading object has the same rolloff default",
                   [[mine valueForKey:@"rolloffFactor"] doubleValue], 1.0, 0.0);
    }
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
            // a fresh object, and its default, which is the thing the review found the port wrong
            // about. The old check 6 was tautological: it compared 1.0/pow(d,rolloff) with
            // 1.0/pow(d,rolloff), so it could not fail and taught nothing.
            id fresh = [[spreadingClass alloc] init];
            checkClose(@"a fresh geometric spreading object holds the header's default rolloff factor",
                       [[fresh valueForKey:@"rolloffFactor"] doubleValue], 1.0, 0.0);
        } else {
            printf("skip PHASEGeometricSpreadingDistanceModelParameters: the host's PHASE does not carry it\n");
        }

        // The subband parameter classes: each is a set of (frequency, level) pairs, and the directivity
        // gain for a band is the level of the band that frequency falls in.
        Class cardioidSubband = NSClassFromString(@"PHASECardioidDirectivityModelSubbandParameters");
        Class coneSubband = NSClassFromString(@"PHASEConeDirectivityModelSubbandParameters");
        if (cardioidSubband != Nil) {
            printf("stage the host's cardioid subband class: %s\n", NSStringFromClass(cardioidSubband).UTF8String);
            // A fresh cardioid subband holds three documented defaults: 1000.0, 0.0 and 1.0.
            id fresh = [[cardioidSubband alloc] init];
            checkClose(@"a fresh cardioid subband's frequency is the header's 1000.0",
                       [[fresh valueForKey:@"frequency"] doubleValue], 1000.0, 0.0);
            checkClose(@"a fresh cardioid subband's pattern is the header's 0.0",
                       [[fresh valueForKey:@"pattern"] doubleValue], 0.0, 0.0);
            checkClose(@"a fresh cardioid subband's sharpness is the header's 1.0",
                       [[fresh valueForKey:@"sharpness"] doubleValue], 1.0, 0.0);
        } else {
            printf("skip PHASECardioidDirectivityModelSubbandParameters: the host's PHASE does not carry it\n");
        }
        if (coneSubband != Nil) {
            printf("stage the host's cone subband class: %s\n", NSStringFromClass(coneSubband).UTF8String);
            // and four: 1000.0, 360.0, 360.0 and 1.0
            id fresh = [[coneSubband alloc] init];
            checkClose(@"a fresh cone subband's frequency is the header's 1000.0",
                       [[fresh valueForKey:@"frequency"] doubleValue], 1000.0, 0.0);
            checkClose(@"a fresh cone subband's inner angle is the header's 360.0",
                       [[fresh valueForKey:@"innerAngle"] doubleValue], 360.0, 0.0);
            checkClose(@"a fresh cone subband's outer angle is the header's 360.0",
                       [[fresh valueForKey:@"outerAngle"] doubleValue], 360.0, 0.0);
            checkClose(@"a fresh cone subband's outer gain is the header's 1.0",
                       [[fresh valueForKey:@"outerGain"] doubleValue], 1.0, 0.0);
        } else {
            printf("skip PHASEConeDirectivityModelSubbandParameters: the host's PHASE does not carry it\n");
        }

        compareDefaults();
        printf("checks=%d failures=%d\n", checks, failures);
    }
    return failures == 0 ? 0 : 1;
}
