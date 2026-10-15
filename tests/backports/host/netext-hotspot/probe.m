#import <Foundation/Foundation.h>
#import <dlfcn.h>
#if HOST_SIDE
#import <NetworkExtension/NetworkExtension.h>
#else
#import "CharonNEHotspot.h"
#endif

/* One operation per process (argv[1]), so a host crash or a hang is one line and not the whole run. */

static void wait_for(NSTimeInterval seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static void line(const char *name, id value)
{
    printf("%s\t%s\n", name, value ? [[value description] UTF8String] : "(nil)");
}

static void owner(const char *name, IMP imp)
{
    Dl_info info;
    const char *image = (imp && dladdr((const void *)imp, &info) && info.dli_fname) ? info.dli_fname : "(none)";
    printf("dladdr\t%s\t%s\n", name, strrchr(image, '/') ? strrchr(image, '/') + 1 : image);
}

static void network(void)
{
    NEHotspotNetwork *n = [[NEHotspotNetwork alloc] init];
    line("network.class", NSStringFromClass([n class]));
    printf("network.securityType\t%ld\n", (long)n.securityType);
    printf("network.signalStrength\t%g\n", n.signalStrength);
    printf("network.isSecure\t%d\n", n.isSecure);
    printf("network.didAutoJoin\t%d\n", n.didAutoJoin);
    printf("network.didJustJoin\t%d\n", n.didJustJoin);
    printf("network.isChosenHelper\t%d\n", n.isChosenHelper);
    [n setConfidence:kNEHotspotHelperConfidenceHigh];
    [n setPassword:@"pw"];
    printf("network.setters\tdone\n");
    line("network.SSID", n.SSID);
    line("network.BSSID", n.BSSID);
    owner("setConfidence", [n methodForSelector:@selector(setConfidence:)]);
    owner("setPassword", [n methodForSelector:@selector(setPassword:)]);
}

static void config(void)
{
    NEHotspotConfiguration *c = [[NEHotspotConfiguration alloc] initWithSSID:@"charon-probe"];
    line("config.SSID", c.SSID);
    line("config.SSIDPrefix", c.SSIDPrefix);
    printf("config.hidden\t%d\n", c.hidden);
    printf("config.joinOnce\t%d\n", c.joinOnce);
    line("config.lifeTimeInDays", c.lifeTimeInDays);
    NEHotspotConfiguration *p = [[NEHotspotConfiguration alloc] initWithSSIDPrefix:@"pre"];
    line("prefix.SSID", p.SSID);
    line("prefix.SSIDPrefix", p.SSIDPrefix);
    NEHotspotConfiguration *w = [[NEHotspotConfiguration alloc] initWithSSID:@"wep" passphrase:@"pw" isWEP:YES];
    line("wep.SSID", w.SSID);
    c.joinOnce = YES;
    c.hidden = YES;
    c.lifeTimeInDays = @5;
    printf("set.joinOnce\t%d\nset.hidden\t%d\n", c.joinOnce, c.hidden);
    line("set.lifeTimeInDays", c.lifeTimeInDays);
    NEHotspotConfiguration *copy = [c copy];
    printf("copy.isSameObject\t%d\n", copy == c);
    line("copy.class", NSStringFromClass([copy class]));
    printf("copy.joinOnce\t%d\ncopy.hidden\t%d\n", copy.joinOnce, copy.hidden);
    line("copy.lifeTimeInDays", copy.lifeTimeInDays);
    NSError *err = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:c requiringSecureCoding:YES error:&err];
    printf("archive.hasData\t%d\n", data != nil);
    line("archive.error", err);
    NEHotspotConfiguration *back = data ? [NSKeyedUnarchiver unarchivedObjectOfClass:[NEHotspotConfiguration class] fromData:data error:&err] : nil;
    line("roundTrip.class", NSStringFromClass([back class]));
    line("roundTrip.SSID", back.SSID);
    printf("roundTrip.joinOnce\t%d\nroundTrip.hidden\t%d\n", back.joinOnce, back.hidden);
    line("roundTrip.lifeTimeInDays", back.lifeTimeInDays);
    owner("initWithSSID", [NEHotspotConfiguration instanceMethodForSelector:@selector(initWithSSID:)]);
    owner("initWithSSIDPrefix", [NEHotspotConfiguration instanceMethodForSelector:@selector(initWithSSIDPrefix:)]);
}

static void fetch(void)
{
    owner("fetchCurrent", [NEHotspotNetwork methodForSelector:@selector(fetchCurrentWithCompletionHandler:)]);
    __block int calls = 0;
    __block id got = nil;
    __block int main = -1;
    __block BOOL returned = NO;
    __block int beforeReturn = -1;
    [NEHotspotNetwork fetchCurrentWithCompletionHandler:^(NEHotspotNetwork *current) {
        calls++;
        got = current;
        main = [NSThread isMainThread];
        beforeReturn = !returned;
    }];
    returned = YES;
    wait_for(3);
    printf("fetch.calls\t%d\n", calls);
    line("fetch.network", got);
    printf("fetch.onMainThread\t%d\n", main);
    printf("fetch.beforeReturn\t%d\n", beforeReturn);
}

#if HOST_SIDE
static void apply(void)
{
    NEHotspotConfiguration *c = [[NEHotspotConfiguration alloc] initWithSSID:@"charon-probe-no-such-ssid"];
    __block int calls = 0;
    __block NSError *err = nil;
    __block int main = -1;
    [[NEHotspotConfigurationManager sharedManager] applyConfiguration:c completionHandler:^(NSError *e) {
        calls++;
        err = e;
        main = [NSThread isMainThread];
    }];
    wait_for(5);
    printf("apply.calls\t%d\n", calls);
    printf("apply.errorDomain\t%s\n", err ? [err.domain UTF8String] : "(nil)");
    printf("apply.errorCode\t%ld\n", err ? (long)err.code : 0L);
    printf("apply.onMainThread\t%d\n", main);
}

static void configured(void)
{
    __block int calls = 0;
    __block id got = nil;
    [[NEHotspotConfigurationManager sharedManager] getConfiguredSSIDsWithCompletionHandler:^(NSArray<NSString *> *ssids) {
        calls++;
        got = ssids;
    }];
    wait_for(5);
    printf("configured.calls\t%d\n", calls);
    line("configured.ssids", got);
}

static void helper(void)
{
    __block int calls = 0;
    BOOL ok = [NEHotspotHelper registerWithOptions:nil queue:dispatch_get_main_queue() handler:^(NEHotspotHelperCommand *cmd) {
        calls++;
    }];
    wait_for(3);
    printf("register.returned\t%d\n", ok);
    printf("register.handlerCalls\t%d\n", calls);
    line("supportedNetworkInterfaces", [NEHotspotHelper supportedNetworkInterfaces]);
    printf("logoff.returned\t%d\n", [NEHotspotHelper logoff:[[NEHotspotNetwork alloc] init]]);
}

#endif /* HOST_SIDE: the manager and the helper are measured on the host only, until the join route is ruled on */

int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        const char *op = argc > 1 ? argv[1] : "";
        if (!strcmp(op, "network")) network();
        else if (!strcmp(op, "config")) config();
        else if (!strcmp(op, "fetch")) fetch();
#if HOST_SIDE
        else if (!strcmp(op, "apply")) apply();
        else if (!strcmp(op, "configured")) configured();
        else if (!strcmp(op, "helper")) helper();
#endif
        else { fprintf(stderr, "usage: probe network|config|fetch|apply|configured|helper\n"); return 2; }
    }
    return 0;
}
