// The protocol-aware ports and endpoints of iOS 14, over the release's own MIDI 1.0 ones:
// MIDIInputPortCreateWithProtocol, MIDIDestinationCreateWithProtocol, MIDISourceCreateWithProtocol,
// MIDISendEventList and MIDIReceivedEventList, and the property that names an endpoint's protocol.
//
// The release carries MIDI 1.0 bytes only. A port or a destination that receives them converts each packet to
// Universal MIDI Packets in the protocol it was made for, and a list that is sent or received is converted to
// MIDI 1.0 bytes before the release delivers it. Both conversions are CharonCoreMIDI.c's, and the measured
// rules behind them are in facts/CoreMIDI/Translation.md. What a 2.0 endpoint loses by this route is the
// resolution of a 2.0 value between two 2.0 endpoints of this process: they meet at 1.0 resolution, as the
// release's own endpoints do between processes.
#import <CoreMIDI/CoreMIDI.h>

#import "CharonCoreMIDI.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

const CFStringRef kMIDIPropertyProtocolID = CFSTR("protocol");

// The receive side of one port or destination: the block it was given, retained for as long as it lives, the
// protocol its events are delivered in, and the MIDI 1.0 parser that carries a SysEx from one list to the next.
typedef struct charon_port {
    void *block;
    int protocol;
    CharonMIDIParser parser;
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

// The receive thread of the release calls this with a list of MIDI 1.0 packets. Each packet becomes one event
// packet of the same time stamp, in the port's protocol. The parser is the port's own, so a SysEx that is open
// at the end of one list is continued by the next, and the list's last packet sends whatever is still held.
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
    packet = &packets->packet[0];
    for (UInt32 i = 0; i < packets->numPackets; i++) {
        words.count = 0;
        CharonMIDIParseBytes(&port->parser, packet->data, packet->length, port->protocol, 0, &words);
        if (i + 1 == packets->numPackets)
            CharonMIDIParseFlush(&port->parser, 0, &words);
        if (words.count > 0 && !words.failed) {
            MIDIEventPacket *next = CharonMIDIEventListAdd(list, capacity, end, packet->timeStamp, words.count, words.words);
            if (next)
                end = next;
        }
        packet = MIDIPacketNext(packet);
    }
    free(words.words);
    if (list->numPackets > 0) {
        MIDIReceiveBlock block = (__bridge MIDIReceiveBlock)port->block;
        block(list, srcConnRefCon);
    }
    free(list);
}

static void charon_set_protocol(MIDIEndpointRef endpoint, MIDIProtocolID protocol)
{
    MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyProtocolID, (SInt32)protocol);
}

static charon_port *charon_new_port(MIDIProtocolID protocol, MIDIReceiveBlock block)
{
    charon_port *port = calloc(1, sizeof(charon_port));
    if (!port)
        return NULL;
    port->protocol = (int)protocol;
    port->block = block ? (__bridge_retained void *)[block copy] : NULL;
    return port;
}

static void charon_free_port(charon_port *port)
{
    if (port->block)
        (void)(__bridge_transfer id)port->block;
    free(port);
}

OSStatus MIDIInputPortCreateWithProtocol(MIDIClientRef client, CFStringRef portName, MIDIProtocolID protocol,
                                         MIDIPortRef *outPort, MIDIReceiveBlock receiveBlock)
{
    if (protocol != kMIDIProtocol_1_0 && protocol != kMIDIProtocol_2_0)
        return paramErr;
    charon_port *port = charon_new_port(protocol, receiveBlock);
    if (!port)
        return memFullErr;
    OSStatus status = MIDIInputPortCreate(client, portName, charon_protocol_read, port, outPort);
    if (status != noErr)
        charon_free_port(port);
    return status;
}

OSStatus MIDIDestinationCreateWithProtocol(MIDIClientRef client, CFStringRef name, MIDIProtocolID protocol,
                                           MIDIEndpointRef *outDest, MIDIReceiveBlock readBlock)
{
    if (protocol != kMIDIProtocol_1_0 && protocol != kMIDIProtocol_2_0)
        return paramErr;
    charon_port *port = charon_new_port(protocol, readBlock);
    if (!port)
        return memFullErr;
    OSStatus status = MIDIDestinationCreate(client, name, charon_protocol_read, port, outDest);
    if (status != noErr)
        charon_free_port(port);
    else
        charon_set_protocol(*outDest, protocol);
    return status;
}

OSStatus MIDISourceCreateWithProtocol(MIDIClientRef client, CFStringRef name, MIDIProtocolID protocol, MIDIEndpointRef *outSrc)
{
    if (protocol != kMIDIProtocol_1_0 && protocol != kMIDIProtocol_2_0)
        return paramErr;
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
        return memFullErr;
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
    OSStatus status = failed ? memFullErr : noErr;
    if (status == noErr && packets->numPackets > 0)
        status = received ? MIDIReceived(endpoint, packets) : MIDISend(port, endpoint, packets);
    free(packets);
    return status;
}

OSStatus MIDISendEventList(MIDIPortRef port, MIDIEndpointRef dest, const MIDIEventList *evtlist)
{
    return charon_send(port, dest, evtlist, 0);
}

OSStatus MIDIReceivedEventList(MIDIEndpointRef src, const MIDIEventList *evtlist)
{
    return charon_send(0, src, evtlist, 1);
}
