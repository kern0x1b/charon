#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

// The encoding and the decoding the three snapshot objects share, written once as static inline so
// that each object holds its own copy and no object names a symbol another one defines.
//
// The data is not a private blob: the framework's own header describes it as a packed structure
// whose first four bytes are a version and a size, with the fields after them in a stated order. So
// what these write is the header's layout and not an approximation of it, and data this port wrote
// reads back through any of the ten functions.
//
// Every answer was measured against the host's own GameController under macOS 27 with no controller
// connected, by the `snapshot functions` group of tests/backports/host/gamecontroller over a matrix
// of inputs: 9188 checks, 0 different, and five mutants of these rules, each noticed.
// facts/GameController/Snapshots.md names each measurement.

#pragma once

// The version the gamepad's own structure documents. It carries no version symbol of its own.
#define CHARON_GCGAMEPAD_SNAPSHOT_VERSION_V100 0x0100

// The structure as data, with its version and size filled in when it carries neither, which is what
// the header says the data "will automatically have". Measured: a zeroed structure encodes with the
// version and the size in its first four bytes, and a structure that already carries a version and a
// size keeps both - version 0x0200 and size 999 encode as 0002 e703.
static inline NSData *charon_gc_snapshot_data(const void *bytes, size_t length, uint16_t version)
{
    if (bytes == NULL)
        return nil;
    void *copy = malloc(length);
    if (copy == NULL)
        return nil;
    memcpy(copy, bytes, length);
    if (length >= 4) {
        uint16_t *header = (uint16_t *)copy;
        if (header[0] == 0)
            header[0] = version;
        if (header[1] == 0)
            header[1] = (uint16_t)length;
    }
    return [NSData dataWithBytesNoCopy:copy length:length freeWhenDone:YES];
}

// The two families of reader accept different data, and the measurements are what fix the two rules:
//
//   the gamepad's V100 reader wants a whole structure and a version that is not zero - measured, 35
//   bytes is refused, a version of zero is refused at a length it otherwise accepts, and this reader
//   alone refuses data with no header at all, empty included;
//   the extended and the micro readers read the header's declared size and refuse one that declares
//   itself larger than the structure they fill - measured, 63 bytes that declare 999 are refused,
//   and so are 59 bytes whose declared size is 0x4141, while 59 bytes that declare 59 are read.

static inline BOOL charon_gc_accept_whole_structure(NSData *data, size_t length)
{
    if (data.length < 4)
        return NO;
    uint16_t header[2] = {0, 0};
    [data getBytes:header length:4];
    return data.length >= length && header[0] != 0;
}

static inline BOOL charon_gc_accept_declared_size(NSData *data, size_t length)
{
    if (data.length < 4)
        return YES;  // nothing declares a size, so nothing is refused
    uint16_t header[2] = {0, 0};
    [data getBytes:header length:4];
    return header[1] <= length;
}

// Fills the structure with as much of the data as reaches it, and answers whether this reader takes
// the data at all.
static inline BOOL charon_gc_snapshot_read(void *out, NSData *data, size_t length, BOOL (*accepts)(NSData *, size_t))
{
    if (out == NULL || data == nil)
        return NO;
    if (!accepts(data, length))
        return NO;
    memset(out, 0, length);
    NSUInteger take = MIN((NSUInteger)length, data.length);
    if (take > 0)
        [data getBytes:out length:take];
    return YES;
}
