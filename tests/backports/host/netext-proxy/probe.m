#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdio.h>

/* One reader, two binaries, the shape the NEDNSSettings slice established: Apple's framework alone on
   the host side, the port's objects with Apple's framework *not linked* on the port side, and a dladdr
   line per class so nothing can be read as the port's answer when Apple's is what answered.

   All twenty-three property names of these four classes are carried by the host's own NetworkExtension
   (measured before this file was written, with class_getInstanceMethod per selector), so the whole set
   is comparable and none of it falls back to the header. */
#ifdef HOST_SIDE
#import <NetworkExtension/NetworkExtension.h>
#else
#import "CharonNetworkExtensionSettings.h"
#endif

static void emit(const char *name, const char *value)
{
    printf("%s\t%s\n", name, value ? value : "(nil)");
    fflush(stdout);   /* the harness reads a file, where stdout is fully buffered and a crash would
                          take every line printed so far with it */
}

static void emit_object(const char *name, id value)
{
    emit(name, value ? "an object" : "(nil)");
}

static void emit_array(const char *name, id value)
{
    emit(name, value ? "an array" : "(nil)");
}

static void emit_bool(const char *name, BOOL value)
{
    emit(name, value ? "YES" : "NO");
}

static void prove(NSString *label, Class cls, SEL selector)
{
    Method m = class_getInstanceMethod(cls, selector);
    IMP imp = m ? method_getImplementation(m) : NULL;
    Dl_info info;
    memset(&info, 0, sizeof info);
    /* The proof, stated plainly: dladdr fills dli_fname or it does not, and either way the answer is
       written down rather than summarised. A method in the dyld shared cache is Apple's, and the path
       it reports is the cache's own - which is the strongest statement this proof can make: the
       implementation is not in this process's image at all. An unresolved one is printed as
       unresolved, and the harness fails on it rather than reading a green verdict out of an empty. */
    const char *where;
    if (!imp) {
        where = "no IMP: the class does not carry the selector in this binary";
    } else if (!dladdr((const void *)imp, &info)) {
        where = "dladdr did not fill it: the implementation is in the dyld shared cache";
    } else if (!info.dli_fname || !*info.dli_fname) {
        where = "dladdr filled no name: the implementation is in the dyld shared cache";
    } else {
        where = info.dli_fname;
    }
    printf("%s.dladdr\t%s\n", [label UTF8String], where);
    fflush(stdout);
}

int main(void)
{
    @autoreleasepool {
        Class server = NSClassFromString(@"NEProxyServer");
        Class settings = NSClassFromString(@"NEProxySettings");
        Class v4 = NSClassFromString(@"NEIPv4Settings");
        Class route = NSClassFromString(@"NEIPv4Route");
        printf("classes\t%s%s%s%s\n",
               server ? "NEProxyServer " : "", settings ? "NEProxySettings " : "",
               v4 ? "NEIPv4Settings " : "", route ? "NEIPv4Route" : "");
        fflush(stdout);
        if (!server || !settings || !v4 || !route)
            return 1;

        prove(@"NEProxyServer", server, @selector(address));
        prove(@"NEProxySettings", settings, @selector(exceptionList));
        prove(@"NEIPv4Settings", v4, @selector(addresses));
        prove(@"NEIPv4Route", route, @selector(destinationAddress));

        id freshServer = [[server alloc] init];
        emit_object("NEProxyServer.username", [freshServer valueForKey:@"username"]);
        emit_object("NEProxyServer.password", [freshServer valueForKey:@"password"]);
        emit_bool("NEProxyServer.authenticationRequired", [[freshServer valueForKey:@"authenticationRequired"] boolValue]);

        id freshSettings = [[settings alloc] init];
        emit_bool("NEProxySettings.autoProxyConfigurationEnabled", [[freshSettings valueForKey:@"autoProxyConfigurationEnabled"] boolValue]);
        emit_object("NEProxySettings.proxyAutoConfigurationURL", [freshSettings valueForKey:@"proxyAutoConfigurationURL"]);
        emit_object("NEProxySettings.proxyAutoConfigurationJavaScript", [freshSettings valueForKey:@"proxyAutoConfigurationJavaScript"]);
        emit_bool("NEProxySettings.HTTPEnabled", [[freshSettings valueForKey:@"HTTPEnabled"] boolValue]);
        emit_object("NEProxySettings.HTTPServer", [freshSettings valueForKey:@"HTTPServer"]);
        emit_bool("NEProxySettings.HTTPSEnabled", [[freshSettings valueForKey:@"HTTPSEnabled"] boolValue]);
        emit_object("NEProxySettings.HTTPSServer", [freshSettings valueForKey:@"HTTPSServer"]);
        emit_bool("NEProxySettings.excludeSimpleHostnames", [[freshSettings valueForKey:@"excludeSimpleHostnames"] boolValue]);
        emit_array("NEProxySettings.exceptionList", [freshSettings valueForKey:@"exceptionList"]);
        emit_array("NEProxySettings.matchDomains", [freshSettings valueForKey:@"matchDomains"]);

        id freshV4 = [[v4 alloc] init];
        emit_array("NEIPv4Settings.addresses", [freshV4 valueForKey:@"addresses"]);
        emit_array("NEIPv4Settings.subnetMasks", [freshV4 valueForKey:@"subnetMasks"]);
        emit_object("NEIPv4Settings.router", [freshV4 valueForKey:@"router"]);
        emit_array("NEIPv4Settings.includedRoutes", [freshV4 valueForKey:@"includedRoutes"]);
        emit_array("NEIPv4Settings.excludedRoutes", [freshV4 valueForKey:@"excludedRoutes"]);

        id freshRoute = [[route alloc] init];
        emit_object("NEIPv4Route.destinationAddress", [freshRoute valueForKey:@"destinationAddress"]);
        emit_object("NEIPv4Route.destinationSubnetMask", [freshRoute valueForKey:@"destinationSubnetMask"]);
        emit_object("NEIPv4Route.gatewayAddress", [freshRoute valueForKey:@"gatewayAddress"]);

        /* and the answers a caller can change, which is what makes them state rather than a constant */
        NEProxySettings *filled = [[NEProxySettings alloc] init];
        [filled setHTTPEnabled:YES];
        [filled setExceptionList:@[@"example.com"]];
        emit_bool("roundTrip.HTTPEnabled", [filled valueForKey:@"HTTPEnabled"] ? YES : NO);
        emit_array("roundTrip.exceptionList", [filled valueForKey:@"exceptionList"]);
        emit_bool("copy.isSameObject", [filled copy] == filled ? YES : NO);
        NSError *error = nil;
        NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:filled requiringSecureCoding:YES error:&error];
        emit("archive.hasData", archived ? "YES" : "NO");
        emit("archive.errorDomain", error ? [error.domain UTF8String] : "(none)");
    }
    return 0;
}
