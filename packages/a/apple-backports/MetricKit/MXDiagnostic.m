#import "CharonMetricValue.h"
#import "CharonMetricKit.h"

// MXDiagnostic is the second root of this framework, beside MXMetric: the diagnostics (a crash, a hang,
// an exception) are not metrics and do not inherit it. Its values, its two representations and its
// archiving are the CharonMetricValue category's, as MXMetric's are; what is here is the class, so
// that _OBJC_CLASS_$_MXDiagnostic exists and the three diagnostic classes that inherit it have a
// superclass to point at.
@implementation MXDiagnostic
@end
