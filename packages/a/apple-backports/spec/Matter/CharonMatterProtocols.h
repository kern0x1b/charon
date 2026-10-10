// CharonMatterProtocols.h - the Matter protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <Matter/Matter.h> for that body, and
#import <Matter/Matter.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@class MTRCommissionableBrowserResult;
API_AVAILABLE(ios(17.0))
@protocol MTRCommissionableBrowserDelegate <NSObject>
- (void)controller:(MTRDeviceController * _Nonnull)controller didFindCommissionableDevice:(MTRCommissionableBrowserResult * _Nonnull)device;
- (void)controller:(MTRDeviceController * _Nonnull)controller didRemoveCommissionableDevice:(MTRCommissionableBrowserResult * _Nonnull)device;
@end

@class MTRCommissioneeInfo;
@class MTRCommissioningOperation;
@class MTRMetrics;
@class MTRNetworkCommissioningClusterThreadInterfaceScanResultStruct;
@class MTRNetworkCommissioningClusterWiFiInterfaceScanResultStruct;
API_AVAILABLE(ios(26.2))
@protocol MTRCommissioningDelegate <NSObject>
@optional
- (void)commissioning:(MTRCommissioningOperation * _Nonnull)commissioning readCommissioneeInfo:(MTRCommissioneeInfo * _Nonnull)info;
@required
- (void)commissioning:(MTRCommissioningOperation * _Nonnull)commissioning completedDeviceAttestation:(MTRDeviceAttestationDeviceInfo * _Nonnull)attestationDeviceInfo error:(NSError * _Nullable)error completion:(dispatch_block_t  _Nonnull)completion;
@optional
- (void)commissioning:(MTRCommissioningOperation * _Nonnull)commissioning needsWiFiCredentialsWithScanResults:(NSArray<MTRNetworkCommissioningClusterWiFiInterfaceScanResultStruct *> * _Nullable)networks error:(NSError * _Nullable)error completion:(void (^ _Nonnull)(NSData * _Nonnull, NSData * _Nullable))completion;
- (void)commissioning:(MTRCommissioningOperation * _Nonnull)commissioning needsThreadCredentialsWithScanResults:(NSArray<MTRNetworkCommissioningClusterThreadInterfaceScanResultStruct *> * _Nullable)networks error:(NSError * _Nullable)error completion:(void (^ _Nonnull)(NSData * _Nonnull))completion;
- (void)commissioningStartingNetworkScan:(MTRCommissioningOperation * _Nonnull)commissioning;
- (void)commissioningProvisionedNetworkCredentials:(MTRCommissioningOperation * _Nonnull)commissioning;
- (void)commissioning:(MTRCommissioningOperation * _Nonnull)commissioning failedWithError:(NSError * _Nonnull)error metrics:(MTRMetrics * _Nonnull)metrics;
- (void)commissioning:(MTRCommissioningOperation * _Nonnull)commissioning succeededForNodeID:(NSNumber * _Nonnull)nodeID metrics:(MTRMetrics * _Nonnull)metrics;
@end

@protocol MTRDeviceAttestationDelegate;

@protocol MTRDeviceControllerDelegate;

@protocol MTRDeviceControllerServerProtocol;

typedef enum MTRStorageSecurityLevel MTRStorageSecurityLevel;
typedef enum MTRStorageSharingType MTRStorageSharingType;
API_AVAILABLE(ios(17.6))
@protocol MTRDeviceControllerStorageDelegate <NSObject>
- (id<NSSecureCoding> _Nullable)controller:(MTRDeviceController * _Nonnull)controller valueForKey:(NSString * _Nonnull)key securityLevel:(MTRStorageSecurityLevel)securityLevel sharingType:(MTRStorageSharingType)sharingType;
- (BOOL)controller:(MTRDeviceController * _Nonnull)controller storeValue:(id<NSSecureCoding>  _Nonnull)value forKey:(NSString * _Nonnull)key securityLevel:(MTRStorageSecurityLevel)securityLevel sharingType:(MTRStorageSharingType)sharingType;
- (BOOL)controller:(MTRDeviceController * _Nonnull)controller removeValueForKey:(NSString * _Nonnull)key securityLevel:(MTRStorageSecurityLevel)securityLevel sharingType:(MTRStorageSharingType)sharingType;
@optional
- (NSDictionary<NSString *,id<NSSecureCoding>> * _Nullable)valuesForController:(MTRDeviceController * _Nonnull)controller securityLevel:(MTRStorageSecurityLevel)securityLevel sharingType:(MTRStorageSharingType)sharingType;
- (BOOL)controller:(MTRDeviceController * _Nonnull)controller storeValues:(NSDictionary<NSString *,id<NSSecureCoding>> * _Nonnull)values securityLevel:(MTRStorageSecurityLevel)securityLevel sharingType:(MTRStorageSharingType)sharingType;
@end

@protocol MTRDeviceDelegate;

@protocol MTRDevicePairingDelegate;

@protocol MTRKeypair;

@protocol MTRNOCChainIssuer;

@protocol MTROTAProviderDelegate;

@protocol MTROperationalCertificateIssuer;

@protocol MTRPersistentStorageDelegate;

@protocol MTRStorage;

API_AVAILABLE(ios(18.2))
@protocol MTRXPCClientProtocol <NSObject, MTRXPCClientProtocol_MTRDevice, MTRXPCClientProtocol_MTRDeviceController>
@end

API_AVAILABLE(ios(18.2))
@protocol MTRXPCClientProtocol_MTRDevice <NSObject>
- (void)device:(NSNumber * _Nonnull)nodeID stateChanged:(MTRDeviceState)state;
- (void)device:(NSNumber * _Nonnull)nodeID receivedAttributeReport:(NSArray<NSDictionary<NSString *,id> *> * _Nonnull)attributeReport;
- (void)device:(NSNumber * _Nonnull)nodeID receivedEventReport:(NSArray<NSDictionary<NSString *,id> *> * _Nonnull)eventReport;
- (void)deviceBecameActive:(NSNumber * _Nonnull)nodeID;
- (void)deviceCachePrimed:(NSNumber * _Nonnull)nodeID;
- (void)deviceConfigurationChanged:(NSNumber * _Nonnull)nodeID;
- (void)device:(NSNumber * _Nonnull)nodeID internalStateUpdated:(NSDictionary * _Nonnull)dictionary;
@end

API_AVAILABLE(ios(18.2))
@protocol MTRXPCClientProtocol_MTRDeviceController <NSObject>
@optional
- (void)controller:(NSUUID * _Nonnull)controller controllerConfigurationUpdated:(NSDictionary * _Nonnull)configuration;
@end

API_AVAILABLE(ios(18.3))
@protocol MTRXPCServerProtocol <NSObject, MTRXPCServerProtocol_MTRDevice, MTRXPCServerProtocol_MTRDeviceController>
@optional
- (void)deviceController:(NSUUID * _Nonnull)controller checkInWithContext:(NSDictionary * _Nonnull)context;
@end

@class MTRAttributeRequestPath;
@class MTRCommandWithRequiredResponse;
typedef enum MTRDiagnosticLogType MTRDiagnosticLogType;
API_AVAILABLE(ios(18.2))
@protocol MTRXPCServerProtocol_MTRDevice <NSObject>
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID getStateWithReply:(void (^ _Nonnull)(MTRDeviceState))reply;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID getDeviceCachePrimedWithReply:(void (^ _Nonnull)(BOOL))reply;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID getEstimatedStartTimeWithReply:(void (^ _Nonnull)(NSDate * _Nullable))reply;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID getEstimatedSubscriptionLatencyWithReply:(void (^ _Nonnull)(NSNumber * _Nullable))reply;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID readAttributeWithEndpointID:(NSNumber * _Nonnull)endpointID clusterID:(NSNumber * _Nonnull)clusterID attributeID:(NSNumber * _Nonnull)attributeID params:(MTRReadParams * _Nullable)params withReply:(void (^ _Nonnull)(NSDictionary<NSString *,id> * _Nullable))reply;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID writeAttributeWithEndpointID:(NSNumber * _Nonnull)endpointID clusterID:(NSNumber * _Nonnull)clusterID attributeID:(NSNumber * _Nonnull)attributeID value:(id  _Nonnull)value expectedValueInterval:(NSNumber * _Nullable)expectedValueInterval timedWriteTimeout:(NSNumber * _Nullable)timeout;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID readAttributePaths:(NSArray<MTRAttributeRequestPath *> * _Nonnull)attributePaths withReply:(void (^ _Nonnull)(NSArray<NSDictionary<NSString *,id> *> * _Nonnull))reply;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID invokeCommandWithEndpointID:(NSNumber * _Nonnull)endpointID clusterID:(NSNumber * _Nonnull)clusterID commandID:(NSNumber * _Nonnull)commandID commandFields:(id  _Nonnull)commandFields expectedValues:(NSArray<NSDictionary<NSString *,id> *> * _Nullable)expectedValues expectedValueInterval:(NSNumber * _Nullable)expectedValueInterval timedInvokeTimeout:(NSNumber * _Nullable)timeout serverSideProcessingTimeout:(NSNumber * _Nullable)serverSideProcessingTimeout completion:(MTRDeviceResponseHandler  _Nonnull)completion;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID openCommissioningWindowWithSetupPasscode:(NSNumber * _Nonnull)setupPasscode discriminator:(NSNumber * _Nonnull)discriminator duration:(NSNumber * _Nonnull)duration completion:(MTRDeviceOpenCommissioningWindowHandler  _Nonnull)completion;
- (void)downloadLogOfType:(MTRDiagnosticLogType)type nodeID:(NSNumber * _Nonnull)nodeID timeout:(NSTimeInterval)timeout completion:(void (^ _Nonnull)(NSURL * _Nullable, NSError * _Nullable))completion;
@optional
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID downloadLogOfType:(MTRDiagnosticLogType)type timeout:(NSTimeInterval)timeout completion:(void (^ _Nonnull)(NSURL * _Nullable, NSError * _Nullable))completion;
- (void)deviceController:(NSUUID * _Nonnull)controller nodeID:(NSNumber * _Nonnull)nodeID invokeCommands:(NSArray<NSArray<MTRCommandWithRequiredResponse *> *> * _Nonnull)commands completion:(MTRDeviceResponseHandler  _Nonnull)completion;
@end

API_AVAILABLE(ios(18.3))
@protocol MTRXPCServerProtocol_MTRDeviceController <NSObject>
@optional
- (void)deviceController:(NSUUID * _Nonnull)controller deleteNodeID:(NSNumber * _Nonnull)nodeID;
- (void)deviceController:(NSUUID * _Nonnull)controller registerNodeID:(NSNumber * _Nonnull)nodeID;
- (void)deviceController:(NSUUID * _Nonnull)controller unregisterNodeID:(NSNumber * _Nonnull)nodeID;
- (void)deviceController:(NSUUID * _Nonnull)controller updateControllerConfiguration:(NSDictionary * _Nonnull)controllerState;
- (void)deviceController:(NSUUID * _Nonnull)controller getNodesWithStoredDataWithReply:(void (^ _Nonnull)(NSArray<NSNumber *> * _Nonnull))reply;
@end
