#import "CharonMetal.h"

// THE 18 STRING CONSTANTS OF THE 14.0 COUNTER FAMILY: fifteen MTLCommonCounter and three
// MTLCommonCounterSet. The header DECLARES each one and never spells the string - Metal.apinotes says
// which error class each domain belongs to and nothing about a value - so every string below is
// APPLE'S OWN, MEASURED by dlsym on Apple's Metal, and the port's source is GENERATED from that
// measurement rather than written by hand. tests/backports/host/metal-census/counters.m repeats the
// measurement on every run and compares the BYTES, and the generator is not in the tree: what is
// here is the measurement's result, and the case is what keeps it true.
//
// A NAME IS NOT A VALUE. MTLCommonCounterSetTimestamp is "timestamp" - nine bytes, all lower case -
// MTLCommonCounterSetStageUtilization is "stageutilization", and
// MTLCommonCounterPostTessellationVertexCycles is "PostTessellationCycles", not the twenty-eight
// character name that belongs to the INVOCATIONS constant. Writing any of them from the name would
// have been wrong, and no compiler would have said so. All eighteen are distinct.


// MTLCommonCounterTimestamp
//   SDK 16.4 MTLCounters.h:43 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterTimestamp;
MTLCommonCounter const MTLCommonCounterTimestamp = @"GPUTimestamp";

// MTLCommonCounterTessellationInputPatches
//   SDK 16.4 MTLCounters.h:44 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterTessellationInputPatches;
MTLCommonCounter const MTLCommonCounterTessellationInputPatches = @"TessellationInputPatches";

// MTLCommonCounterVertexInvocations
//   SDK 16.4 MTLCounters.h:45 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterVertexInvocations;
MTLCommonCounter const MTLCommonCounterVertexInvocations = @"VertexInvocations";

// MTLCommonCounterPostTessellationVertexInvocations
//   SDK 16.4 MTLCounters.h:46 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterPostTessellationVertexInvocations;
MTLCommonCounter const MTLCommonCounterPostTessellationVertexInvocations = @"PostTessellationVertexInvocations";

// MTLCommonCounterClipperInvocations
//   SDK 16.4 MTLCounters.h:47 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterClipperInvocations;
MTLCommonCounter const MTLCommonCounterClipperInvocations = @"ClipperInvocations";

// MTLCommonCounterClipperPrimitivesOut
//   SDK 16.4 MTLCounters.h:48 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterClipperPrimitivesOut;
MTLCommonCounter const MTLCommonCounterClipperPrimitivesOut = @"ClipperPrimitivesOut";

// MTLCommonCounterFragmentInvocations
//   SDK 16.4 MTLCounters.h:49 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterFragmentInvocations;
MTLCommonCounter const MTLCommonCounterFragmentInvocations = @"FragmentInvocations";

// MTLCommonCounterFragmentsPassed
//   SDK 16.4 MTLCounters.h:50 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterFragmentsPassed;
MTLCommonCounter const MTLCommonCounterFragmentsPassed = @"FragmentsPassed";

// MTLCommonCounterComputeKernelInvocations
//   SDK 16.4 MTLCounters.h:51 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterComputeKernelInvocations;
MTLCommonCounter const MTLCommonCounterComputeKernelInvocations = @"KernelInvocations";

// MTLCommonCounterTotalCycles
//   SDK 16.4 MTLCounters.h:52 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterTotalCycles;
MTLCommonCounter const MTLCommonCounterTotalCycles = @"TotalCycles";

// MTLCommonCounterVertexCycles
//   SDK 16.4 MTLCounters.h:53 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterVertexCycles;
MTLCommonCounter const MTLCommonCounterVertexCycles = @"VertexCycles";

// MTLCommonCounterTessellationCycles
//   SDK 16.4 MTLCounters.h:54 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterTessellationCycles;
MTLCommonCounter const MTLCommonCounterTessellationCycles = @"TessellationCycles";

// MTLCommonCounterPostTessellationVertexCycles
//   SDK 16.4 MTLCounters.h:55 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterPostTessellationVertexCycles;
MTLCommonCounter const MTLCommonCounterPostTessellationVertexCycles = @"PostTessellationCycles";

// MTLCommonCounterFragmentCycles
//   SDK 16.4 MTLCounters.h:56 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterFragmentCycles;
MTLCommonCounter const MTLCommonCounterFragmentCycles = @"FragmentCycles";

// MTLCommonCounterRenderTargetWriteCycles
//   SDK 16.4 MTLCounters.h:57 - a common counter
MTL_EXTERN MTLCommonCounter const MTLCommonCounterRenderTargetWriteCycles;
MTLCommonCounter const MTLCommonCounterRenderTargetWriteCycles = @"RenderTargetWriteCycles";

// MTLCommonCounterSetTimestamp
//   SDK 16.4 MTLCounters.h:69 - a common counter
MTL_EXTERN MTLCommonCounterSet const MTLCommonCounterSetTimestamp;
MTLCommonCounterSet const MTLCommonCounterSetTimestamp = @"timestamp";

// MTLCommonCounterSetStageUtilization
//   SDK 16.4 MTLCounters.h:70 - a common counter
MTL_EXTERN MTLCommonCounterSet const MTLCommonCounterSetStageUtilization;
MTLCommonCounterSet const MTLCommonCounterSetStageUtilization = @"stageutilization";

// MTLCommonCounterSetStatistic
//   SDK 16.4 MTLCounters.h:71 - a common counter
MTL_EXTERN MTLCommonCounterSet const MTLCommonCounterSetStatistic;
MTLCommonCounterSet const MTLCommonCounterSetStatistic = @"statistic";

// THE THREE ERROR DOMAINS OF THE SAME BAND. Each is an NSErrorDomain: the header declares the
// name and never the string, and Metal.apinotes is where the SDK says which error class each
// one belongs to, so the STRING is Apple's own, measured, as the eighteen above are.
// MTLBinaryArchiveDomain - SDK 16.4 MTLBinaryArchive.h:17; the domain of MTLBinaryArchiveError in Metal.apinotes.
MTL_EXTERN NSErrorDomain const MTLBinaryArchiveDomain;
NSErrorDomain const MTLBinaryArchiveDomain = @"MTLBinaryArchiveDomain";
// MTLCounterErrorDomain - SDK 16.4 MTLCounters.h:202; the domain of MTLCounterSampleBufferError in Metal.apinotes.
MTL_EXTERN NSErrorDomain const MTLCounterErrorDomain;
NSErrorDomain const MTLCounterErrorDomain = @"MTLCounterErrorDomain";
// MTLDynamicLibraryDomain - SDK 16.4 MTLDynamicLibrary.h:14; the domain of MTLDynamicLibraryError in Metal.apinotes.
MTL_EXTERN NSErrorDomain const MTLDynamicLibraryDomain;
NSErrorDomain const MTLDynamicLibraryDomain = @"MTLDynamicLibraryDomain";
