// HMAccessorySetupPayload, of iOS 13.0: the initialiser that takes the accessory's ownership token
// along with its setup payload URL.
//
// One release's API per object file. This file is of 13.0 alone; the 11.3 initialiser of the same class
// is a separate object in HMAccessorySetupPayload11_3.m, and a band from 13.0 up links both, because the
// 11.3 one is API the device has and this one is API added to it.
//
// The 26.2 header, HMAccessorySetupPayload.h:48-57:
//   /*! Creates a new accessory setup payload to add an accessory to the home.
//    * @param setupPayloadURL The HomeKit setup payload URL for the accessory being added to the home.`
//    * @param ownershipToken The token proving ownership of the accessory being added to the home.
//    * @return Returns an accessory setup payload object if successful or nil on error. */
//   - (nullable instancetype)initWithURL:(NSURL *)setupPayloadURL
//                    ownershipToken:(nullable HMAccessoryOwnershipToken *)ownershipToken
//        API_AVAILABLE(ios(13.0))API_UNAVAILABLE(macos, watchos, tvos);
//
// **The difference from 11.3 is the token, and it is a difference in what a device can check.** With the
// token the device can prove the caller owns the accessory before it adds it; without one it adds the
// accessory on the strength of the setup code alone. The port records which of the two a payload was
// made with, and records the token opaquely, because HMAccessoryOwnershipToken is a class the port does
// not carry -- see the facts file -- and there is nothing here that could make one.
//
// **What the port cannot do.** Verifying that the token proves ownership is the accessory's and the
// daemon's work; the port has neither the accessory nor a HomeKit transport, so it neither sends the
// token anywhere nor opens a connection. Nothing in this file touches the network or a real HomeKit store
// on this machine.

#import "CharonHomeKitInternal.h"

@interface HMAccessorySetupPayload ()
// The token is held as the SDK's own type and read only for its presence, and that is deliberate rather
// than a shortcut: the port does not carry HMAccessoryOwnershipToken, so it cannot inspect what is inside
// one, and pretending otherwise by copying its bytes would claim a check the port never made. A nil token
// is not an error here even though the URL is not allowed to be nil -- the header types the token
// nullable, and a caller that has none is answering a question the header lets it leave open.
@property (nonatomic, strong, nullable) HMAccessoryOwnershipToken *charon_ownershipToken;
@end

@implementation HMAccessorySetupPayload

// charon_setupPayloadURL belongs to the 11.3 object: the same ivar, one class, two release objects, and
// a band from 13.0 up links both. @dynamic and not @synthesize, and that is the whole reason for the
// choice: a second @synthesize of a property another object of the same class already synthesises is a
// duplicate definition, while auto-synthesis here would satisfy the flag by creating a SECOND ivar for
// the same property -- two objects linked into one binary with two different payloads' worth of URL, and
// the 13.0 initialiser's URL invisible to the 11.3 object's getter. @dynamic says what is true: this
// object does not define the accessors, the 11.3 object beside it does.
@dynamic charon_setupPayloadURL;

@synthesize charon_ownershipToken = _charon_ownershipToken;

- (instancetype)initWithURL:(NSURL *)setupPayloadURL
         ownershipToken:(HMAccessoryOwnershipToken *)ownershipToken
{
    // The header makes the URL nonnull here and the return nullable, and those two go together: this
    // overload was added for a caller that has a real setup payload URL, and the documented nil comes
    // back when it does not have one.
    if (setupPayloadURL == nil) {
        return nil;
    }
    self = [super init];
    if (self) {
        // The URL goes into the 11.3 object's own storage, through the setter that object defines, so a
        // payload read by either object's accessor sees the URL it was made with.
        self.charon_setupPayloadURL = setupPayloadURL;
        _charon_ownershipToken = ownershipToken;
    }
    return self;
}

@end
