#import "CharonMetricKit.h"
#import "CharonMetricValue.h"


@implementation MXAnimationMetric
@dynamic scrollHitchTimeRatio;

CHARON_VALUE_PROPERTY(NSMeasurement *, scrollHitchTimeRatio)

@end

@implementation MXAnimationMetric (CharonMetricKit)
@dynamic hitchTimeRatio;

CHARON_VALUE_PROPERTY(NSMeasurement *, hitchTimeRatio)

@end

@implementation MXAppExitMetric
@dynamic foregroundExitData, backgroundExitData;

CHARON_VALUE_PROPERTY(MXForegroundExitData *, foregroundExitData)
CHARON_VALUE_PROPERTY(MXBackgroundExitData *, backgroundExitData)

@end

@implementation MXAppLaunchDiagnostic
@dynamic callStackTree, launchDuration;

CHARON_VALUE_PROPERTY(MXCallStackTree *, callStackTree)
CHARON_VALUE_PROPERTY(NSMeasurement *, launchDuration)

@end

@implementation MXAppLaunchMetric
@dynamic histogrammedTimeToFirstDraw, histogrammedApplicationResumeTime, histogrammedOptimizedTimeToFirstDraw, histogrammedExtendedLaunch;

CHARON_VALUE_PROPERTY(MXHistogram *, histogrammedTimeToFirstDraw)
CHARON_VALUE_PROPERTY(MXHistogram *, histogrammedApplicationResumeTime)
CHARON_VALUE_PROPERTY(MXHistogram *, histogrammedOptimizedTimeToFirstDraw)
CHARON_VALUE_PROPERTY(MXHistogram *, histogrammedExtendedLaunch)

@end

@implementation MXAppResponsivenessMetric
@dynamic histogrammedApplicationHangTime;

CHARON_VALUE_PROPERTY(MXHistogram *, histogrammedApplicationHangTime)

@end

@implementation MXAppRunTimeMetric
@dynamic cumulativeForegroundTime, cumulativeBackgroundTime, cumulativeBackgroundAudioTime, cumulativeBackgroundLocationTime;

CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeForegroundTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeBackgroundTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeBackgroundAudioTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeBackgroundLocationTime)

@end

@implementation MXAverage
@dynamic averageMeasurement, sampleCount, standardDeviation;

CHARON_VALUE_PROPERTY(NSMeasurement *, averageMeasurement)
CHARON_SCALAR_PROPERTY(NSInteger, sampleCount)
CHARON_DOUBLE_PROPERTY(double, standardDeviation)


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

@implementation MXCPUMetric
@dynamic cumulativeCPUTime, cumulativeCPUInstructions;

CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeCPUTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeCPUInstructions)

@end

@implementation MXCellularConditionMetric
@dynamic histogrammedCellularConditionTime;

CHARON_VALUE_PROPERTY(MXHistogram *, histogrammedCellularConditionTime)

@end

@implementation MXCrashDiagnostic
@dynamic callStackTree, terminationReason, virtualMemoryRegionInfo, exceptionType, exceptionCode, signal;

CHARON_VALUE_PROPERTY(MXCallStackTree *, callStackTree)
CHARON_VALUE_PROPERTY(NSString *, terminationReason)
CHARON_VALUE_PROPERTY(NSString *, virtualMemoryRegionInfo)
CHARON_VALUE_PROPERTY(NSNumber *, exceptionType)
CHARON_VALUE_PROPERTY(NSNumber *, exceptionCode)
CHARON_VALUE_PROPERTY(NSNumber *, signal)

@end

@implementation MXCrashDiagnostic (CharonMetricKit)
@dynamic exceptionReason;

CHARON_VALUE_PROPERTY(MXCrashDiagnosticObjectiveCExceptionReason *, exceptionReason)

@end

@implementation MXCrashDiagnosticObjectiveCExceptionReason
@dynamic composedMessage, formatString, arguments, exceptionType, className, exceptionName;

CHARON_VALUE_PROPERTY(NSString *, composedMessage)
CHARON_VALUE_PROPERTY(NSString *, formatString)
CHARON_VALUE_PROPERTY(NSArray *, arguments)
CHARON_VALUE_PROPERTY(NSString *, exceptionType)
CHARON_VALUE_PROPERTY(NSString *, className)
CHARON_VALUE_PROPERTY(NSString *, exceptionName)


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

@implementation MXDiskIOMetric
@dynamic cumulativeLogicalWrites;

CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeLogicalWrites)

@end

@implementation MXDiskSpaceUsageMetric
@dynamic totalBinaryFileSize, totalBinaryFileCount, totalDataFileSize, totalDataFileCount, totalCacheFolderSize, totalCloneSize, totalDiskSpaceUsedSize, totalDiskSpaceCapacity;

CHARON_VALUE_PROPERTY(NSMeasurement *, totalBinaryFileSize)
CHARON_SCALAR_PROPERTY(NSInteger, totalBinaryFileCount)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalDataFileSize)
CHARON_SCALAR_PROPERTY(NSInteger, totalDataFileCount)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalCacheFolderSize)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalCloneSize)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalDiskSpaceUsedSize)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalDiskSpaceCapacity)

@end

@implementation MXDiskWriteExceptionDiagnostic
@dynamic callStackTree, totalWritesCaused;

CHARON_VALUE_PROPERTY(MXCallStackTree *, callStackTree)
CHARON_VALUE_PROPERTY(NSMeasurement *, totalWritesCaused)

@end

@implementation MXDisplayMetric
@dynamic averagePixelLuminance;

CHARON_VALUE_PROPERTY(MXAverage *, averagePixelLuminance)

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

@implementation MXGPUMetric
@dynamic cumulativeGPUTime;

CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeGPUTime)

@end

@implementation MXHangDiagnostic
@dynamic callStackTree, hangDuration;

CHARON_VALUE_PROPERTY(MXCallStackTree *, callStackTree)
CHARON_VALUE_PROPERTY(NSMeasurement *, hangDuration)

@end

@implementation MXHistogram
@dynamic totalBucketCount, bucketEnumerator;

CHARON_SCALAR_PROPERTY(NSUInteger, totalBucketCount)
CHARON_VALUE_PROPERTY(NSEnumerator<MXHistogramBucket *> *, bucketEnumerator)

@end

@implementation MXHistogramBucket
@dynamic bucketStart, bucketEnd, bucketCount;

CHARON_VALUE_PROPERTY(NSMeasurement *, bucketStart)
CHARON_VALUE_PROPERTY(NSMeasurement *, bucketEnd)
CHARON_SCALAR_PROPERTY(NSUInteger, bucketCount)

@end

@implementation MXLocationActivityMetric
@dynamic cumulativeBestAccuracyTime, cumulativeBestAccuracyForNavigationTime, cumulativeNearestTenMetersAccuracyTime, cumulativeHundredMetersAccuracyTime, cumulativeKilometerAccuracyTime, cumulativeThreeKilometersAccuracyTime;

CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeBestAccuracyTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeBestAccuracyForNavigationTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeNearestTenMetersAccuracyTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeHundredMetersAccuracyTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeKilometerAccuracyTime)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeThreeKilometersAccuracyTime)

@end

@implementation MXMemoryMetric
@dynamic peakMemoryUsage, averageSuspendedMemory;

CHARON_VALUE_PROPERTY(NSMeasurement *, peakMemoryUsage)
CHARON_VALUE_PROPERTY(MXAverage *, averageSuspendedMemory)

@end

@implementation MXMetaData
@dynamic regionFormat, osVersion, deviceType, applicationBuildVersion, platformArchitecture;

CHARON_VALUE_PROPERTY(NSString *, regionFormat)
CHARON_VALUE_PROPERTY(NSString *, osVersion)
CHARON_VALUE_PROPERTY(NSString *, deviceType)
CHARON_VALUE_PROPERTY(NSString *, applicationBuildVersion)
CHARON_VALUE_PROPERTY(NSString *, platformArchitecture)

@end

@implementation MXMetaData (CharonMetricKit)
@dynamic lowPowerModeEnabled, isTestFlightApp, pid, bundleIdentifier;

CHARON_SCALAR_PROPERTY(bool, lowPowerModeEnabled)
CHARON_SCALAR_PROPERTY(bool, isTestFlightApp)
CHARON_SCALAR_PROPERTY(pid_t, pid)
CHARON_VALUE_PROPERTY(NSString *, bundleIdentifier)

@end

@implementation MXMetricPayload
@dynamic latestApplicationVersion, includesMultipleApplicationVersions, timeStampBegin, timeStampEnd, cpuMetrics, gpuMetrics, cellularConditionMetrics, applicationTimeMetrics, locationActivityMetrics, networkTransferMetrics, applicationLaunchMetrics, applicationResponsivenessMetrics, diskIOMetrics, memoryMetrics, displayMetrics, animationMetrics, applicationExitMetrics, signpostMetrics, metaData;

CHARON_VALUE_PROPERTY(NSString *, latestApplicationVersion)
CHARON_SCALAR_PROPERTY(BOOL, includesMultipleApplicationVersions)
CHARON_VALUE_PROPERTY(NSDate *, timeStampBegin)
CHARON_VALUE_PROPERTY(NSDate *, timeStampEnd)
CHARON_VALUE_PROPERTY(MXCPUMetric *, cpuMetrics)
CHARON_VALUE_PROPERTY(MXGPUMetric *, gpuMetrics)
CHARON_VALUE_PROPERTY(MXCellularConditionMetric *, cellularConditionMetrics)
CHARON_VALUE_PROPERTY(MXAppRunTimeMetric *, applicationTimeMetrics)
CHARON_VALUE_PROPERTY(MXLocationActivityMetric *, locationActivityMetrics)
CHARON_VALUE_PROPERTY(MXNetworkTransferMetric *, networkTransferMetrics)
CHARON_VALUE_PROPERTY(MXAppLaunchMetric *, applicationLaunchMetrics)
CHARON_VALUE_PROPERTY(MXAppResponsivenessMetric *, applicationResponsivenessMetrics)
CHARON_VALUE_PROPERTY(MXDiskIOMetric *, diskIOMetrics)
CHARON_VALUE_PROPERTY(MXMemoryMetric *, memoryMetrics)
CHARON_VALUE_PROPERTY(MXDisplayMetric *, displayMetrics)
CHARON_VALUE_PROPERTY(MXAnimationMetric *, animationMetrics)
CHARON_VALUE_PROPERTY(MXAppExitMetric *, applicationExitMetrics)
CHARON_VALUE_PROPERTY(NSArray *, signpostMetrics)
CHARON_VALUE_PROPERTY(MXMetaData *, metaData)

@end

@implementation MXNetworkTransferMetric
@dynamic cumulativeWifiUpload, cumulativeWifiDownload, cumulativeCellularUpload, cumulativeCellularDownload;

CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeWifiUpload)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeWifiDownload)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeCellularUpload)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeCellularDownload)

@end

@implementation MXSignpostIntervalData
@dynamic histogrammedSignpostDuration, cumulativeCPUTime, averageMemory, cumulativeLogicalWrites, cumulativeHitchTimeRatio;

CHARON_VALUE_PROPERTY(MXHistogram *, histogrammedSignpostDuration)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeCPUTime)
CHARON_VALUE_PROPERTY(MXAverage *, averageMemory)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeLogicalWrites)
CHARON_VALUE_PROPERTY(NSMeasurement *, cumulativeHitchTimeRatio)

@end

@implementation MXSignpostMetric
@dynamic signpostName, signpostCategory, signpostIntervalData, totalCount;

CHARON_VALUE_PROPERTY(NSString *, signpostName)
CHARON_VALUE_PROPERTY(NSString *, signpostCategory)
CHARON_VALUE_PROPERTY(MXSignpostIntervalData *, signpostIntervalData)
CHARON_SCALAR_PROPERTY(NSUInteger, totalCount)

@end

@implementation MXSignpostRecord
@dynamic subsystem, category, name, beginTimeStamp, endTimeStamp, duration, isInterval;

CHARON_VALUE_PROPERTY(NSString *, subsystem)
CHARON_VALUE_PROPERTY(NSString *, category)
CHARON_VALUE_PROPERTY(NSString *, name)
CHARON_VALUE_PROPERTY(NSDate *, beginTimeStamp)
CHARON_VALUE_PROPERTY(NSDate *, endTimeStamp)
CHARON_VALUE_PROPERTY(NSMeasurement *, duration)
CHARON_SCALAR_PROPERTY(BOOL, isInterval)


@end

@implementation MXUnitAveragePixelLuminance
@dynamic apl;

CHARON_VALUE_PROPERTY(MXUnitAveragePixelLuminance *, apl)

@end

@implementation MXUnitSignalBars
@dynamic bars;

CHARON_VALUE_PROPERTY(MXUnitSignalBars *, bars)

@end

@implementation MXMetricPayload (CharonMetricKit)
@dynamic diskSpaceUsageMetrics;

CHARON_VALUE_PROPERTY(MXDiskSpaceUsageMetric *, diskSpaceUsageMetrics)

@end
