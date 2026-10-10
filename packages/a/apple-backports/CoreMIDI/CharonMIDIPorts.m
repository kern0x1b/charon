// The protocol-aware ports and endpoints, and the list sends, of the iOS 14 API, as internal functions: the
// functions MIDIProtocol14.m exports call these, and so do the iOS 18 classes (MIDIUMP18.m), which build on the
// same endpoints. This file exports no API name: every function is CharonMIDI..., so a band whose release has the
// protocol API still gets these, where MIDIProtocol14.m is left out.
#import <CoreMIDI/CoreMIDI.h>

#import "CharonCoreMIDI.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

// The protocol key, as a constant of this file: the iOS SDK marks kMIDIPropertyProtocolID as available from 14.0, and
// this library is built for releases before it, so a use of the exported constant would be unguarded there. The string
// is the one macOS gives the constant (oracle/probe2.m prints it).
static const CFStringRef charon_protocol_key = CFSTR("protocol");

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

// The objects this file made with a block, and what each owns: the receive side of an input port or a destination (port),
// or a retained block of a port or destination that MIDIBlocks9.m made (refCon). A destination row also lets this process
// deliver to the destination itself. The release does not tell the library that an object was disposed, so the rows are
// swept whenever a new one is made: an object the release no longer knows answers paramErr to a UniqueID read (measured on
// macOS for a destination, a source and an input port: oracle/removal-notify.m, removal-notify-macos.txt).
typedef struct charon_owned {
    MIDIObjectRef object;
    int destination;
    charon_port *port;
    void *refCon;
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
        size_t capacity = port->sourceCapacity ? port->sourceCapacity * 2 : 4;
        charon_source *grown = realloc(port->sources, capacity * sizeof(charon_source));
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
    size_t capacity = 8;
    const MIDIPacket *packet = &packets->packet[0];
    for (UInt32 i = 0; i < packets->numPackets; i++) {
        // Eight bytes of event per byte of input bounds every message's words, a SysEx's included.
        capacity += 12 + 8 * (size_t)packet->length;
        packet = MIDIPacketNext(packet);
    }
    MIDIEventList *list = malloc(capacity);
    if (!list)
        return;
    list->protocol = port->protocol;
    list->numPackets = 0;
    MIDIEventPacket *end = &list->packet[0];
    CharonMIDIWords words;
    memset(&words, 0, sizeof(words));
    pthread_mutex_lock(&port->lock);
    // A source whose parser cannot be made (the table cannot grow) sends no packet of this list, and says nothing more.
    CharonMIDIParser *parser = charon_source_parser(port, srcConnRefCon);
    packet = &packets->packet[0];
    for (UInt32 i = 0; parser && i < packets->numPackets; i++) {
        words.count = 0;
        CharonMIDIParseBytes(parser, packet->data, packet->length, port->protocol, 0, &words);
        if (i + 1 == packets->numPackets)
            CharonMIDIParseFlush(parser, 0, &words);
        if (words.count > 0 && !words.failed) {
            MIDIEventPacket *next = CharonMIDIEventListAdd(list, capacity, end, packet->timeStamp, words.count, words.words);
            if (next)
                end = next;
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

static void charon_set_protocol(MIDIEndpointRef endpoint, MIDIProtocolID protocol)
{
    MIDIObjectSetIntegerProperty(endpoint, charon_protocol_key, (SInt32)protocol);
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
// never existed), and a live object answers something else.
static int charon_gone(MIDIObjectRef object)
{
    SInt32 uniqueID = 0;
    return MIDIObjectGetIntegerProperty(object, kMIDIPropertyUniqueID, &uniqueID) == charon_paramErr;
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

// Frees the rows of the objects that are gone, and the selection states of the endpoints that are. Called with the owned lock held.
static void charon_sweep_owned(void)
{
    size_t kept = 0;
    for (size_t i = 0; i < charon_owned_count; i++) {
        if (charon_gone(charon_owned_rows[i].object))
            charon_free_owned(&charon_owned_rows[i]);
        else
            charon_owned_rows[kept++] = charon_owned_rows[i];
    }
    charon_owned_count = kept;
    charon_prune_routes();
}

// Records an object the library made with a block, after a sweep. A row that cannot be added (the table cannot grow) leaves
// the object untracked: its port or block is then kept for as long as the process runs, as it was before the table existed.
static void charon_own(MIDIObjectRef object, int destination, charon_port *port, void *refCon)
{
    pthread_mutex_lock(&charon_owned_lock);
    charon_sweep_owned();
    if (charon_owned_count == charon_owned_capacity) {
        size_t capacity = charon_owned_capacity ? charon_owned_capacity * 2 : 16;
        charon_owned *grown = realloc(charon_owned_rows, capacity * sizeof(charon_owned));
        if (grown) {
            charon_owned_rows = grown;
            charon_owned_capacity = capacity;
        }
    }
    if (charon_owned_count < charon_owned_capacity) {
        charon_owned *row = &charon_owned_rows[charon_owned_count++];
        row->object = object;
        row->destination = destination;
        row->port = port;
        row->refCon = refCon;
    }
    pthread_mutex_unlock(&charon_owned_lock);
}

// The block a destination this process made delivers to, and its protocol: a copy of the block, so that it outlives a sweep
// that happens while the caller calls it. NO when the endpoint is not one of this process's destinations.
static int charon_destination(MIDIEndpointRef endpoint, MIDIReceiveBlock *block, int *protocol)
{
    int found = 0;
    pthread_mutex_lock(&charon_owned_lock);
    for (size_t i = 0; i < charon_owned_count; i++) {
        charon_owned *row = &charon_owned_rows[i];
        if (row->destination && row->object == endpoint && row->port) {
            *block = (__bridge MIDIReceiveBlock)row->port->block;
            *protocol = row->port->protocol;
            found = 1;
            break;
        }
    }
    pthread_mutex_unlock(&charon_owned_lock);
    return found;
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

// Delivers a list of UMP words verbatim to a destination this process made, in the port's protocol, on the calling thread
// (macOS delivers on its own thread: the one difference). NO when the endpoint is not one of this process's destinations;
// a destination that was disposed takes nothing, as macOS delivers nothing to one.
Boolean CharonMIDIDeliverInProcess(MIDIEndpointRef endpoint, const UInt32 *words, UInt32 count)
{
    MIDIReceiveBlock block = NULL;
    int protocol = 0;
    if (!charon_destination(endpoint, &block, &protocol))
        return false;
    if (!block || charon_gone(endpoint))
        return true;
    size_t capacity = 8 + sizeof(MIDITimeStamp) + sizeof(UInt32) + 4 * (size_t)count;
    MIDIEventList *list = malloc(capacity);
    if (!list)
        return false;
    list->protocol = (MIDIProtocolID)protocol;
    list->numPackets = 0;
    MIDIEventPacket *end = CharonMIDIEventListAdd(list, capacity, &list->packet[0], 0, count, words);
    if (end)
        block(list, NULL);
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
    if (!charon_destination(endpoint, &block, &protocol) || protocol != kMIDIProtocol_2_0)
        return 0;
    *status = noErr;
    if (!block || charon_gone(endpoint))
        return 1;
    size_t capacity = 16;
    const MIDIEventPacket *event = &source->packet[0];
    for (UInt32 i = 0; i < source->numPackets; i++) {
        capacity += 16 + 4 * (size_t)event->wordCount;
        event = MIDIEventPacketNext(event);
    }
    MIDIEventList *list = malloc(capacity);
    if (!list) {
        *status = charon_memFullErr;
        return 1;
    }
    list->protocol = kMIDIProtocol_2_0;
    list->numPackets = 0;
    MIDIEventPacket *end = &list->packet[0];
    event = &source->packet[0];
    for (UInt32 i = 0; i < source->numPackets && end; i++) {
        end = CharonMIDIEventListAdd(list, capacity, end, event->timeStamp, event->wordCount, event->words);
        event = MIDIEventPacketNext(event);
    }
    if (end)
        block(list, NULL);
    else
        *status = charon_memFullErr;
    free(list);
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
    } else {
        charon_set_protocol(*outDest, protocol);
        charon_own(*outDest, 1, port, NULL);
    }
    return status;
}

// The retained block of a port or a destination that MIDIBlocks9.m made through the release's function form: the block is
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
    if (status == noErr)
        charon_set_protocol(*outSrc, protocol);
    return status;
}

// The selection state of an endpoint, found or made. NULL when the table cannot grow: the list is then converted
// with no state carried from the list before, and the caller says so by failing the conversion.
static CharonMIDIRPN *charon_state(MIDIEndpointRef endpoint)
{
    for (size_t i = 0; i < charon_route_count; i++)
        if (charon_routes[i].endpoint == endpoint)
            return charon_routes[i].rpn;
    if (charon_route_count == charon_route_capacity) {
        size_t capacity = charon_route_capacity ? charon_route_capacity * 2 : 16;
        charon_route *grown = realloc(charon_routes, capacity * sizeof(charon_route));
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
    size_t capacity = 16;
    const MIDIEventPacket *event = &list->packet[0];
    for (UInt32 i = 0; i < list->numPackets; i++) {
        // A MIDI 1.0 packet's header and up to three bytes for each word, plus the parameter's own bytes.
        capacity += 10 + 8 * (size_t)event->wordCount;
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
