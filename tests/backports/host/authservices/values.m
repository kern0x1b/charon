/* values -- what a fresh AuthenticationServices request holds, and what its copy holds, on both sides.
 *
 * Two builds of the same source, in one process:
 *
 *   the host's own classes, named as the SDK header names them, linked from
 *   AuthenticationServices.framework -- and
 *
 *   the port's classes, which this process never names: the port's own build renames them, so the test
 *   reaches them through NSClassFromString and the runtime. The rename is on the port's translation
 *   units only and never on this one -- a test compiled with the port's renames would be asking the
 *   port's version of the question and calling it the host's.
 *
 * What is asserted is the four properties a fresh OpenID request holds, the four its copy holds, and the
 * user an Apple ID request carries and its copy carries. The shape check cannot see any of this: it
 * reads the binary and asks whether a method is bound, and a value is not a method. This is the
 * instrument for a value claim, and the value mutant is a change here that this must notice.
 */
#import <Foundation/Foundation.h>
#import <AuthenticationServices/AuthenticationServices.h>
// After Foundation: the runtime header declares things in terms of NSString, and importing it first is
// an error that reads like a broken SDK rather than an include order.
#import <dlfcn.h>
#import <objc/runtime.h>
#include <objc/message.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* The port's classes, as the port's build names them. The renames are listed here so that a change to
 * them and a change here are the same change, and so that the two builds are visibly two builds. */
static const char *const kPortOpenID = "PortASAuthorizationOpenIDRequest";
static const char *const kPortAppleID = "PortASAuthorizationAppleIDRequest";

/* The value every fresh OpenID request holds, and the header's name for it. Read through the runtime on
 * the host side too, so that the two sides are asked the same way and a difference is a difference in
 * the port and not in how the question was put. */
static const char *const kImplicitOperation = "ASAuthorizationOperationImplicit";

static id ask(id target, const char *name)
{
    SEL selector = sel_registerName(name);
    if (![target respondsToSelector:selector]) {
        printf("  FAIL %s does not answer -%s\n", class_getName(object_getClass([target class])), name);
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static void set(id target, const char *name, id value)
{
    char setter[128];
    const char *upper = name;
    snprintf(setter, sizeof setter, "set%c%s:", (upper[0] >= 'a' && upper[0] <= 'z') ? (char)(upper[0] - 32) : upper[0],
             upper + 1);
    SEL selector = sel_registerName(setter);
    if (![target respondsToSelector:selector]) {
        printf("  FAIL %s does not answer -%s\n", class_getName(object_getClass([target class])), setter);
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
}

/* One side's answers, as text. A copy is made through -copyWithZone: exactly as an application would:
 * -copy on NSObject dispatches to it. */
static void report(const char *label, int onHost, id providerForThisSide, Class openID, Class appleID, id implicitOperation)
{
    // The two call targets for one selector, from the runtime: the class each side made its request
    // from, and the address -init is actually reached at on it. Two addresses are two call targets.
    Method initMethod = class_getInstanceMethod([openID class], sel_registerName("init"));
    printf("%s\n", label);
    printf("  built   request class          %s\n", class_getName(openID));
    printf("  built   -init imp            %p\n", initMethod ? (void *)method_getImplementation(initMethod) : (void *)0);
    // The host's request comes from its provider, which is the path the SDK gives and the one the
    // base's NS_UNAVAILABLE -init and +new are pointing at. The port's provider is not implemented yet,
    // so the port's request is made with [[cls alloc] init], which the port binds because its own
    // header does not mark it unavailable. Two constructors, one per side, and this says so.
    id request = onHost
        ? ((id (*)(id, SEL))objc_msgSend)(providerForThisSide, sel_registerName("createRequest"))
        : ((id (*)(id, SEL))objc_msgSend)(providerForThisSide, sel_registerName("createRequest"));
    if (!request) {
        printf("  FAIL no request could be made from %s\n", class_getName(openID));
        return;
    }
    if (!request) {
        printf("  FAIL no request could be made from %s\n", class_getName(openID));
        return;
    }
    printf("  fresh   requestedScopes        %s\n", ask(request, "requestedScopes") ? "set" : "nil");
    printf("  fresh   state                  %s\n", ask(request, "state") ? "set" : "nil");
    printf("  fresh   nonce                  %s\n", ask(request, "nonce") ? "set" : "nil");
    printf("  fresh   requestedOperation   %s\n", ask(request, "requestedOperation") ? "set" : "nil");

    set(request, "state", @"the state");
    set(request, "nonce", @"the nonce");
    set(request, "requestedScopes", (@[ @"fullName", @"email" ]));
    set(request, "requestedOperation", implicitOperation);

    id copy = ask(request, "copy");
    printf("  copy    requestedScopes         %s\n", ask(copy, "requestedScopes") ? "set" : "nil");
    printf("  copy    state                   %s\n", ask(copy, "state") ? "set" : "nil");
    printf("  copy    nonce                  %s\n", ask(copy, "nonce") ? "set" : "nil");
    printf("  copy    requestedOperation    %s\n", ask(copy, "requestedOperation") ? "set" : "nil");

    if (appleID) {
        id apple = onHost
            ? ((id (*)(id, SEL))objc_msgSend)(providerForThisSide, sel_registerName("createRequest"))
            : ((id (*)(id, SEL))objc_msgSend)(providerForThisSide, sel_registerName("createRequest"));
        if (!apple) {
            printf("  FAIL no request could be made from %s\n", class_getName(appleID));
            return;
        }
        printf("  fresh   user                   %s\n", ask(apple, "user") ? "set" : "nil");
        set(apple, "user", @"001234.abcdef.0000");
        id appleCopy = ask(apple, "copy");
        printf("  copy    user                    %s\n", ask(appleCopy, "user") ? "set" : "nil");
    }
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s <AuthenticationServices.framework>\n", argv[0]);
        return 2;
    }
    if (!dlopen(argv[1], RTLD_LAZY)) {
        fprintf(stderr, "%s: %s\n", argv[1], dlerror());
        return 1;
    }
    /* The implicit operation is the release's own extern, linked once and used as the value both
     * sides are asked against: a port that spelled its own would then be caught rather than agreeing
     * by writing the same string twice. */
    Class hostOpenID = objc_getClass("ASAuthorizationOpenIDRequest");
    Class hostApple = objc_getClass("ASAuthorizationAppleIDRequest");
    // The release owns this constant; reading it is enough and copying it is an ARC error.
    id hostImplicit = ASAuthorizationOperationImplicit;
    if (!hostOpenID || !hostImplicit) {
        fprintf(stderr, "the host's own classes or its implicit operation are not there\n");
        return 1;
    }
    id hostProvider = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(objc_getClass("ASAuthorizationAppleIDProvider"), sel_registerName("alloc")), sel_registerName("init"));
    if (!hostProvider) { fprintf(stderr, "the host provider could not be made\n"); return 1; }
    report("host", 1, hostProvider, hostOpenID, hostApple, hostImplicit);

    Class portOpenID = NSClassFromString([NSString stringWithUTF8String:kPortOpenID]);
    Class portApple = NSClassFromString([NSString stringWithUTF8String:kPortAppleID]);
    /* The port's operation is the same extern the host's is -- it is a value the release owns and the
     * constants check measures it -- so both sides are asked against the one value on purpose. */
    if (!portOpenID) {
        fprintf(stderr, "the port's %s is not linked into this test\n", kPortOpenID);
        return 1;
    }
    // The port's provider, made the way the port's provider is made: its own construction, because the
    // provider's superclass is NSObject and -init is not marked unavailable on it.
    id portProvider = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)
        (NSClassFromString([NSString stringWithUTF8String:"PortASAuthorizationAppleIDProvider"]), sel_registerName("alloc")),
        sel_registerName("init"));
    if (!portProvider) { fprintf(stderr, "the port's own provider could not be made\n"); return 1; }
    report("port", 0, portProvider, portOpenID, portApple, hostImplicit);
    return 0;
}
