#import "CharonVision.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
#pragma clang diagnostic ignored "-Wnullability-completeness"
/* The class method below is declared on VNDetectFaceLandmarksRequest's own interface, so a category
 * on that class draws this warning whether or not the interface's implementation defines it -- and
 * it does not: VNRequests.m's @implementation of the class is empty, and nm on its object finds no
 * selector named supportsConstellation at all. The warning is per translation unit and cannot see
 * the other file, and there is one definition of the method in this library. */
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

/* Vision of iOS 13.0, and only that: the names this object carries are the ones the SDK of 16.4
 * annotates as arriving in 13, and every measurement behind them is in facts/Vision/Absence.md with
 * the command that produced it.
 *
 * A release that has Vision cannot be told what to do about any of it from a header, because the
 * recognisers behind these requests are Apple's own and Apple has published no source for Vision at
 * all (coordination/corpus/sources.md, measured 2026-09-30). What IS knowable is the shape: the two
 * releases this port deploys on carry no Vision image whatever, so a name here is a name the release
 * has never heard of, and the question each row answers is what this port does with it.
 *
 * What each answer below is:
 *   - VNElementTypeSize and the two animal identifiers answer with values measured out of a Vision
 *     image and not out of a name (the name of a constant is never its value);
 *   - +revision:supportsConstellation: answers the truth table Apple's own answers, for the pairs
 *     Apple's own Vision was asked about;
 *   - the precision and recall addition answers NO, which is what the gate its own header describes
 *     says a caller must read before sending the two methods beside it;
 *   - a request class is declared and its revision table answers from the port's own, and running it
 *     comes back from the request handler as VNErrorNotImplemented -- the refusal every request of
 *     iOS 11 and 12 this port cannot run already answers with, so a caller tests an error rather
 *     than losing the process to an unrecognised class.
 */

/* The identifiers an animal recognition answer carries, with the texts Apple's Vision gives them.
 *
 * "Cat" and "Dog", measured twice and read the same way both times: out of the Vision image of the
 * 16.0 arm64e cache through the exported symbol, whose value is a CFString (tools/corpus/
 * cache-value.lua), and out of the Vision of this host through VNAnimalIdentifierCat itself. The
 * capital is the capital and nothing else -- the name of the constant is not the text it names, and
 * a caller that compares an observation's identifier against these needs the text, not the name. */
VNAnimalIdentifier const VNAnimalIdentifierCat = @"Cat";
VNAnimalIdentifier const VNAnimalIdentifierDog = @"Dog";

/* How many bytes one element of a feature print's data takes.
 *
 * The enumeration names three cases and this answers the width of each, with 0 for the unknown one
 * and for every argument the enumeration does not name. Measured against the Vision of this host
 * over the arguments 0 to 4: 0 gives 0, 1 gives 4, 2 gives 8, and 3 and 4 give 0. The widths are
 * sizeof rather than literals so that the answer is the width of the type on the release that asks,
 * which is the whole of what the function is for. */
NSUInteger VNElementTypeSize(VNElementType elementType)
{
    switch (elementType) {
        case VNElementTypeFloat:
            return sizeof(float);
        case VNElementTypeDouble:
            return sizeof(double);
        case VNElementTypeUnknown:
            break;
    }
    return 0;
}

/* Which constellations of face landmarks a revision of the face landmarks request maps a face with.
 *
 * Apple's own answers, for every pair of a revision from 1 to 4 and a constellation from not-defined
 * through 76 points: revisions 1, 2 and 3 map a face with 65 points, revision 3 alone also with 76,
 * and not-defined for none of them. Every other pair is NO as well, which is what Apple's own Vision
 * answers and not this port declining anything.
 *
 * That this port carries revisions 1 and 2 of the request and not revision 3 is a different question
 * from the one asked here, and it is answered where it belongs: a request handler refuses a revision
 * the port does not carry with VNErrorUnsupportedRevision, which VNRequests.m's own revision table
 * decides. */
@implementation VNDetectFaceLandmarksRequest (CharonVision130Constellation)

+ (BOOL)revision:(NSUInteger)requestRevision supportsConstellation:(VNRequestFaceLandmarksConstellation)constellation
{
    if (constellation == VNRequestFaceLandmarksConstellation65Points)
        return requestRevision >= 1 && requestRevision <= 3;
    if (constellation == VNRequestFaceLandmarksConstellation76Points)
        return requestRevision == 3;
    return NO;
}

@end

/* The precision and recall a classification can be read at. This port runs a Core ML classifier,
 * which answers one score per class, and a curve is those same scores swept across thresholds of
 * themselves: there is no set of scores here and so no operation points to compare, which is the
 * whole of what the three answers below say.
 *
 * The property is the gate its own header describes -- "if this property is YES, then all other
 * precision/recall related methods in this addition can be called" -- so answering NO is what keeps
 * a caller from sending the two methods, and the two answering NO is what a caller that sends them
 * anyway gets rather than an answer about a curve that is not there. */
@implementation VNClassificationObservation (CharonVision130PrecisionRecall)

- (BOOL)hasPrecisionRecallCurve
{
    return NO;
}

- (BOOL)hasMinimumPrecision:(float)minimumPrecision forRecall:(float)recall
{
    return NO;
}

- (BOOL)hasMinimumRecall:(float)minimumRecall forPrecision:(float)precision
{
    return NO;
}

@end

/* The two requests the measured values above belong to: an animal recognition answer carries one of
 * the two identifiers, and a feature print's data is the array of elements whose type this answers.
 * Each is a VNImageBasedRequest, which is what its own header declares it to be, so a caller builds
 * it the way it builds every other image request and the request handler takes it. The feature print
 * request's own default is written down beside it above. */
@implementation VNRecognizeAnimalsRequest
@end

/* The other six requests of 13.0, each declared over VNImageBasedRequest by its own header and each
 * with exactly one revision in 13.0, so the port's own revision table places every one of them
 * without a revision of its own. The classifier, the face capture quality, the person, the two
 * saliency maps and the text are Apple's own models, and there is no source for any of them.
 *
 * Two of the six are declared conforming to a protocol by their own headers, and declaring a class
 * whose header names a protocol puts that protocol in the class's own conformance list at run time:
 * -conformsToProtocol: and -instancesRespondToSelector: answer for it whether or not this port writes
 * the selector down. So each member those protocols declare is written down here, and a row is
 * registered for it. A class that answered YES to a protocol and then raised on the protocol's own
 * selector would be worse than a class that were not there. */
@implementation VNClassifyImageRequest
@end

/* VNFaceObservationAccepting's inputFaceObservations, which is this class's own API by its header's
 * declaration. VNDetectFaceLandmarksRequest carries the same property in VNRequests.m, and this is
 * that one again for the request that scores a face rather than the one that maps it. */
@implementation VNDetectFaceCaptureQualityRequest {
    NSArray *_inputFaceObservations;
}
@synthesize inputFaceObservations = _inputFaceObservations;
@end

@implementation VNDetectHumanRectanglesRequest {
    BOOL _upperBodyOnly;
}

/* The upper body alone, which is what the request looks for unless a caller asks for the whole
 * person. Zero is not that: the flag's own header says the default is YES, so it is written down
 * here rather than left to whatever a fresh ivar holds. */
- (instancetype)initWithCompletionHandler:(VNRequestCompletionHandler)completionHandler
{
    if ((self = [super initWithCompletionHandler:completionHandler]))
        _upperBodyOnly = YES;
    return self;
}

@end

@implementation VNGenerateAttentionBasedSaliencyImageRequest
@end

@implementation VNGenerateObjectnessBasedSaliencyImageRequest
@end

/* The request that answers with the feature print observation whose element type VNElementTypeSize
 * answers for. Zero is not this request's own default either: VNImageCropAndScaleOptionScaleFill is
 * 2, and the header says ScaleFill is the default, so a fresh ivar's 0 -- which is CenterCrop --
 * would answer with the other option. */
@implementation VNGenerateImageFeaturePrintRequest {
    VNImageCropAndScaleOption _imageCropAndScaleOption;
}

- (instancetype)initWithCompletionHandler:(VNRequestCompletionHandler)completionHandler
{
    if ((self = [super initWithCompletionHandler:completionHandler]))
        _imageCropAndScaleOption = VNImageCropAndScaleOptionScaleFill;
    return self;
}

@end

/* VNRequestProgressProviding's two members, which this class's own header declares it conforming to.
 * The handler a caller installs is kept and handed back; the request cannot be run here, so it is
 * never called, and a request that reports no progress is told so rather than left to guess.
 *
 * indeterminate answers NO, which is what Apple's own Vision answers for this class (measured, see
 * facts/Vision/Absence.md section 4). It is asked here of a request this port cannot run at all, and
 * NO is the answer that does not promise fractions of work that will never happen. */
@implementation VNRecognizeTextRequest {
    VNRequestProgressHandler _progressHandler;
}
@synthesize progressHandler = _progressHandler;

- (BOOL)indeterminate
{
    return NO;
}

@end

/* The observations those requests answer with. Each is declared over the superclass its own header
 * names -- VNRectangleObservation for the area a text was read from, VNObservation for the feature
 * print and VNPixelBufferObservation for the saliency map -- so an answer is a kind of the
 * observation this port already answers for, and it inherits that observation's archiving and copying
 * rather than writing a second one. The port fills none of them: there is no model behind any of
 * these requests, so a handler refuses the request and no observation of this port's making appears. */
@implementation VNRecognizedTextObservation
@end

@implementation VNFeaturePrintObservation
@end

@implementation VNSaliencyImageObservation
@end

/* The text itself, the one observation of this release with nothing above it but NSObject, and so the
 * only one whose protocols the port cannot inherit: its own header declares it over NSObject with
 * NSCopying, NSSecureCoding and VNRequestRevisionProviding. Each of those is written down here.
 *
 * The archiver holds the two properties the header declares on the class and the revision, keyed the
 * way this library keys every other observation -- by the class and the property -- so an archive
 * written here cannot be read as another observation's. Nothing of this port makes one, so no archive
 * exists to read; what the class owes a caller is that archiving, copying and reading back an object
 * of the class answers instead of raising. */
@implementation VNRecognizedText

@synthesize requestRevision = _requestRevision;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_string forKey:@"VNRecognizedText.string"];
    [coder encodeFloat:_confidence forKey:@"VNRecognizedText.confidence"];
    [coder encodeInteger:(NSInteger)_requestRevision forKey:@"VNRecognizedText.requestRevision"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        _string = [[coder decodeObjectOfClass:[NSString class] forKey:@"VNRecognizedText.string"] copy];
        _confidence = [coder decodeFloatForKey:@"VNRecognizedText.confidence"];
        _requestRevision = (NSUInteger)[coder decodeIntegerForKey:@"VNRecognizedText.requestRevision"];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    VNRecognizedText *copy = [[VNRecognizedText allocWithZone:zone] init];
    copy->_string = _string;
    copy->_confidence = _confidence;
    copy->_requestRevision = _requestRevision;
    return copy;
}

@end
