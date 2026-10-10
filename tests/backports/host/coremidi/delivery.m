// The in-process deliveries of this library's destinations against the dispose of their endpoint, on the host's own CoreMIDI
// (process-lifetime virtual endpoints; nothing persists, which prefs-bracket.sh checks). The release's destinations run nothing
// after their dispose has returned; a destination this library made must not either. Two cases are measured: test E (one delivery
// blocked inside its call, two queued behind it, and the dispose issued while the first is blocked), and the trials (a burst of
// messages, then a dispose, counted over 1000 trials). The release's own destination is the control of test E: its dispose waits for
// the blocked call, and nothing runs after it.
#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#import "CharonCoreMIDI.h"

static int gFailures;
static MIDIClientRef gClient;
static MIDIPortRef gOut;
static double gNsPerTick;

static void expect(int passed, const char *what, long value)
{
    printf("%s %s (%ld)\n", passed ? "ok" : "FAIL", what, value);
    if (!passed)
        gFailures++;
}

// What the receive procedures record: the calls begun, the calls begun after the dispose returned, and how long after it the latest
// such call began. The dispose time is set by the disposing thread when its dispose has returned (0 before that).
typedef struct {
    dispatch_semaphore_t entered;
    dispatch_semaphore_t go;
    long started;
    long afterDispose;
    uint64_t lateMax;
    uint64_t disposed;
    int armed;
    uint32_t holdMicros;
} probe_state;
static probe_state gP;

static void record_call(void)
{
    uint64_t now = mach_absolute_time();
    __atomic_add_fetch(&gP.started, 1, __ATOMIC_ACQ_REL);
    uint64_t disposed = __atomic_load_n(&gP.disposed, __ATOMIC_ACQUIRE);
    if (disposed && now > disposed) {
        __atomic_add_fetch(&gP.afterDispose, 1, __ATOMIC_ACQ_REL);
        uint64_t late = now - disposed;
        uint64_t seen = __atomic_load_n(&gP.lateMax, __ATOMIC_ACQUIRE);
        while (late > seen && !__atomic_compare_exchange_n(&gP.lateMax, &seen, late, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
            ;
    }
    if (__atomic_exchange_n(&gP.armed, 0, __ATOMIC_ACQ_REL)) {
        dispatch_semaphore_signal(gP.entered);
        dispatch_semaphore_wait(gP.go, DISPATCH_TIME_FOREVER);
    }
    if (gP.holdMicros)
        usleep(gP.holdMicros);
}

static void library_receive(const MIDIEventList *list, void *refCon)
{
    (void)list;
    (void)refCon;
    record_call();
}

static void release_read(const MIDIPacketList *packets, void *refCon, void *srcConnRefCon)
{
    (void)packets;
    (void)refCon;
    (void)srcConnRefCon;
    record_call();
}

// The disposing thread: it disposes, and records when the dispose returned.
typedef struct {
    MIDIEndpointRef endpoint;
    OSStatus status;
} disposer;

static void *dispose_thread(void *argument)
{
    disposer *d = argument;
    d->status = MIDIEndpointDispose(d->endpoint);
    __atomic_store_n(&gP.disposed, mach_absolute_time(), __ATOMIC_RELEASE);
    return NULL;
}

// One 2.0 note, as a list of one packet, for the library's sends.
static MIDIEventList *note(uint8_t *storage, size_t size)
{
    MIDIEventList *list = (MIDIEventList *)storage;
    MIDIEventPacket *end = MIDIEventListInit(list, kMIDIProtocol_2_0);
    UInt32 words[2] = {0x40903C00u, 0xFFFF0000u};
    CharonMIDIEventListAdd(list, size, end, 0, 2, words);
    return list;
}

static void reset_probe(void)
{
    gP.started = 0;
    gP.afterDispose = 0;
    gP.lateMax = 0;
    gP.disposed = 0;
    gP.armed = 0;
    gP.holdMicros = 0;
}

// Test E: the first delivery is blocked inside its call; two more are queued behind it; the dispose is issued and returns (for the
// library) or waits for the blocked call (for the release); then the blocked call is released. The queued deliveries must not run after
// the dispose has returned.
static void test_e(int library)
{
    reset_probe();
    gP.entered = dispatch_semaphore_create(0);
    gP.go = dispatch_semaphore_create(0);
    gP.armed = 1;
    MIDIEndpointRef dest = 0;
    OSStatus status;
    if (library)
        status = CharonMIDIDestination(gClient, CFSTR("delivery-e"), kMIDIProtocol_2_0, &dest, ^(const MIDIEventList *list, void *refCon) {
            library_receive(list, refCon);
        });
    else
        status = MIDIDestinationCreate(gClient, CFSTR("delivery-e-release"), release_read, NULL, &dest);
    if (status != noErr) {
        expect(0, library ? "E: the library's destination is made" : "E: the release's destination is made", status);
        return;
    }
    uint8_t storage[64] __attribute__((aligned(8)));
    MIDIEventList *list = note(storage, sizeof(storage));
    Byte bytes[3] = {0x90, 60, 100};
    uint8_t packetStorage[64] __attribute__((aligned(8)));
    MIDIPacketList *packets = (MIDIPacketList *)packetStorage;
    MIDIPacketListAdd(packets, sizeof(packetStorage), MIDIPacketListInit(packets), 0, 3, bytes);
    for (int i = 0; i < 3; i++) {
        if (library)
            CharonMIDISend(gOut, dest, list);
        else
            MIDISend(gOut, dest, packets);
    }
    long waited = dispatch_semaphore_wait(gP.entered, dispatch_time(DISPATCH_TIME_NOW, 3LL * NSEC_PER_SEC));
    if (waited != 0) {
        expect(0, library ? "E library: the first delivery is inside its call" : "E release: the first call is inside its read", 0);
        return;
    }
    disposer d = {dest, noErr};
    pthread_t thread;
    pthread_create(&thread, NULL, dispose_thread, &d);
    // The blocked call is held for 20 ms after the dispose is issued: longer than one drain pass (one millisecond), so a queued
    // delivery that follows it is checked again. The library's dispose returns during the hold; the release's waits for the call.
    usleep(20000);
    dispatch_semaphore_signal(gP.go);
    pthread_join(thread, NULL);
    usleep(200000);
    const char *name = library ? "E library" : "E release (control)";
    printf("%s: calls begun %ld; begun after the dispose returned %ld; dispose status %d\n", name, gP.started, gP.afterDispose, (int)d.status);
    expect(gP.afterDispose == 0, library ? "E library: no delivery begins after its dispose returned" : "E release: no read begins after the dispose returned",
           gP.afterDispose);
    if (library)
        expect(gP.started == 1, "E library: the two queued deliveries are not called (the one blocked call is)", gP.started);
}

// Waits until a call has begun (the first of a burst), so that the dispose is issued while the deliveries behind it are queued.
static int wait_started(void)
{
    for (int i = 0; i < 30000; i++) {
        if (__atomic_load_n(&gP.started, __ATOMIC_ACQUIRE) > 0)
            return 1;
        usleep(100);
    }
    return 0;
}

// The trials: a burst of four messages to a destination, the dispose issued once its first call has begun, over 1000 trials. Each
// call holds for one millisecond, so three deliveries are queued behind the first. Counted: the calls begun, and those begun after the
// dispose returned. The first call of each trial begins before the dispose, so the count of calls is 1000 when the queue is served as it
// should be.
static void test_trials(void)
{
    long started = 0;
    long afterDispose = 0;
    long began = 0;
    for (int trial = 0; trial < 1000; trial++) {
        reset_probe();
        gP.holdMicros = 1000;
        MIDIEndpointRef dest = 0;
        if (CharonMIDIDestination(gClient, CFSTR("delivery-trial"), kMIDIProtocol_2_0, &dest, ^(const MIDIEventList *list, void *refCon) {
                library_receive(list, refCon);
            }) != noErr) {
            expect(0, "trials: the library's destination is made", trial);
            return;
        }
        uint8_t storage[64] __attribute__((aligned(8)));
        MIDIEventList *list = note(storage, sizeof(storage));
        for (int i = 0; i < 4; i++)
            CharonMIDISend(gOut, dest, list);
        began += wait_started();
        disposer d = {dest, noErr};
        dispose_thread(&d);
        usleep(8000);
        started += gP.started;
        afterDispose += gP.afterDispose;
    }
    printf("trials: 1000 trials of 4 messages; first calls begun %ld; calls begun %ld; begun after the dispose returned %ld\n",
           began, started, afterDispose);
    expect(began == 1000, "trials: the first call of every trial begins before its dispose", began);
    expect(afterDispose == 0, "trials: no delivery begins after its destination's dispose returned, in 1000 trials", afterDispose);
}

// The window of the shared check: fast calls, so a drain pass runs many deliveries. A call that begins after the dispose returned is
// one whose check was made in the pass that began before the dispose; the pass is at most one millisecond long (the call that crosses
// it included), so the latest such call begins well within two milliseconds of the dispose.
static void test_window(void)
{
    long began = 0;
    long started = 0;
    long afterDispose = 0;
    uint64_t late = 0;
    for (int trial = 0; trial < 200; trial++) {
        reset_probe();
        MIDIEndpointRef dest = 0;
        if (CharonMIDIDestination(gClient, CFSTR("delivery-window"), kMIDIProtocol_2_0, &dest, ^(const MIDIEventList *list, void *refCon) {
                library_receive(list, refCon);
            }) != noErr) {
            expect(0, "window: the library's destination is made", trial);
            return;
        }
        uint8_t storage[64] __attribute__((aligned(8)));
        MIDIEventList *list = note(storage, sizeof(storage));
        for (int i = 0; i < 32; i++)
            CharonMIDISend(gOut, dest, list);
        began += wait_started();
        disposer d = {dest, noErr};
        dispose_thread(&d);
        usleep(4000);
        started += gP.started;
        afterDispose += gP.afterDispose;
        if (gP.lateMax > late)
            late = gP.lateMax;
    }
    double lateMs = (double)late * gNsPerTick / 1000000.0;
    printf("window: 200 trials of 32 fast messages; first calls begun %ld; calls begun %ld; begun after the dispose returned %ld; latest such call %.3f ms after it\n",
           began, started, afterDispose, lateMs);
    expect(began == 200, "window: the first call of every trial begins before its dispose (so the window is measured)", began);
    expect(lateMs < 2.0, "window: the latest call begun after a dispose is within two milliseconds of it", (long)(lateMs * 1000));
}

int main(void)
{
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    gNsPerTick = (double)timebase.numer / (double)timebase.denom;
    if (MIDIClientCreate(CFSTR("delivery"), NULL, NULL, &gClient) != noErr || MIDIOutputPortCreate(gClient, CFSTR("delivery-out"), &gOut) != noErr) {
        printf("FAIL the client and its output port are made\n");
        return 1;
    }
    test_e(1);
    test_e(0);
    test_trials();
    test_window();
    printf("delivery: %d failures\n", gFailures);
    return gFailures ? 1 : 0;
}
