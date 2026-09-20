#import <CoreNFC/CoreNFC.h>

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

NSErrorDomain const NFCErrorDomain = @"NFCError";

@implementation NFCReaderSession

@dynamic ready, alertMessage, delegate, sessionQueue;

+ (BOOL)readingAvailable
{
    return NO;
}

@end

@implementation NFCNDEFReaderSession

@end
