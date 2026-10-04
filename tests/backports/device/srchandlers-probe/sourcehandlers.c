/* A barrier source's cancellation and registration handlers on the emulated iPhone3,1 at 6.1.3: the
   release's own calls beside this package's shims, one scenario per process.

   This is tests/compat_test.py's DISPATCH_SOURCE_HANDLERS program - the same case body, the same line
   format, the same readings, so the guest's answers can be laid beside the host's field by field - driven
   the way this guest has to be driven. Two things about the emulated iPhone3,1 at 6.1.3 (10B329) are
   measured, not assumed, and both are why:

     - `xmake emulate run` takes a bare path. A command with words after the path comes back
       `fail(spawn error 2)`, and the program is run with argc == 1 and nothing else: measured 2026-10-04
       with the same binary installed by the same deb, `/usr/libexec/sourcehandlers` prints
       `argc=1 argv0=/usr/libexec/sourcehandlers` while `/usr/libexec/sourcehandlers cancel concurrent
       system` never starts. So the scenario cannot be named on the command line here.
     - fork works. A child that does nothing, that prints, that makes a queue, that makes a barrier block,
       that makes a source and reads a record off it and that runs a dispatch_async and waits for it all
       exit 0 on this release; measured 2026-10-04, the six children in main's first loop. So with no
       arguments the process forks one child per scenario, which is what one scenario per process needs.

   The line is what the harness's parse() reads, so the keys are the same and in the same order, with one
   addition: `the target queue record`, which is what tells the two columns apart when the shims found
   nothing to work on. The harness's own check for it ("the two columns would agree because the shims did
   nothing") could not fire before, because nothing printed the phrase it looks for.

   A scenario whose child ends on a signal says so, and names the signal: WEXITSTATUS of a signalled child
   is 0, so a probe that reads only the exit status reports a clean end for a process that died. */

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "dispatch_source_state.h"

/* Cases, and what each asks of the target queue:

     cancel         a barrier cancellation handler, the source resumed, then cancelled.
     registration   a barrier registration handler, then resumed: the resume is what runs it.
     neverresumed   a barrier cancellation handler on a source that was never resumed, then cancelled.
     retargetbefore the source is made on one queue and handed another before the handler is set.
     retargetafter  the handler is set on one queue and the source handed another before the cancel.
     onqueue        the call is made from a block already running on the source's own target queue.
     resumecancel   a registration handler and a cancellation handler on one source, resumed and then
                    cancelled from off the queue, and the order the two ran in read out. gapMs is the wait
                    between the two calls, and it is a parameter because the release's own answer at gap 0
                    is a race and not a rule: measured on the host, gap 0 answers C alone and gap 1 answers
                    RC, because the resume submits the registration handler to the target queue and
                    returns, and a cancel that arrives before that submission has run discards it. The
                    guest asks it at 50 ms, which is where the host settles to RC on both widths.

   Every case but onqueue and resumecancel puts a block on the target queue that records that it started and
   does not return until told, so three things can be read:
     held   the call under test returned while that block was still running - that is, it did not wait
     ran    the handler ran at all, read after the holder has been let go and the call has been joined
     alone  the handler entered while that block was no longer running - that is, it ran alone, which a
            barrier queue gives and an ordinary one does not
   and second is which of the two queues the handler ran on, read from a specific this program puts on each
   queue with the call that names it (dispatch_queue_set_specific, iOS 5 and later, and not deprecated at
   any of this repository's deployment targets: measured 2026-10-04, compiling this file for
   armv7-apple-ios6.1.3 with -Wall -Wdeprecated-declarations and no diagnostic). The second queue is made
   the same width as the first, so "alone" means the same thing in every row.

   The onqueue case has no separate holder: the block that holds the target queue is the block the call is
   made from, which is the whole point of it, so "held" would be meaningless and what is read is whether
   the call returns at all. The holder signals a semaphore of its own when the call has returned and never
   the handler's, so the handler's answer cannot be the holder's.

   The call under test is made on a thread of its own and joined where there is a holder, so nothing here
   can hang the run, and nothing is released under a call that is still in it. Not a fork per scenario:
   the fork is in main, before any queue exists, so a child inherits no thread pool and creates its own -
   which is the whole reason a scenario is worth a process of its own, since a case recorded in another's
   answer is not an answer. The source is never released either, because libdispatch traps on releasing a
   source that was never resumed and neverresumed asks about one.

   system  the release's own calls, named as the SDK names them. No shim in this program defines a plain
           dispatch name, so the program's own dispatch_* calls reach the release whether or not a shim is
           linked in, and nothing renames them for it: the guest project compiles the shims exactly as
           packages/a/apple-compat/xmake.lua compiles them, one plain `clang -Os -fvisibility=hidden -c`
           with no forced include of the renaming headers. A forced include is what an image gets, so that
           the calls in the image bind to the shim; a shim's own call to the release must not see it, or
           dispatch_source_cancel.c calls itself, and the probe must not see it either, or its system
           column would reach the shim.
   shim    this package's six renamed shims, reached by the names their headers carry, and the source is
           made through charon_dispatch_source_create too: with the release's own dispatch_source_create
           there is no target queue record for the shims to find, and the two columns would then agree
           because the shims had done nothing. The line says whether that record is there.

   The handler is made through dispatch_block_create with DISPATCH_BLOCK_BARRIER, which on this release is
   this package's own call: dispatch_block_create arrived in iOS 8, and this package's reads the release's
   when there is one and makes the block itself when there is not, which is what puts the barrier bit
   where its own dispatch_block.h can read it. A plain block literal carries no such bit, so the shims
   would not see a barrier handler and would hand it to the release as it is, and the two columns would
   agree for the wrong reason. */

dispatch_source_t charon_dispatch_source_create(dispatch_source_type_t, uintptr_t, uintptr_t, dispatch_queue_t);
void charon_dispatch_resume(dispatch_object_t);
void charon_dispatch_set_target_queue(dispatch_object_t, dispatch_queue_t);
void charon_dispatch_source_set_cancel_handler(dispatch_source_t, dispatch_block_t);
void charon_dispatch_source_set_registration_handler(dispatch_source_t, dispatch_block_t);
void charon_dispatch_source_cancel(dispatch_source_t);

static volatile int holderInside;
static volatile int handlerAlone;
static volatile int handlerRan;
static volatile int handlerOnSecond;
static volatile int returned;
/* Which of the two handlers ran, and in which order, for the resumecancel case. A block literal cannot
   capture a char array, so both handlers append to this one. */
static char order[8];

static int useSystem;
static int registration;
static int never;
static int onQueue;
static int resumeCancel;
static int ordinaryAsync;
static dispatch_source_t source;
static dispatch_queue_t second;
static dispatch_queue_t held;
static dispatch_semaphore_t handlerDone;
static const char *width;
static int record;
/* Where an answer goes. It is stdout when this program is run with a scenario named on the command line,
   and it is the writing end of a pipe when it is run on this guest with no arguments at all: a forked
   child's writes to this guest's standard output do not reach the runner's capture, which is measured - on
   2026-10-04 twelve children each printed exactly one line and exited 0, and every one of the parent's own
   lines arrived while not one of theirs did. So the child answers through a pipe and the parent, whose own
   output does arrive, reads it and prints it. */
static FILE *answers;

static void tag(dispatch_queue_t queue, const void *value)
{
    /* dispatch_queue_set_specific is what names the queue a block runs on. */
    dispatch_queue_set_specific(queue, (const void *)0x636861726f6e51u, (void *)value, NULL);
}

static void *where(void)
{
    return dispatch_get_specific((const void *)0x636861726f6e51u);
}

static void *make_source(dispatch_queue_t queue)
{
    return useSystem ? dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue)
                     : charon_dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
}

static void set_cancel(dispatch_source_t target, dispatch_block_t handler)
{
    if (useSystem)
        dispatch_source_set_cancel_handler(target, handler);
    else
        charon_dispatch_source_set_cancel_handler(target, handler);
}

static void set_registration(dispatch_source_t target, dispatch_block_t handler)
{
    if (useSystem)
        dispatch_source_set_registration_handler(target, handler);
    else
        charon_dispatch_source_set_registration_handler(target, handler);
}

static void retarget(dispatch_object_t target, dispatch_queue_t queue)
{
    if (useSystem)
        dispatch_set_target_queue(target, queue);
    else
        charon_dispatch_set_target_queue(target, queue);
}

static void resume_it(dispatch_object_t target)
{
    if (useSystem)
        dispatch_resume(target);
    else
        charon_dispatch_resume(target);
}

static void cancel_it(dispatch_source_t target)
{
    if (useSystem)
        dispatch_source_cancel(target);
    else
        charon_dispatch_source_cancel(target);
}

static void call_under_test(void)
{
    if (registration)
        resume_it(source);
    else
        cancel_it(source);
    returned = 1;
}

/* The control for the ordinaryasync case: an ordinary block submitted to the target queue, from a thread of
   its own, where every other case puts a source's handler there. `held` and `handlerDone` are file scope
   because a block literal cannot capture them out of the function that made them, and this program runs
   one scenario per process anyway. */
static void *ordinary_runner(void *ignored)
{
    (void)ignored;
    dispatch_async(held, ^{
        handlerAlone = holderInside ? 0 : 1;
        handlerRan = 1;
        dispatch_semaphore_signal(handlerDone);
    });
    returned = 1;
    return NULL;
}

static void *runner(void *ignored)
{
    (void)ignored;
    call_under_test();
    return NULL;
}

static void say(const char *which, const char *held, const char *ran)
{
    fprintf(answers, "%s %s %s: held=%s ran=%s alone=%s second=%s returned=%s order=%s%s\n", which, width,
            useSystem ? "system" : "shim", held, ran,
            handlerAlone < 0 ? "n/a" : (handlerAlone ? "yes" : "no"),
            handlerOnSecond < 0 ? "n/a" : (handlerOnSecond ? "yes" : "no"),
            returned ? "yes" : "no", order[0] ? order : "-",
            record < 0 ? "" : (record ? " the target queue record: yes" : " the target queue record: NO"));
}

/* One scenario. The scenario is named by the arguments when there are any, which is how the host
   differential runs this same program; on this guest there are none, and main forks one child per
   scenario and calls this in the child with the arguments it would have been given. */
static int scenario(int argc, char **argv)
{
    const char *which = argc > 1 ? argv[1] : "cancel";
    width = argc > 2 && strcmp(argv[2], "serial") == 0 ? "serial" : "concurrent";
    useSystem = argc > 3 && strcmp(argv[3], "system") == 0;
    int gapMs = argc > 4 ? atoi(argv[4]) : 0;
    registration = strcmp(which, "registration") == 0;
    never = strcmp(which, "neverresumed") == 0;
    int retargetBefore = strcmp(which, "retargetbefore") == 0;
    int retargetAfter = strcmp(which, "retargetafter") == 0;
    onQueue = strcmp(which, "onqueue") == 0;
    resumeCancel = strcmp(which, "resumecancel") == 0;
    ordinaryAsync = strcmp(which, "ordinaryasync") == 0;

    holderInside = 0;
    handlerAlone = -1;
    handlerRan = 0;
    handlerOnSecond = -1;
    returned = 0;
    order[0] = 0;

    dispatch_queue_attr_t attr = strcmp(width, "serial") == 0 ? DISPATCH_QUEUE_SERIAL : DISPATCH_QUEUE_CONCURRENT;
    dispatch_queue_t queue = dispatch_queue_create("target", attr);
    second = dispatch_queue_create("second", attr);
    tag(queue, (const void *)1);
    tag(second, (const void *)2);
    source = (dispatch_source_t)make_source(queue);
    int firstIsTarget = 1;

    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    dispatch_semaphore_t release = dispatch_semaphore_create(0);
    handlerDone = dispatch_semaphore_create(0);
    dispatch_block_t handler = dispatch_block_create(DISPATCH_BLOCK_BARRIER, ^{
        handlerAlone = holderInside ? 0 : 1;
        handlerRan = 1;
        handlerOnSecond = where() == (void *)2 ? 1 : 0;
        if (resumeCancel) {
            size_t length = strlen(order);
            if (length + 1 < sizeof order) {
                order[length] = 'C';
                order[length + 1] = 0;
            }
        }
        dispatch_semaphore_signal(handlerDone);
    });

    if (retargetBefore) {
        retarget(source, second);
        firstIsTarget = 0;
    }
    if (registration) {
        set_registration(source, handler);
    } else {
        set_cancel(source, handler);
        /* resumecancel makes the resume itself, with a cancel straight after it, and a second resume on a
           running source traps in _dispatch_lane_resume. */
        if (!never && !resumeCancel)
            resume_it(source);
    }
    if (retargetAfter) {
        retarget(source, second);
        firstIsTarget = 0;
    }
    record = useSystem ? -1 : (charon_source_target(source) != NULL ? 1 : 0);

    if (resumeCancel) {
        dispatch_block_t registration_handler = dispatch_block_create(DISPATCH_BLOCK_BARRIER, ^{
            size_t length = strlen(order);
            if (length + 1 < sizeof order) {
                order[length] = 'R';
                order[length + 1] = 0;
            }
        });
        set_registration(source, registration_handler);
        set_cancel(source, handler);
        resume_it(source);
        if (gapMs > 0)
            usleep((useconds_t)gapMs * 1000);
        cancel_it(source);
        for (int waited = 0; waited < 3000 && strlen(order) < 2; waited++)
            usleep(1000);
        say(which, "n/a", strlen(order) > 1 ? "yes" : "no");
        return 0;
    }

    held = firstIsTarget ? queue : second;
    if (onQueue) {
        dispatch_semaphore_t callReturned = dispatch_semaphore_create(0);
        dispatch_async(held, ^{
            holderInside = 1;
            dispatch_semaphore_signal(entered);
            dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
            holderInside = 0;
            call_under_test();
            dispatch_semaphore_signal(callReturned);
        });
        dispatch_semaphore_wait(entered, DISPATCH_TIME_FOREVER);
        dispatch_semaphore_signal(release);
        long called = dispatch_semaphore_wait(callReturned, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
        dispatch_semaphore_wait(handlerDone, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
        say(which, "n/a", handlerRan ? "yes" : "no");
        return called ? 1 : 0;
    }

    dispatch_async(held, ^{
        holderInside = 1;
        dispatch_semaphore_signal(entered);
        dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
        holderInside = 0;
    });
    dispatch_semaphore_wait(entered, DISPATCH_TIME_FOREVER);

    /* The control every `alone` reading on this guest is read against: the same holder in the same target
       queue, and an ORDINARY block submitted to it where every other case submits a source's handler. An
       ordinary block on a concurrent queue runs beside the holder, so this answers alone=no; if it answered
       alone=yes then this queue runs one block at a time and `alone` would say nothing about a barrier on
       this guest, in either column. */
    pthread_t thread;
    pthread_create(&thread, NULL, ordinaryAsync ? ordinary_runner : runner, NULL);
    for (int waited = 0; waited < 2000 && !returned; waited++)
        usleep(1000);
    int returnedWhileHeld = returned;
    dispatch_semaphore_signal(release);
    pthread_join(thread, NULL);
    long ranLater = dispatch_semaphore_wait(handlerDone, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    say(which, returnedWhileHeld ? "yes" : "no", (ranLater == 0 || handlerRan) ? "yes" : "no");
    return 0;
}

/* The one place the two hosts differ, so it is here and not scattered through the program: on the host
   the arguments name the scenario and this runs once, answering on stdout; on this guest there are none, so
   one child per scenario is forked, the child answers on a pipe and this reads it back and prints it.
   WEXITSTATUS of a signalled child is 0, so a child's status is read with WIFSIGNALED and WTERMSIG, and a
   child that died is reported as the signal it died of rather than as a clean end. The fork is before any
   queue exists, so a child inherits no thread pool and creates its own, and it exits with _exit because the
   atexit handlers of a forked child are not this child's to run. */
int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    answers = stdout;
    printf("the guest reports %ld processors, and OS_dispatch_source is %s\n",
           sysconf(_SC_NPROCESSORS_ONLN), objc_getClass("OS_dispatch_source") ? "present" : "ABSENT");
    if (argc >= 4)
        return scenario(argc, argv);

    static const char *cases[] = {"cancel", "registration", "neverresumed", "retargetbefore",
                                  "retargetafter", "onqueue", "resumecancel", "ordinaryasync"};
    static const char *widths[] = {"concurrent", "serial"};
    for (unsigned c = 0; c < sizeof cases / sizeof cases[0]; c++) {
        for (unsigned w = 0; w < sizeof widths / sizeof widths[0]; w++) {
            for (int api = 0; api < 2; api++) {
                char *arguments[] = {argv[0], (char *)cases[c], (char *)widths[w],
                                     (char *)(api ? "shim" : "system"), (char *)"50", NULL};
                int ends[2];
                if (pipe(ends) != 0) {
                    printf("%s %s %s: PIPE FAILED\n", cases[c], widths[w], api ? "shim" : "system");
                    continue;
                }
                fflush(stdout);
                pid_t child = fork();
                if (child == 0) {
                    close(ends[0]);
                    answers = fdopen(ends[1], "w");
                    if (answers)
                        setvbuf(answers, NULL, _IONBF, 0);
                    int code = scenario(5, arguments);
                    if (answers)
                        fflush(answers);
                    _exit(code);
                }
                close(ends[1]);
                if (child < 0) {
                    close(ends[0]);
                    printf("%s %s %s: FORK FAILED\n", cases[c], widths[w], api ? "shim" : "system");
                    continue;
                }
                int status = 0;
                waitpid(child, &status, 0);
                /* What the child answered, read to the end of its pipe: a child that ended on a signal has
                   closed it, so this is empty for one, which is how "no answer" is told from an answer. */
                FILE *reader = fdopen(ends[0], "r");
                char line[512];
                if (reader) {
                    while (fgets(line, sizeof line, reader))
                        fputs(line, stdout);
                    fclose(reader);
                }
                close(ends[0]);
                if (WIFSIGNALED(status))
                    printf("%s %s %s: CHILD ENDED ON SIGNAL %d (%s), no answer\n", cases[c], widths[w],
                           api ? "shim" : "system", WTERMSIG(status), strsignal(WTERMSIG(status)));
                else if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
                    printf("%s %s %s: CHILD ENDED status=%d\n", cases[c], widths[w],
                           api ? "shim" : "system", WEXITSTATUS(status));
            }
        }
    }
    return 0;
}