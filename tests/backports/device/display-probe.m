// display-probe.m - does a bare process (no UIApplicationMain) have a display, by the public routes, and what does a display
// link do there? Prints [UIScreen mainScreen], [UIScreen screens].count, the private +[CADisplay mainDisplay] that
// dynamics-watch.m used to decide with (for comparison only), and then, last because it may fault, one display link:
//     display-probe screen   -[UIScreen displayLinkWithTarget:selector:] (public since 4.0)
//     display-probe class    +[CADisplayLink displayLinkWithTarget:selector:]
// With a second argument `view` a UIView with a subview is made first, as dynamics-watch.m does before its animators start a
// link: whether a layer tree in the process changes what the display and the link do.
// A fault is caught to print the image, the offset in it and the fault address (the run's own verdict has only the pc), and the
// process exits 139. Built as a daemon target (`add_rules("@addon/charon/daemon")`, Foundation, UIKit, QuartzCore) and run with
// `xmake emulate -d iPhone3,1 -r 4.3 run /usr/libexec/display-probe screen`.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <signal.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>
#import <sys/ucontext.h>

@interface Ticker : NSObject
- (void)tick:(CADisplayLink *)link;
@end

@implementation Ticker
- (void)tick:(CADisplayLink *)link
{
}
@end

static void say(const char *text)
{
    write(STDOUT_FILENO, text, strlen(text));
}

static void locate(const char *what, uintptr_t address)
{
    Dl_info info;
    char line[512];
    if (dladdr((void *)address, &info) && info.dli_fname)
        snprintf(line, sizeof line, "  %s 0x%lx: image %s, base 0x%lx, offset +0x%lx, symbol %s\n", what, (unsigned long)address, info.dli_fname,
                 (unsigned long)info.dli_fbase, (unsigned long)(address - (uintptr_t)info.dli_fbase), info.dli_sname ? info.dli_sname : "(none)");
    else
        snprintf(line, sizeof line, "  %s 0x%lx: no image\n", what, (unsigned long)address);
    say(line);
}

static void fault(int signal_number, siginfo_t *info, void *context)
{
    ucontext_t *uc = context;
    char line[128];
    snprintf(line, sizeof line, "FAULT signal %d, fault address 0x%lx\n", signal_number, (unsigned long)info->si_addr);
    say(line);
    locate("pc", (uintptr_t)uc->uc_mcontext->__ss.__pc);
    locate("lr", (uintptr_t)uc->uc_mcontext->__ss.__lr);
    _exit(139);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        BOOL screen = argc > 1 && strcmp(argv[1], "screen") == 0;
        printf("display probe: %s, mode %s%s\n", [[[UIDevice currentDevice] systemVersion] UTF8String], argc > 1 ? argv[1] : "(none)", argc > 2 ? [[NSString stringWithFormat:@" %s", argv[2]] UTF8String] : "");
        UIView *superview = nil;
        if (argc > 2 && strcmp(argv[2], "view") == 0) {
            superview = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 600, 800)];
            [superview addSubview:[[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 400)]];
            printf("a UIView with a subview made first\n");
        }
        UIScreen *main = [UIScreen mainScreen];
        printf("UIScreen mainScreen: %s\n", main ? [[main description] UTF8String] : "nil");
        printf("UIScreen screens: count %lu\n", (unsigned long)[[UIScreen screens] count]);
        Class display = NSClassFromString(@"CADisplay");
        id mainDisplay = [display respondsToSelector:@selector(mainDisplay)] ? [display performSelector:@selector(mainDisplay)] : nil;
        printf("private +[CADisplay mainDisplay]: %s\n", display ? (mainDisplay ? "an object" : "nil") : "no such class");
        printf("next: %s\n", screen ? "-[UIScreen displayLinkWithTarget:selector:]" : "+[CADisplayLink displayLinkWithTarget:selector:]");
        fflush(stdout);

        struct sigaction action;
        memset(&action, 0, sizeof action);
        action.sa_sigaction = fault;
        action.sa_flags = SA_SIGINFO;
        sigaction(SIGSEGV, &action, NULL);
        sigaction(SIGBUS, &action, NULL);

        Ticker *ticker = [Ticker new];
        CADisplayLink *link = screen ? [main displayLinkWithTarget:ticker selector:@selector(tick:)]
                                     : [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        printf("display link: %s\n", link ? "an object" : "nil");
        (void)superview;
    }
    return 0;
}
