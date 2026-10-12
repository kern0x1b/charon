// matterdifferential/shutdown-controller.h - the controller the checks stop before they ask a cluster anything.
//
// behaviour.m and commands.m both need the framework with a controller on a new fabric and no node to reach. The
// storage and the keypair are what behaviour.m always used; they live here so commands.m does not carry a second copy.
// The caller takes its device from the controller and then shuts it down: from then on every request answers with the
// framework's own "this controller cannot answer" path.
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import <Security/Security.h>

@interface BehaviourStorage : NSObject <MTRStorage>
@property (nonatomic, strong) NSMutableDictionary *table;
@end
@implementation BehaviourStorage
- (instancetype)init { self = [super init]; _table = [NSMutableDictionary dictionary]; return self; }
- (NSData *)storageDataForKey:(NSString *)key { @synchronized (self) { return self.table[key]; } }
- (BOOL)setStorageData:(NSData *)value forKey:(NSString *)key { @synchronized (self) { self.table[key] = value; } return YES; }
- (BOOL)removeStorageDataForKey:(NSString *)key { @synchronized (self) { [self.table removeObjectForKey:key]; } return YES; }
@end

// A software P-256 key: the framework asks the operational signer for a public key and a signature while it
// creates a fabric, and nothing else here signs anything.
@interface BehaviourKeypair : NSObject <MTRKeypair>
@property (nonatomic) SecKeyRef privateKey;
@property (nonatomic) SecKeyRef publicKeyRef;
@end
@implementation BehaviourKeypair
- (instancetype)init
{
    self = [super init];
    NSDictionary *attributes = @{(id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
                                 (id)kSecAttrKeySizeInBits: @256};
    CFErrorRef error = NULL;
    _privateKey = SecKeyCreateRandomKey((CFDictionaryRef)attributes, &error);
    if (!_privateKey) {
        return nil;
    }
    _publicKeyRef = SecKeyCopyPublicKey(_privateKey);
    return self;
}
- (SecKeyRef)copyPublicKey { return (SecKeyRef)CFRetain(_publicKeyRef); }
- (SecKeyRef)publicKey { return _publicKeyRef; }
- (NSData *)signMessageECDSA_DER:(NSData *)message
{
    CFErrorRef error = NULL;
    CFDataRef signature = SecKeyCreateSignature(_privateKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                (CFDataRef)message, &error);
    return (__bridge_transfer NSData *)signature;
}
@end

// The factory started and a controller created on a new fabric, not yet stopped. nil, with *error set, when either
// step fails.
static MTRDeviceController *StartControllerOnNewFabric(NSError **error)
{
    BehaviourStorage *storage = [[BehaviourStorage alloc] init];
    MTRDeviceControllerFactoryParams *factoryParams =
        [[MTRDeviceControllerFactoryParams alloc] initWithStorage:storage];
    MTRDeviceControllerFactory *factory = [MTRDeviceControllerFactory sharedInstance];
    if (![factory startControllerFactory:factoryParams error:error]) {
        return nil;
    }
    uint8_t ipk[16] = {0};
    MTRDeviceControllerStartupParams *startup = [[MTRDeviceControllerStartupParams alloc]
        initWithIPK:[NSData dataWithBytes:ipk length:sizeof(ipk)] fabricID:@1
          nocSigner:[[BehaviourKeypair alloc] init]];
    startup.vendorID = @0xFFF1;
    return [factory createControllerOnNewFabric:startup error:error];
}
