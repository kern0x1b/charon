// ARKitConstants16.m - the constants of the 16.0 headers.
//
// Split from ARKitConstants.m because an object carries the API of one release. These are the nine
// joint names a body anchor's geometry is indexed by, which arrived with the body tracking the 16.0
// headers declare in ARConfiguration4.m.

#import <ARKit/ARKit.h>

#pragma mark - The body's joints

NSString * const ARSkeletonJointNameRoot = @"root";
NSString * const ARSkeletonJointNameHead = @"head";
NSString * const ARSkeletonJointNameLeftShoulder = @"left_shoulder";
NSString * const ARSkeletonJointNameRightShoulder = @"right_shoulder";
NSString * const ARSkeletonJointNameLeftHand = @"left_hand";
NSString * const ARSkeletonJointNameRightHand = @"right_hand";
NSString * const ARSkeletonJointNameLeftFoot = @"left_foot";
NSString * const ARSkeletonJointNameRightFoot = @"right_foot";
