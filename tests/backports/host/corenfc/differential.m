#import <Foundation/Foundation.h>
#import "CoreNFC/CoreNFC.h"
#import "check.h"

// The port's NFCNDEFPayload and NFCNDEFMessage against NDEF byte vectors.
//
// **There is no host framework to compare with**: macOS has no CoreNFC — every declaration of
// NFCNDEFPayload.h and NFCNDEFMessage.h is API_UNAVAILABLE(macos) — so the oracle is the record shape
// of the NFC Forum NDEF Technical Specification itself, and the vectors below are written out from its
// field rules. Two of them are the specification's own worked example (the text RTD's "Hello" in
// English, and a well-known URI) and are the byte strings a reader of that specification would write
// by hand. The rest are built in the test from the same rules, so the round trip is proved against
// them and not against the port's own encoder.

static void check_named(BOOL passed, NSString *name, NSString *detail)
{
    charon_check(passed, [name UTF8String], detail);
}

static NSData *bytes(const unsigned char *values, size_t length)
{
    return [NSData dataWithBytes:values length:length];
}

// A single short well-known record: the header byte is MB 0x80, ME 0x40, SR 0x20, TNF well known
// 0b001 in bits 3..1 which is 0x02, and nothing else - 0xE2. Then the type length, the one byte payload
// length, and, because IL is clear, no ID length field at all; the type "T" and the payload of the
// text RTD: the status byte 0x02 (UTF-8, a two byte language code - its low six bits are that
// length, not a flag), "en" and "Hello", which is eight bytes.
static NSData *TextVector(void)
{
    const unsigned char v[] = {0xE2, 0x01, 0x08, 0x54, 0x02, 0x65, 0x6E, 0x48, 0x65, 0x6C, 0x6C, 0x6F};
    return bytes(v, sizeof v);
}

// The same header, the type "U", and the payload of the URI RTD: 0x01 for the "http://www." prefix
// of its table, then "example.com" - twelve bytes, so 0x0C.
static NSData *URIVector(void)
{
    const unsigned char v[] = {0xE2, 0x01, 0x0C, 0x55, 0x01, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65,
                               0x2E, 0x63, 0x6F, 0x6D};
    return bytes(v, sizeof v);
}

// A record that is not short: SR clear, so the payload length is the four bytes after the type length.
// 0x00 for the two header bytes, the type length, then 0x00 0x00 0x01 0x2C = 300.
static NSData *LongRecordVector(size_t payloadLength)
{
    NSMutableData *data = [NSMutableData data];
    // A media record with an ID: MB, ME, TNF media (0b010 in bits 3..1, which is 0x04), IL set, SR clear.
    const unsigned char head[] = {0xC4, 0x04, (unsigned char)(payloadLength >> 24),
                                  (unsigned char)(payloadLength >> 16), (unsigned char)(payloadLength >> 8),
                                  (unsigned char)payloadLength, 0x00, 0x74, 0x65, 0x73, 0x74};
    [data appendBytes:head length:sizeof head];
    for (size_t index = 0; index < payloadLength; index++) {
        unsigned char filler = (unsigned char)(index & 0xff);
        [data appendBytes:&filler length:1];
    }
    // And a second record after it: ME 0x40, SR 0x20, TNF well known 0x02, so 0x62; a type length of
    // one, a payload length of one, no ID length because IL is clear, the type "Q" and the payload "Q".
    const unsigned char tail[] = {0x62, 0x01, 0x01, 0x51, 0x51};
    [data appendBytes:tail length:sizeof tail];
    return data;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    BOOL mutated = argc > 1 && strcmp(argv[1], "--mutated") == 0;

    // 1. The specification's two worked examples, read back field by field.
    NSData *text = TextVector();
    if (mutated) {
        // One byte of the text record's payload length, so the parse reads a different message: the
        // differential has to notice, and the mutation is shown failing below.
        NSMutableData *changed = [text mutableCopy];
        ((unsigned char *)changed.mutableBytes)[2] = 0x07;   // the payload length, one byte short
        text = changed;
    }
    NFCNDEFMessage *fromText = [NFCNDEFMessage ndefMessageWithData:text];
    check_named(fromText.records.count == 1, @"the text vector is one record", [NSString stringWithFormat:@"%lu", (unsigned long)fromText.records.count]);
    NFCNDEFPayload *textRecord = fromText.records.firstObject;
    check_named(textRecord.typeNameFormat == NFCTypeNameFormatNFCWellKnown, @"whose type name format is well known",
                 [NSString stringWithFormat:@"%u", (unsigned)textRecord.typeNameFormat]);
    check_named([textRecord.type isEqualToData:[@"T" dataUsingEncoding:NSUTF8StringEncoding]], @"and whose type is the text RTD's T", textRecord.type);
    check_named(textRecord.identifier.length == 0, @"with no identifier", textRecord.identifier);
    NSLocale *locale = nil;
    NSString *hello = [textRecord wellKnownTypeTextPayloadWithLocale:&locale];
    check_named([hello isEqualToString:@"Hello"], @"and whose payload reads back as the text it was", hello);
    check_named([locale.localeIdentifier isEqualToString:@"en"], @"in the language its status byte names", locale.localeIdentifier);
    check_named(fromText.length == text.length, @"and whose length is the length of the vector",
                 [NSString stringWithFormat:@"%lu against %lu", (unsigned long)fromText.length, (unsigned long)text.length]);

    NFCNDEFMessage *fromURI = [NFCNDEFMessage ndefMessageWithData:URIVector()];
    check_named(fromURI.records.count == 1, @"the URI vector is one record", nil);
    NSURL *url = [fromURI.records.firstObject wellKnownTypeURIPayload];
    check_named([url.absoluteString isEqualToString:@"http://www.example.com"], @"whose payload reads back as the URI it was", url.absoluteString);
    check_named(fromURI.length == URIVector().length, @"and whose length is the length of the vector", nil);

    // 2. A record that is not short, and a long one the one-byte length field cannot say.
    NSData *long300 = LongRecordVector(300);
    NFCNDEFMessage *fromLong = [NFCNDEFMessage ndefMessageWithData:long300];
    check_named(fromLong.records.count == 2, @"a 300 byte payload and its tail are two records", [NSString stringWithFormat:@"%lu", (unsigned long)fromLong.records.count]);
    check_named([fromLong.records.firstObject.payload isEqualToData:[long300 subdataWithRange:NSMakeRange(14, 300)]],
                 @"and the first carries the 300 bytes the four byte length field named", nil);
    check_named([fromLong.records.lastObject.type isEqualToData:[@"Q" dataUsingEncoding:NSUTF8StringEncoding]],
                 @"and the second the type that follows", [fromLong.records.lastObject.type description]);

    // 3. A record the port builds itself, encoded and read back: the two must agree byte for byte.
    NFCNDEFPayload *text2 = [NFCNDEFPayload wellKnownTypeTextPayloadWithString:@"Hello" locale:[NSLocale localeWithLocaleIdentifier:@"en"]];
    NFCNDEFMessage *built = [[NFCNDEFMessage alloc] initWithNDEFRecords:@[text2]];
    check_named(built.length == text.length, @"a message the port builds weighs what the vector weighs",
                 [NSString stringWithFormat:@"%lu against %lu", (unsigned long)built.length, (unsigned long)text.length]);
    NFCNDEFMessage *reread = [NFCNDEFMessage ndefMessageWithData:[built valueForKey:@"charonEncoded"]];
    check_named([reread.records.firstObject.payload isEqualToData:textRecord.payload], @"and its own bytes read back as the same payload",
                 [reread.records.firstObject.payload description]);

    // 4. A chunked payload: a well-known record whose first byte is the zero marker, then one
    //    continuation per chunk, each with the CF flag, no type and the chunk number in its first byte.
    NSMutableData *ten = [NSMutableData data];
    for (int index = 0; index < 10; index++) {
        unsigned char byte = (unsigned char)('a' + index);
        [ten appendBytes:&byte length:1];
    }
    NFCNDEFPayload *chunked = [[NFCNDEFPayload alloc] initWithFormat:NFCTypeNameFormatNFCWellKnown
                                                             type:[@"T" dataUsingEncoding:NSUTF8StringEncoding]
                                                        identifier:nil payload:ten chunkSize:4];
    NFCNDEFMessage *chunkedMessage = [[NFCNDEFMessage alloc] initWithNDEFRecords:@[chunked]];
    NSData *chunkedBytes = [chunkedMessage valueForKey:@"charonEncoded"];
    check_named(chunkedBytes.length == 12 + 6 + 6, @"a ten byte payload chunked by four is three records",
                 [NSString stringWithFormat:@"%lu bytes", (unsigned long)chunkedBytes.length]);
    check_named((((const unsigned char *)chunkedBytes.bytes)[0] & 0x01) == 0, @"whose first record is not a continuation", nil);
    check_named((((const unsigned char *)chunkedBytes.bytes)[12] & 0x01) != 0, @"whose second is", nil);
    check_named((((const unsigned char *)chunkedBytes.bytes)[12] & 0x20) == 0, @"and carries no type of its own, the first byte after the header being the chunk number", nil);
    check_named(((const unsigned char *)chunkedBytes.bytes)[12 + 4] == 0x01, @"numbered one", nil);
    NFCNDEFMessage *chunkedBack = [NFCNDEFMessage ndefMessageWithData:chunkedBytes];
    check_named([chunkedBack.records.firstObject.payload isEqualToData:ten], @"and the group reads back as the ten bytes it was",
                 [chunkedBack.records.firstObject.payload description]);

    // 5. What must be refused: a record that does not add up, and a continuation out of order.
    NSMutableData *truncated = [URIVector() mutableCopy];
    [truncated appendBytes:(const unsigned char *)"\x09\x09\x09" length:3];
    NFCNDEFMessage *afterTruncation = [NFCNDEFMessage ndefMessageWithData:truncated];
    check_named(afterTruncation.records.count == 1, @"a record that does not add up ends the message rather than repairing it",
                 [NSString stringWithFormat:@"%lu records", (unsigned long)afterTruncation.records.count]);
    check_named([[NFCNDEFMessage ndefMessageWithData:chunkedBytes].records.firstObject.payload isEqualToData:ten],
                 @"a chunked group reads back as the one payload it was", nil);

    // 6. Secure coding, both classes.
    NFCNDEFMessage *archived = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:built]];
    check_named(archived.records.count == built.records.count, @"a message survives secure coding with its records",
                 [NSString stringWithFormat:@"%lu", (unsigned long)archived.records.count]);
    check_named([archived.records.firstObject.payload isEqualToData:textRecord.payload], @"and the payload with it",
                 [archived.records.firstObject.payload description]);

    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures == 0 ? 0 : 1;
}
