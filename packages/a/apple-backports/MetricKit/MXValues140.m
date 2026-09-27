#import "CharonMetricKit.h"
#import "CharonMetricValue.h"
// The value classes of this framework that arrived in iOS 14.0, one file for that release alone: an
// object carries API that arrived in one release, so this is the iOS 14.0 half and no two of them are one
// object.

@implementation MXAnimationMetric (CharonMetricKit)
@dynamic hitchTimeRatio;

CHARON_VALUE_PROPERTY(NSMeasurement *, hitchTimeRatio)

@end
@implementation MXAppExitMetric
@dynamic foregroundExitData, backgroundExitData;

CHARON_VALUE_PROPERTY(MXForegroundExitData *, foregroundExitData)
CHARON_VALUE_PROPERTY(MXBackgroundExitData *, backgroundExitData)

@end
@implementation MXBackgroundExitData
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@dynamic cumulativeNormalAppExitCount, cumulativeMemoryResourceLimitExitCount, cumulativeCPUResourceLimitExitCount, cumulativeMemoryPressureExitCount, cumulativeBadAccessExitCount, cumulativeAbnormalExitCount, cumulativeIllegalInstructionExitCount, cumulativeAppWatchdogExitCount, cumulativeSuspendedWithLockedFileExitCount, cumulativeBackgroundTaskAssertionTimeoutExitCount;

CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeNormalAppExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeMemoryResourceLimitExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeCPUResourceLimitExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeMemoryPressureExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeBadAccessExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeAbnormalExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeIllegalInstructionExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeAppWatchdogExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeSuspendedWithLockedFileExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeBackgroundTaskAssertionTimeoutExitCount)

@end
@implementation MXCPUExceptionDiagnostic
@dynamic callStackTree, totalCPUTime, totalSampledTime;

CHARON_VALUE_PROPERTY(MXCallStackTree *, callStackTree)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalCPUTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalSampledTime)

@end
@implementation MXCallStackTree
@end

@implementation MXDiskWriteExceptionDiagnostic
@dynamic callStackTree, totalWritesCaused;

CHARON_VALUE_PROPERTY(MXCallStackTree *, callStackTree)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalWritesCaused)

@end
@implementation MXCrashDiagnostic (CharonMetricKit)
@dynamic exceptionReason;

CHARON_VALUE_PROPERTY(MXCrashDiagnosticObjectiveCExceptionReason *, exceptionReason)

@end
@implementation MXDiagnostic
@end
@implementation MXDiagnosticPayload
@dynamic cpuExceptionDiagnostics, diskWriteExceptionDiagnostics, hangDiagnostics, appLaunchDiagnostics, crashDiagnostics, timeStampBegin, timeStampEnd;

CHARON_VALUE_PROPERTY(NSArray *, cpuExceptionDiagnostics)
CHARON_VALUE_PROPERTY(NSArray *, diskWriteExceptionDiagnostics)
CHARON_VALUE_PROPERTY(NSArray *, hangDiagnostics)
CHARON_VALUE_PROPERTY(NSArray *, appLaunchDiagnostics)
CHARON_VALUE_PROPERTY(NSArray *, crashDiagnostics)
CHARON_VALUE_PROPERTY(NSDate *, timeStampBegin)
CHARON_VALUE_PROPERTY(NSDate *, timeStampEnd)

@end

@implementation MXForegroundExitData
@dynamic cumulativeNormalAppExitCount, cumulativeMemoryResourceLimitExitCount, cumulativeBadAccessExitCount, cumulativeAbnormalExitCount, cumulativeIllegalInstructionExitCount, cumulativeAppWatchdogExitCount;

CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeNormalAppExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeMemoryResourceLimitExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeBadAccessExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeAbnormalExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeIllegalInstructionExitCount)
CHARON_SCALAR_PROPERTY(NSUInteger, cumulativeAppWatchdogExitCount)

@end
@implementation MXHangDiagnostic
@dynamic callStackTree, hangDuration;

CHARON_VALUE_PROPERTY(MXCallStackTree *, callStackTree)
CHARON_VALUE_PROPERTY(NSMeasurement *, hangDuration)

@end
