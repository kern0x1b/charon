// AVContentKeyResponse103.m - AVContentKeyResponse as of 10.3, with its three factories as they came: FairPlay
// Streaming key response data (10.3), clear key data with its initialization vector (11.0) and authorization token
// data (13.0). A response is the answer an application gives a content key request, and the request that takes it
// (-processContentKeyResponse:) is a content key session's, which 6.1.3 does not carry (see
// facts/AVFoundation/ContentKeyValues.md). So the object is carried as the value it is, and it has no reader: the
// header declares no property on it, and nothing the port does reads what it holds.
//
// Measured by tests/backports/host/avf-contentkey-values: each factory returns an object of the class for any data
// it is given, nil included, and refuses nothing. The host builds one of three subclasses, one per factory; the port
// builds one class with the three values in its own fields, which is not visible through the header, so a probe
// asks each answer as "is a response" rather than by the subclass name.
#import <AVFoundation/AVContentKeySession.h>
#import <Foundation/Foundation.h>

@implementation AVContentKeyResponse {
    NSData *_keyData;
    NSData *_initializationVector;
    NSData *_authorizationTokenData;
}

+ (instancetype)contentKeyResponseWithFairPlayStreamingKeyResponseData:(NSData *)keyResponseData
{
    return [[self alloc] initWithKeyData:keyResponseData initializationVector:nil authorizationTokenData:nil];
}

+ (instancetype)contentKeyResponseWithClearKeyData:(NSData *)clearKeyData initializationVector:(NSData *)initializationVector
{
    return [[self alloc] initWithKeyData:clearKeyData initializationVector:initializationVector authorizationTokenData:nil];
}

+ (instancetype)contentKeyResponseWithAuthorizationTokenData:(NSData *)authorizationTokenData
{
    return [[self alloc] initWithKeyData:nil initializationVector:nil authorizationTokenData:authorizationTokenData];
}

// The three values are kept as given, copied so a caller's mutable data changes nothing already made. A nil or empty
// value is kept as it is: the host refuses none of them at the factory, and nothing on this release reads them back.
- (instancetype)initWithKeyData:(NSData *)keyData
                  initializationVector:(NSData *)initializationVector
                authorizationTokenData:(NSData *)authorizationTokenData
{
    self = [super init];
    if (self) {
        _keyData = [keyData copy];
        _initializationVector = [initializationVector copy];
        _authorizationTokenData = [authorizationTokenData copy];
    }
    return self;
}

@end
