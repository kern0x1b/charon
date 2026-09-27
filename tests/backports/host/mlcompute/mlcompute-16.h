// The members of MLCompute 14 that MLCompute 26's headers no longer declare, put back so that one program
// can be written against the surface this port carries and run beside both the host's framework and the
// port's own. Each is a category with declarations and no implementation, so the framework's own code
// answers for the system build and the port's answers for the port build, and nothing here is a second
// copy of a declaration that still exists: where the SDK still declares a member, this file says nothing
// about it.
#import <Foundation/Foundation.h>
#import <MLCompute/MLCompute.h>

@interface MLCTensor (CharonSixteen)
// Removed in MLCompute 26, present in 14 and still in the framework on the host (measured: the class
// responds to it and answers a tensor labelled data0).
+ (instancetype)tensorWithShape:(NSArray<NSNumber *> *)shape;
@end

// MLCompute's own header marks +new and -init unavailable on the classes below. The framework carries them
// all and a program can reach them through a Class, so the cases ask that way rather than by a name the
// compiler refuses.
static id CharonNew(Class cls)
{
    return [[cls alloc] init];
}

static id CharonNewOf(NSString *name)
{
    return CharonNew(NSClassFromString(name));
}
