// The protocol-aware ports and endpoints, and the list sends, of the iOS 14 API, as internal functions: the
// functions MIDIProtocol14.m exports call these, and so do the iOS 18 classes (MIDIUMP18.m), which build on the
// same endpoints. This file exports no API name: every function is CharonMIDI..., so a band whose release has the
// protocol API still gets these, where MIDIProtocol14.m is left out.
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

#import "CharonCoreMIDI.h"

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

// Logs the first refusal, once: a packet or an event the library cannot carry is not dropped silently, and the same refusal is
// not written again for every packet that meets it.
static void charon_refused(const char *reason)
{
    static int logged = 0;
    if (!logged) {
        logged = 1;
        NSLog(@"charon: CoreMIDI refused %s (the first refusal is logged; later ones are not written)", reason);
    }
}

// The MIDI 1.0 parser of one source of a port, keyed by the reference the source was connected with (srcConnRefCon). Two
// sources are two byte streams: the SysEx one source has open does not continue on the bytes of another.
typedef struct charon_source {
    void *refCon;
    CharonMIDIParser parser;
} charon_source;

// The receive side of one port or destination: the block it was given, retained for as long as it lives, the protocol its
// events are delivered in, the parsers of its sources, and the lock that guards those parsers.
typedef struct charon_port {
    void *block;
    int protocol;
    pthread_mutex_t lock;
    charon_source *sources;
    size_t sourceCount;
    size_t sourceCapacity;
} charon_port;

// The 2.0 parameter selection each destination (or source) last sent on each channel.
typedef struct charon_route {
    MIDIEndpointRef endpoint;
    CharonMIDIRPN rpn[16];
} charon_route;

// The table grows with the endpoints that send; every access takes the lock.
static charon_route *charon_routes;
static size_t charon_route_count;
static size_t charon_route_capacity;
static pthread_mutex_t charon_lock = PTHREAD_MUTEX_INITIALIZER;

// The objects this file made with a block, and what each owns: the receive side of an input port or a destination (port), or
// the retained block of a port, destination or client that MIDIBlocks9.m made (refCon). A destination row also lets this process
// deliver to the destination itself. The release does not tell the library that an object was disposed, so the rows are swept
// whenever a new one is made. An object the release no longer knows answers paramErr to a UniqueID read (a destination, a
// source, an input port and a client: oracle/removal-notify-macos.txt on macOS, and the 6.1.3 probe of
// tests/backports/emulate/coremidi/app/main.m). The release may give a disposed reference to a new object, so each row also
// carries the stamp the library wrote on the object (CHARON_OWNER_KEY) when it took it: a live object that answers another
// stamp, or none, is a reference that was given again. The stamp is the library's own key, so what an application does to the
// object's UniqueID (the creator's to set) does not change the row.
typedef struct charon_owned {
    MIDIObjectRef object;
    int destination;
    charon_port *port;
    void *refCon;
    int stamped;
    SInt32 stamp;
} charon_owned;
static charon_owned *charon_owned_rows;
static size_t charon_owned_count;
static size_t charon_owned_capacity;
static pthread_mutex_t charon_owned_lock = PTHREAD_MUTEX_INITIALIZER;

// The parser of a source of a port, made on its first list. The caller holds the port's lock. NULL when the table cannot grow.
static CharonMIDIParser *charon_source_parser(charon_port *port, void *refCon)
{
    for (size_t i = 0; i < port->sourceCount; i++)
        if (port->sources[i].refCon == refCon)
            return &port->sources[i].parser;
    if (port->sourceCount == port->sourceCapacity) {
        size_t capacity = port->sourceCapacity ? charon_grown_capacity(port->sourceCapacity, sizeof(charon_source)) : 4;
        charon_source *grown = capacity ? realloc(port->sources, capacity * sizeof(charon_source)) : NULL;
        if (!grown)
            return NULL;
        port->sources = grown;
        port->sourceCapacity = capacity;
    }
    charon_source *source = &port->sources[port->sourceCount++];
    source->refCon = refCon;
    memset(&source->parser, 0, sizeof(source->parser));
    return &source->parser;
}

// The receive thread of the release calls this with a list of MIDI 1.0 packets. Each packet becomes one event packet of the
// same time stamp, in the port's protocol. The parser is the source's own, so a SysEx that is open at the end of one list is
// continued by the next, and the list's last packet sends whatever is still held.
static void charon_protocol_read(const MIDIPacketList *packets, void *refCon, void *srcConnRefCon)
{
    charon_port *port = refCon;
    if (!port->block)
        return;
    // Eight bytes of event per byte of input bounds every message's words, a SysEx's included. The sizes are summed with checks:
    // the release's counts are summed into a size_t that is 32 bits on armv7.
    size_t capacity = 8;
    const MIDIPacket *packet = &packets->packet[0];
    for (UInt32 i = 0; i < packets->numPackets; i++) {
        size_t piece = 0;
        if (!charon_size_mul(&piece, 8, packet->length) || !charon_size_add(&piece, 12) || !charon_size_add(&capacity, piece)) {
            charon_refused("a list whose events do not fit the address space");
            return;
        }
        packet = MIDIPacketNext(packet);
    }
    MIDIEventList *list = malloc(capacity);
    if (!list) {
        charon_refused("a list the allocator would not give");
        return;
    }
    list->protocol = port->protocol;
    list->numPackets = 0;
    MIDIEventPacket *end = &list->packet[0];
    MIDIEventPacket *last = NULL;
    CharonMIDIWords words;
    memset(&words, 0, sizeof(words));
    pthread_mutex_lock(&port->lock);
    CharonMIDIParser *parser = charon_source_parser(port, srcConnRefCon);
    if (!parser)
        charon_refused("a source whose parser cannot be made");
    packet = &packets->packet[0];
    for (UInt32 i = 0; parser && i < packets->numPackets; i++) {
        words.count = 0;
        CharonMIDIParseBytes(parser, packet->data, packet->length, port->protocol, 0, &words);
        if (i + 1 == packets->numPackets)
            CharonMIDIParseFlush(parser, 0, &words);
        if (words.failed) {
            charon_refused("the words of a packet, which could not be allocated");
        } else if (words.count > 0) {
            MIDIEventPacket *next = CharonMIDIEventListAppend(list, capacity, end, &last, packet->timeStamp, words.count, words.words);
            if (next)
                end = next;
            else
                charon_refused("an event that does not fit the list it was sized for");
        }
        packet = MIDIPacketNext(packet);
    }
    pthread_mutex_unlock(&port->lock);
    free(words.words);
    if (list->numPackets > 0) {
        MIDIReceiveBlock block = (__bridge MIDIReceiveBlock)port->block;
        block(list, srcConnRefCon);
    }
    free(list);
}

// The protocol of an endpoint, as the port sets it. The result is the release's; a caller that cannot set it disposes the endpoint.
static OSStatus charon_set_protocol(MIDIEndpointRef endpoint, MIDIProtocolID protocol)
{
    return MIDIObjectSetIntegerProperty(endpoint, CHARON_PROTOCOL_KEY, (SInt32)protocol);
}

static charon_port *charon_new_port(MIDIProtocolID protocol, MIDIReceiveBlock block)
{
    charon_port *port = calloc(1, sizeof(charon_port));
    if (!port)
        return NULL;
    port->protocol = (int)protocol;
    port->block = block ? (__bridge_retained void *)[block copy] : NULL;
    pthread_mutex_init(&port->lock, NULL);
    return port;
}

static void charon_free_port(charon_port *port)
{
    if (port->block)
        (void)(__bridge_transfer id)port->block;
    pthread_mutex_destroy(&port->lock);
    free(port->sources);
    free(port);
}

// Whether the release no longer knows an object: a UniqueID read answers paramErr for one that was disposed (and for one that
// never existed), and a live object answers something else (noErr, or -10835 for an object with no UniqueID).
static int charon_gone(MIDIObjectRef object)
{
    SInt32 uniqueID = 0;
    return MIDIObjectGetIntegerProperty(object, kMIDIPropertyUniqueID, &uniqueID) == charon_paramErr;
}

typedef enum {
    charon_object_live,
    charon_object_gone,
    charon_object_replaced
} charon_object_state;

// What a reference answers now, for the object that was taken with the given stamp (stamped is 0 when the stamp could not be
// written). paramErr is an object the release no longer knows. For a stamped object the stamp read back is the evidence of
// identity: noErr with the same value is the object; noErr with another value, or kMIDIUnknownProperty on a live object, is a
// reference that was given to a new object. Any other status (the server not answering, say) is no evidence: the object is
// kept, because freeing the port of a live object leaves the release calling into freed memory.
static charon_object_state charon_object_check(MIDIObjectRef object, int stamped, SInt32 stamp)
{
    SInt32 value = 0;
    OSStatus status = MIDIObjectGetIntegerProperty(object, CHARON_OWNER_KEY, &value);
    if (status == charon_paramErr)
        return charon_object_gone;
    if (!stamped)
        return charon_object_live;
    if (status == noErr)
        return value == stamp ? charon_object_live : charon_object_replaced;
    return status == kMIDIUnknownProperty ? charon_object_replaced : charon_object_live;
}

// Whether an owned row is stale: its object is gone, or its reference now belongs to another object.
static int charon_row_stale(const charon_owned *row)
{
    return charon_object_check(row->object, row->stamped, row->stamp) != charon_object_live;
}

// Frees what an owned row holds: the port and its block, or the retained block alone.
static void charon_free_owned(charon_owned *row)
{
    if (row->port)
        charon_free_port(row->port);
    if (row->refCon)
        (void)(__bridge_transfer id)row->refCon;
}

// Forgets the endpoints that are gone from the selection states: a disposed endpoint sends nothing again. Called with the
// owned lock held, and takes the route lock (no caller holds the route lock while it takes the owned lock).
static void charon_prune_routes(void)
{
    pthread_mutex_lock(&charon_lock);
    size_t kept = 0;
    for (size_t i = 0; i < charon_route_count; i++) {
        if (!charon_gone(charon_routes[i].endpoint))
            charon_routes[kept++] = charon_routes[i];
    }
    charon_route_count = kept;
    pthread_mutex_unlock(&charon_lock);
}

// Frees the rows that are stale, and the selection states of the endpoints that are gone. Called with the owned lock held.
static void charon_sweep_owned(void)
{
    size_t kept = 0;
    for (size_t i = 0; i < charon_owned_count; i++) {
        if (charon_row_stale(&charon_owned_rows[i]))
            charon_free_owned(&charon_owned_rows[i]);
        else
            charon_owned_rows[kept++] = charon_owned_rows[i];
    }
    charon_owned_count = kept;
    charon_prune_routes();
}

// Records an object the library made with a block, after a sweep. A row that cannot be added (the table cannot grow) leaves the
// object untracked: its port or block is then kept for as long as the process runs.
static void charon_own(MIDIObjectRef object, int destination, charon_port *port, void *refCon)
{
    charon_owned row;
    memset(&row, 0, sizeof(row));
    row.object = object;
    row.destination = destination;
    row.port = port;
    row.refCon = refCon;
    // The stamp is a value of this process's own choosing: a reused reference may carry another library instance's stamp, and a
    // random value makes a coincidence a 2^-32 event.
    row.stamp = (SInt32)arc4random();
    row.stamped = MIDIObjectSetIntegerProperty(object, CHARON_OWNER_KEY, row.stamp) == noErr;
    pthread_mutex_lock(&charon_owned_lock);
    charon_sweep_owned();
    if (charon_owned_count == charon_owned_capacity) {
        size_t capacity = charon_grown_capacity(charon_owned_capacity, sizeof(charon_owned));
        charon_owned *grown = capacity ? realloc(charon_owned_rows, capacity * sizeof(charon_owned)) : NULL;
        if (grown) {
            charon_owned_rows = grown;
            charon_owned_capacity = capacity;
        }
    }
    if (charon_owned_count < charon_owned_capacity)
        charon_owned_rows[charon_owned_count++] = row;
    pthread_mutex_unlock(&charon_owned_lock);
}

// What this process made an endpoint: a destination with a live receive side (its block and protocol are returned), a destination
// that is gone (sends to it deliver nothing), or an endpoint that is not one of this process's destinations, which is so when its
// reference is not in the table or the reference now answers another UniqueID.
typedef enum {
    charon_not_ours,
    charon_ours_live,
    charon_ours_gone
} charon_ownership;

static charon_ownership charon_destination_state(MIDIEndpointRef endpoint, MIDIReceiveBlock *block, int *protocol)
{
    charon_ownership state = charon_not_ours;
    pthread_mutex_lock(&charon_owned_lock);
    for (size_t i = 0; i < charon_owned_count; i++) {
        charon_owned *row = &charon_owned_rows[i];
        if (!row->destination || row->object != endpoint || !row->port)
            continue;
        *block = (__bridge MIDIReceiveBlock)row->port->block;
        *protocol = row->port->protocol;
        charon_object_state object = charon_object_check(endpoint, row->stamped, row->stamp);
        if (object == charon_object_gone)
            state = charon_ours_gone;
        else if (object == charon_object_live)
            state = charon_ours_live;
        break;
    }
    pthread_mutex_unlock(&charon_owned_lock);
    return state;
}

// The one queue every in-process delivery runs on, serial, so that the sends of this process arrive in the order they were made.
// macOS delivers on its own thread and after the send returns (oracle/removal-notify-macos.txt: the block ran after the call).
static dispatch_queue_t charon_delivery_queue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("charon.in-process-delivery", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// Hands a list to a block on the delivery queue. The list belongs to the delivery: the queue frees it after the block returns.
static void charon_deliver_async(MIDIReceiveBlock block, MIDIEventList *list)
{
    dispatch_async(charon_delivery_queue(), ^{
        block(list, NULL);
        free(list);
    });
}

OSStatus CharonMIDIInputPort(MIDIClientRef client, CFStringRef portName, MIDIProtocolID protocol,
                                         MIDIPortRef *outPort, MIDIReceiveBlock receiveBlock)
{
    if (protocol != kMIDIProtocol_1_0 && protocol != kMIDIProtocol_2_0)
        return charon_paramErr;
    charon_port *port = charon_new_port(protocol, receiveBlock);
    if (!port)
        return charon_memFullErr;
    OSStatus status = MIDIInputPortCreate(client, portName, charon_protocol_read, port, outPort);
    if (status != noErr)
        charon_free_port(port);
    else
        charon_own(*outPort, 0, port, NULL);
    return status;
}

// Delivers a list of UMP words verbatim to a destination this process made, in the port's protocol, on the delivery queue. NO when
// the endpoint is not one of this process's destinations; a destination that is gone takes nothing, as macOS delivers nothing to one.
Boolean CharonMIDIDeliverInProcess(MIDIEndpointRef endpoint, const UInt32 *words, UInt32 count)
{
    MIDIReceiveBlock block = NULL;
    int protocol = 0;
    charon_ownership state = charon_destination_state(endpoint, &block, &protocol);
    if (state == charon_not_ours)
        return false;
    if (state == charon_ours_gone || !block)
        return true;
    // The list header, one packet's header, and the words: four bytes a word, summed with checks.
    size_t bytes = 0;
    if (!charon_size_mul(&bytes, 4, count) || !charon_size_add(&bytes, 8 + sizeof(MIDITimeStamp) + sizeof(UInt32))) {
        charon_refused("a UMP send of this many words");
        return true;
    }
    MIDIEventList *list = malloc(bytes);
    if (!list)
        return true;
    list->protocol = (MIDIProtocolID)protocol;
    list->numPackets = 0;
    MIDIEventPacket *last = NULL;
    if (CharonMIDIEventListAppend(list, bytes, &list->packet[0], &last, 0, count, words))
        charon_deliver_async(block, list);
    else
        free(list);
    return true;
}

// A list sent to a 2.0 destination this process made goes to its block as it is: each packet's time stamp and words, with no
// conversion to MIDI 1.0 and back, which cuts a 2.0 value to 7 bits (the release's route). NO when the endpoint is not such a
// destination, and then the list takes the release's route; a list that cannot be copied answers memFullErr and sends nothing.
static int charon_deliver_2_0(MIDIEndpointRef endpoint, const MIDIEventList *source, OSStatus *status)
{
    MIDIReceiveBlock block = NULL;
    int protocol = 0;
    charon_ownership state = charon_destination_state(endpoint, &block, &protocol);
    if (state == charon_not_ours || protocol != kMIDIProtocol_2_0)
        return 0;
    *status = noErr;
    if (state == charon_ours_gone || !block)
        return 1;
    size_t bytes = 16;
    const MIDIEventPacket *event = &source->packet[0];
    for (UInt32 i = 0; i < source->numPackets; i++) {
        size_t piece = 0;
        if (!charon_size_mul(&piece, 4, event->wordCount) || !charon_size_add(&piece, 16) || !charon_size_add(&bytes, piece)) {
            *status = charon_memFullErr;
            charon_refused("a 2.0 list of this many words");
            return 1;
        }
        event = MIDIEventPacketNext(event);
    }
    MIDIEventList *list = malloc(bytes);
    if (!list) {
        *status = charon_memFullErr;
        return 1;
    }
    list->protocol = kMIDIProtocol_2_0;
    list->numPackets = 0;
    MIDIEventPacket *end = &list->packet[0];
    MIDIEventPacket *last = NULL;
    event = &source->packet[0];
    for (UInt32 i = 0; i < source->numPackets && end; i++) {
        end = CharonMIDIEventListAppend(list, bytes, end, &last, event->timeStamp, event->wordCount, event->words);
        event = MIDIEventPacketNext(event);
    }
    if (end)
        charon_deliver_async(block, list);
    else {
        *status = charon_memFullErr;
        free(list);
    }
    return 1;
}

OSStatus CharonMIDIDestination(MIDIClientRef client, CFStringRef name, MIDIProtocolID protocol,
                                           MIDIEndpointRef *outDest, MIDIReceiveBlock readBlock)
{
    if (protocol != kMIDIProtocol_1_0 && protocol != kMIDIProtocol_2_0)
        return charon_paramErr;
    charon_port *port = charon_new_port(protocol, readBlock);
    if (!port)
        return charon_memFullErr;
    OSStatus status = MIDIDestinationCreate(client, name, charon_protocol_read, port, outDest);
    if (status != noErr) {
        charon_free_port(port);
        return status;
    }
    status = charon_set_protocol(*outDest, protocol);
    if (status != noErr) {
        // The destination is not handed out: it is disposed, and nothing of the port is kept.
        if (MIDIEndpointDispose(*outDest) != noErr)
            charon_refused("the dispose of a destination whose protocol was refused");
        charon_free_port(port);
        return status;
    }
    charon_own(*outDest, 1, port, NULL);
    return noErr;
}

// The retained block of a port, destination or client that MIDIBlocks9.m made through the release's function form: the block is
// released when the object is gone, as the rows of this file are.
void CharonMIDIOwnBlock(MIDIObjectRef object, void *retainedBlock)
{
    charon_own(object, 0, NULL, retainedBlock);
}

OSStatus CharonMIDISource(MIDIClientRef client, CFStringRef name, MIDIProtocolID protocol, MIDIEndpointRef *outSrc)
{
    if (protocol != kMIDIProtocol_1_0 && protocol != kMIDIProtocol_2_0)
        return charon_paramErr;
    OSStatus status = MIDISourceCreate(client, name, outSrc);
    if (status != noErr)
        return status;
    status = charon_set_protocol(*outSrc, protocol);
    if (status != noErr) {
        if (MIDIEndpointDispose(*outSrc) != noErr)
            charon_refused("the dispose of a source whose protocol was refused");
        return status;
    }
    return noErr;
}

// The selection state of an endpoint, found or made. NULL when the table cannot grow: the list is then converted
// with no state carried from the list before, and the caller says so by failing the conversion.
static CharonMIDIRPN *charon_state(MIDIEndpointRef endpoint)
{
    for (size_t i = 0; i < charon_route_count; i++)
        if (charon_routes[i].endpoint == endpoint)
            return charon_routes[i].rpn;
    if (charon_route_count == charon_route_capacity) {
        size_t capacity = charon_route_capacity ? charon_grown_capacity(charon_route_capacity, sizeof(charon_route)) : 16;
        charon_route *grown = capacity ? realloc(charon_routes, capacity * sizeof(charon_route)) : NULL;
        if (!grown)
            return NULL;
        charon_routes = grown;
        charon_route_capacity = capacity;
    }
    charon_route *route = &charon_routes[charon_route_count++];
    route->endpoint = endpoint;
    memset(route->rpn, 0, sizeof(route->rpn));
    return route->rpn;
}

// Converts an event list to MIDI 1.0 packets and hands them to the release: MIDISend for a list sent from a port,
// MIDIReceived for one that comes from a source. A list with no 1.0 form sends nothing and answers noErr, as the
// release does for an empty list; a list that cannot be converted answers memFullErr and sends nothing.
static OSStatus charon_send(MIDIPortRef port, MIDIEndpointRef endpoint, const MIDIEventList *list, int received)
{
    // The capacity is summed from the packets' word counts with checks, before any word is read: a count that wraps the size_t
    // is refused here, and no conversion reads past the list.
    size_t capacity = 16;
    const MIDIEventPacket *event = &list->packet[0];
    for (UInt32 i = 0; i < list->numPackets; i++) {
        // A MIDI 1.0 packet's header and up to three bytes for each word, plus the parameter's own bytes.
        size_t piece = 0;
        if (!charon_size_mul(&piece, 8, event->wordCount) || !charon_size_add(&piece, 10) || !charon_size_add(&capacity, piece))
            return charon_memFullErr;
        event = MIDIEventPacketNext(event);
    }
    MIDIPacketList *packets = malloc(capacity);
    if (!packets)
        return charon_memFullErr;
    CharonMIDIBytes bytes;
    memset(&bytes, 0, sizeof(bytes));
    int failed = 0;
    pthread_mutex_lock(&charon_lock);
    CharonMIDIRPN *state = charon_state(endpoint);
    if (!state)
        failed = 1;
    MIDIPacket *packet = MIDIPacketListInit(packets);
    event = &list->packet[0];
    for (UInt32 i = 0; i < list->numPackets && !failed; i++) {
        bytes.count = 0;
        CharonMIDIUMPToBytes(event->words, event->wordCount, state, &bytes);
        if (bytes.failed) {
            failed = 1;
        } else if (bytes.count > 0) {
            MIDIPacket *next = MIDIPacketListAdd(packets, capacity, packet, event->timeStamp, bytes.count, bytes.bytes);
            if (next)
                packet = next;
            else
                failed = 1;
        }
        event = MIDIEventPacketNext(event);
    }
    pthread_mutex_unlock(&charon_lock);
    free(bytes.bytes);
    OSStatus status = failed ? charon_memFullErr : noErr;
    if (status == noErr && packets->numPackets > 0)
        status = received ? MIDIReceived(endpoint, packets) : MIDISend(port, endpoint, packets);
    free(packets);
    return status;
}

OSStatus CharonMIDISend(MIDIPortRef port, MIDIEndpointRef dest, const MIDIEventList *evtlist)
{
    OSStatus status = noErr;
    if (charon_deliver_2_0(dest, evtlist, &status))
        return status;
    return charon_send(port, dest, evtlist, 0);
}

OSStatus CharonMIDIReceive(MIDIEndpointRef src, const MIDIEventList *evtlist)
{
    return charon_send(0, src, evtlist, 1);
}
