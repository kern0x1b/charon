// The one class the port's voice control needs and the harness cannot bring: its superclass.
//
// Apple's own CarPlay is in this binary (the differential links it), so the port's own `CPTemplate`
// is renamed onto `charonHost_CPTemplate` when the port's sources are compiled -- the renames move
// the PORT's references and this file's whole job is to declare what they moved onto. It is the same
// arrangement `tests/backports/host/passkit/port-classes.m` uses for the four PassKit classes, and for
// the same reason: two classes of one name cannot be in one process.
//
// What it has to answer is the two coder calls the port's template makes on its superclass, because
// `CPTemplate` conforms to NSSecureCoding in the SDK and NSObject's own superclass does not declare
// a coder at all.

#import <Foundation/Foundation.h>

@interface charonHost_CPTemplate : NSObject
@end

@implementation charonHost_CPTemplate

- (void)encodeWithCoder:(NSCoder *)coder
{
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super init];
}

@end
