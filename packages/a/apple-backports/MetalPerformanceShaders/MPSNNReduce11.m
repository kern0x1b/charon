// MPSNNReduce, from MPSNNReduce.h of the iPhoneOS 16.4 surface. One object for one release:
// MPSNNReduce.h:36 carries MPS_CLASS_AVAILABLE_STARTING(macos(10.13.4), ios(11.3), macCatalyst(13.0),
// tvos(11.3)) above MPSNNReduceUnary, and each of the twelve concrete classes repeats that same
// annotation on its own declaration (:68, :95, :121, :175, :201, :227, :281, :307, :333, :359, :385,
// :412), so every @implementation below is a release-11.3 class and nothing else is in this file.
//
// Thirteen classes: the abstract base and twelve concrete ones. What decides that this is a CPU walk
// and not an opaque encoder call is the RELEASE'S OWN CACHE, read with tools/corpus/objc-inventory.lua
// over $HOME/.charon/dyld/16.0/dyld_shared_cache_arm64e: none of the thirteen declares an encode of
// its own. MPSNNReduceRowSum's entire instance list is -destinationImageDescriptorForSourceImages:
// sourceStates:paddingMethod:sourceOffset:, -initWithCoder:device: and -initWithDevice:. The walk is
// the one it INHERITS from MPSCNNKernel, and MPSCNNKernel is a class this port already carries
// (MPSCNNKernel10.m, cnn.json, introduced 10.0, implemented) - whose own
// -encodeToCommandBuffer:sourceImage:destinationImage: is a CPU walk here exactly as
// MPSCNNPooling10.m's and MPSCNNConvolution10.m's are. So the encode is implemented per concrete
// class, which is how MPSCNNPooling10.m does it, and NOT in the base: a category cannot read the ivars
// the base declares, and MPSImageReduceUnary16.m already records that lesson for the same family of
// reduction.
//
// THE WALK IS NOT NEW, and that is the point. MPSImageReduceUnary16.m already reduces a row or a
// column of an MPSImage over CharonMPSImageReadRegion / CharonMPSImageLoad / CharonMPSImageWriteRegion
// and its 108 cases compare with 0 mismatches. This file adds the third axis MPSNNReduce names and
// MPSImageReduce does not - the FEATURE CHANNEL - and reuses the same helpers, so the arithmetic on
// each axis is the arithmetic already measured twice over. Reusing it is the rule in the workspace
// contract ("no second copy of something that already exists"): a reduction over one axis of a plane
// is the same loop whichever axis the header names, and writing it again would be a second answer for
// a later author to choose between.
//
// What the header fixes, and what it does not:
//
//   - The axis and the operation per class. MPSNNReduce.h:66 "returning the mininmum value for each row
//     of an image" (the release's own spelling), :93 and :199 the same for a column's minimum and
//     maximum, :119 "for feature channels of an image", :173/:199/:225/:279/:305/:331/:357/:383/:410 for
//     max, mean and sum. So a ROW reduction answers one value per source row, a COLUMN one per source
//     column, and a FEATURE-CHANNEL one per source pixel - and that count is the header's sentence,
//     not this file's arithmetic.
//   - The read window: MPSNNReduce.h:31-42's clipRectSource, "The source rectangle to use when reading
//     data ... If the clipRectSource does not lie completely within the source image, the intersection
//     of the image bounds and clipRectSource will be used. The clipRectSource replaces the MPSCNNKernel
//     offset parameter for this filter. The latter is ignored. Default: MPSRectNoClip, use the entire
//     source texture." So offset does not enter this kernel, and the window is an INTERSECTION with
//     the image rather than a rectangle applied on its own. :44-47 marks the base's -initWithDevice:
//     NS_UNAVAILABLE - "You must use one of the sub-classes of MPSNNReduceUnary."
//   - One value the caller sets: MPSNNReduceFeatureChannelsSum's weight, :414-420, "The scale factor
//     to apply to each feature channel value ... Each feature channel is multiplied by the weight value
//     to compute a weighted sum or mean across feature channels. The default value is 1.0." That 1.0
//     is the header's own sentence and is where this file's default comes from.
//
// What the header does NOT state, and what no measurement on this host can supply: the destination's
// width and height. Each class fixes HOW MANY values there are and not their shape. This host's AGX
// family lacks computeCommandEncoderWithDispatchType: and the release's own kernel dies encoding with
// '-[AGXG16XFamilyCommandBuffer mtlnext computeCommandEncoderWithDispatchType:]': unrecognized
// selector, so the release's answer cannot be read here and nothing below claims to have measured it.
// What this file does instead is the shape the count forces and the layout allows, and it says so in
// the row it carries: a row reduction's values go DOWN the destination's first column (runs of them,
// one per source row), a column reduction's go ALONG its first row, and a feature-channel reduction's
// fill the destination, one per source pixel. A destination too small for the count is refused BY
// NAME with the count in the message rather than written past its edge, which is what
// MPSImageReduceUnary16.m does and why the release's own assertion on a wide write is not reproduced.
//
// Arithmetic: min, max and sum select or add values the source already holds, so they are exact and the
// differential compares them for EQUALITY - a copy that moved a bit is a copy that moved a bit. mean
// divides, and dividing cannot be exact in binary, so the sum is taken in double and divided once,
// which leaves the result within one whole float32 ulp of the answer. That bound is the one
// mps-reference.h already states for the MPSImageReduce rows and is not widened here.

#import "CharonMPSCnn.h"
#import "CharonMPSReduce.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
// One scoped suppression, recorded in coordination/crutches.md with the reason, and the reason is the
// release's own shape rather than this file's convenience. The SDK marks the base's -initWithDevice:
// NS_UNAVAILABLE (:44-47) and each concrete class's -initWithDevice: NS_DESIGNATED_INITIALIZER, so
// clang requires the concrete initializer to call a designated initializer of the base while the base's
// only designated initializer is -initWithCoder:device:, which cannot know which of the twelve
// operations to build and takes a nonnull coder this path has no use for. MPSImageReduceUnary16.m
// records the same suppression for the same reason and the same native fix, and CharonMPSReduce.h
// already declares the seam both files use: a `charon_` initializer that is not in the `init` family,
// which cannot therefore be marked designated.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

// The seam CharonMPSReduce.h already declares for MPSImageReduceUnary, declared here for
// MPSNNReduceUnary. It is a category so that it reaches the class the SDK declares without this file
// re-declaring the interface, and it says which axis and which operation the concrete class is, in the
// same two pieces of state MPSImageReduceUnary keeps for the same reason: a reduction has to remember
// which axis it walks, and the class name is not somewhere a base can read it from.
@interface MPSNNReduceUnary (CharonMPSNNReduce)
- (instancetype)charon_nnReduceWithDevice:(id<MTLDevice>)device
                                   byColumn:(BOOL)byColumn
                           byFeatureChannel:(BOOL)byFeatureChannel
                                 operation:(CharonMPSReduceOperation)operation;
- (float)charon_nnReduceWeight;
- (void)charon_setNnReduceWeight:(float)weight;
@end

// The ONE class whose OWN @interface declares `weight` - MPSNNReduce.h:420, on
// MPSNNReduceFeatureChannelsSum - gets its accessors implemented against the base's storage, because
// the SDK's declaration makes it autosynthesize an ivar of its own that the walk does not read.
//
// ONE class and not two, measured rather than assumed: the header gives `weight` to
// MPSNNReduceFeatureChannelsSum alone (:413-420), and the release's own cache agrees - of the twelve
// concrete classes, only MPSNNReduceFeatureChannelsSum lists -weight and -setWeight:.
// MPSNNReduceFeatureChannelsMean (:334) declares no property at all, and its cache entry lists no
// weight selector, so a `weight` on it would be an API this port has and the release does not.
@interface MPSNNReduceFeatureChannelsSum (CharonMPSNNReduce)
- (float)weight;
- (void)setWeight:(float)weight;
@end


@implementation MPSNNReduceUnary {
    MTLRegion _clipRectSource;
    BOOL _byColumn;
    BOOL _byFeatureChannel;
    CharonMPSReduceOperation _operation;
    // The weight, in an ivar whose name is the base's own and not the one @synthesize would pick. The
    // SDK declares `weight` on the two concrete feature-channel classes, so each of those
    // autosynthesizes its OWN _weight and a base ivar called _weight is the collision clang reports
    // ("property 'weight' attempting to use instance variable '_weight' declared in super class"). The
    // base's storage is therefore named for the base, and the accessors below - which the base's own
    // @interface does not declare, so nothing is synthesized for them here - read and write it. The
    // concrete classes' own synthesized accessors still work: they shadow the base's for the two
    // classes that declare the property, and the walk reads the base's, so setWeight: on those two has
    // to reach the base's storage. That is what the accessors below are for, and why they are declared
    // in a category on the two concrete classes rather than only in the base.
    float _charonWeight;
}

@synthesize clipRectSource = _clipRectSource;

// MPSNNReduce.h:36, the default: MPSRectNoClip, the whole source.
- (instancetype)charon_nnReduceWithDevice:(id<MTLDevice>)device
                                 byColumn:(BOOL)byColumn
                         byFeatureChannel:(BOOL)byFeatureChannel
                               operation:(CharonMPSReduceOperation)operation
{
    MPSNNReduceUnary *made = [super initWithDevice:device];
    if (made) {
        made->_clipRectSource = MPSRectNoClip;
        made->_byColumn = byColumn;
        made->_byFeatureChannel = byFeatureChannel;
        made->_operation = operation;
        // MPSNNReduce.h:418, "The default value is 1.0" - the header's own sentence, not a number
        // this file chose. It is read only by the two feature-channel classes that declare `weight`,
        // and the release's own cache confirms which those are: MPSNNReduceFeatureChannelsSum lists
        // -weight and -setWeight: and no other concrete class lists either.
        made->_charonWeight = 1.0f;
    }
    return made;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    // MPSNNReduce.h:44-47 marks this NS_UNAVAILABLE on the abstract base: "You must use one of the
    // sub-classes of MPSNNReduceUnary." A caller that reached it named no axis and no operation, so
    // there is nothing to reduce. The release asserts and takes the process with it; this port refuses
    // by name and returns nil, which is what the rest of this package does rather than aborting a
    // caller that got the class wrong.
    CharonMPSRefuse(@"MPSNNReduceUnary: -initWithDevice: is unavailable on the abstract base, which"
                    @" MPSNNReduce.h:44-47 says must not be instantiated - use one of the twelve"
                    @" concrete classes");
    return nil;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    if ((self = [super initWithCoder:aDecoder device:device])) {
        _clipRectSource = MPSRectNoClip;
        _byColumn = NO;
        _byFeatureChannel = NO;
        _operation = CharonMPSReduceSum;
        _charonWeight = 1.0f;
    }
    return self;
}

// The weight. ONE class declares it: MPSNNReduce.h:413-420, on MPSNNReduceFeatureChannelsSum, whose
// @discussion says "Each feature channel is multiplied by the weight value to compute a weighted sum
// or mean across feature channels" and whose `weight` property's own @discussion at :414-420 ends "The
// default value is 1.0." - the header's own sentence, and where this file's default comes from. The
// weight scales each feature channel's value BEFORE the reduction, so it multiplies every value a
// feature-channel run combines rather than the run's result.
//
// The accessors are here and not @synthesize'd, because the SDK declares `weight` on the two CONCRETE
// classes and not on the base, so the base cannot synthesize for it: clang rejects a @synthesize whose
// property the class's own @interface does not declare, and an autosynthesized `weight` in the base
// collides with the concrete classes' own declaration of it. Declaring the accessors by hand is the
// same shape MPSImage9.m:281 uses (`@synthesize colorTransform = _charonTransform;` for a property the
// SDK spells differently), and the release's own cache confirms which classes declare it: only
// MPSNNReduceFeatureChannelsSum lists -weight and -setWeight: among the twelve.
- (float)charon_nnReduceWeight { return _charonWeight; }
- (void)charon_setNnReduceWeight:(float)weight { _charonWeight = weight; }

// The reduce itself. The signature is MPSCNNKernel's, inherited: the release's own cache gives
// MPSNNReduceRowSum no encode of its own, and MPSCNNKernel declares this one, so this is the selector
// a caller of a reduce class reaches.
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  sourceImage:(MPSImage *)sourceImage
               destinationImage:(MPSImage *)destinationImage
{
    NSString *what = NSStringFromClass([self class]);
    if (!commandBuffer) {
        CharonMPSRefuse(@"%@: no command buffer, so nothing was written", what);
        return;
    }
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    if (!CharonMPSImageUsable(sourceImage, what)) {
        CharonMPSRefuse(@"%@: the source image cannot be walked", what);
        return;
    }
    if (!destinationImage) {
        CharonMPSRefuse(@"%@: no destination image, so nothing was written", what);
        return;
    }

    CharonMPSImageLayout in = CharonMPSImageLayoutOf(sourceImage);
    CharonMPSImageLayout out = CharonMPSImageLayoutOf(destinationImage);

    // The read window: clipRectSource INTERSECTED with the image (MPSNNReduce.h:33-34). The
    // intersection is done here against the image, so the MPSRectNoClip sentinel is resolved before
    // any texture sees it - a NoClip rectangle has size {-1,-1,0} and to a texture its xoffset + width
    // is -2, where the framework asserts.
    NSUInteger winX, winY, winCols, winRows;
    CharonMPSImageRegionIsEmpty(_clipRectSource)
        ? (winX = 0, winY = 0, winCols = in.width, winRows = in.height)
        : (winX = (NSUInteger)self.clipRectSource.origin.x, winY = (NSUInteger)self.clipRectSource.origin.y,
           winCols = (NSUInteger)self.clipRectSource.size.width,
           winRows = (NSUInteger)self.clipRectSource.size.height);
    if (winX + winCols > in.width)
        winCols = in.width - (winX < in.width ? winX : in.width);
    if (winY + winRows > in.height)
        winRows = in.height - (winY < in.height ? winY : in.height);
    if (!winCols || !winRows) {
        CharonMPSRefuse(@"%@: clipRectSource intersects the %lux%lu source to nothing, so nothing was"
                        @" written", what, (unsigned long)in.width, (unsigned long)in.height);
        return;
    }

    // The three axes, and which of them is the walk. This is the only thing that distinguishes the
    // twelve classes from one another, and it is the header's own per-class sentence: a row
    // reduction runs along a row, a column reduction down a column, a feature-channel reduction across
    // the channels of one pixel.
    //
    // WHERE the channel goes is the one thing the header does not say, and it is decided here from
    // what the count means rather than guessed. "Returning the sum for each row of an image" counts
    // ROWS, and an MPSImage's row is a row of ONE feature channel - MPSCNNKernel carries
    // sourceFeatureChannelOffset and sourceFeatureChannelMaxCount precisely because a kernel walks one
    // channel at a time. So a row or column reduction answers one value per row (or column) PER
    // FEATURE CHANNEL, and the destination keeps its channel count; a feature-channel reduction is the
    // one that crosses channels, so it answers one value per PIXEL and the destination holds one plane.
    // The two are counted differently on purpose, and the count in the refusal below is the one the
    // walk actually produces.
    NSUInteger channels = in.channels ? in.channels : 1;
    NSUInteger span, runs;
    if (_byFeatureChannel) {
        span = channels;
        runs = winCols * winRows;
    } else {
        span = _byColumn ? winRows : winCols;
        runs = (_byColumn ? winCols : winRows) * channels;
        if (!span) {
            CharonMPSRefuse(@"%@: the window is one pixel along the reduction's axis, so there is"
                            @" nothing to reduce and nothing was written", what);
            return;
        }
    }

    // The destination holds `runs` values, and a write that would land past its edge is refused by
    // name rather than performed: the release asserts on it, and a write outside a texture is not an
    // answer a caller can read back.
    NSUInteger needCols, needRows, needChannels;
    if (_byFeatureChannel) {
        needCols = winCols;
        needRows = winRows;
        needChannels = 1;
    } else if (_byColumn) {
        needCols = winCols;
        needRows = 1;
        needChannels = channels;
    } else {
        needCols = 1;
        needRows = winRows;
        needChannels = channels;
    }
    if (out.width < needCols || out.height < needRows || out.channels < needChannels) {
        CharonMPSRefuse(@"%@: a %@ reduction over a %lux%lu window of %lu channels answers %lu values"
                        @" and needs a %lux%lux%lu destination, and this one is %lux%lux%lu, so nothing"
                        @" was written",
                        what, _byFeatureChannel ? @"feature channel" : (_byColumn ? @"column" : @"row"),
                        (unsigned long)winCols, (unsigned long)winRows, (unsigned long)channels,
                        (unsigned long)runs, (unsigned long)needCols, (unsigned long)needRows,
                        (unsigned long)needChannels, (unsigned long)out.width,
                        (unsigned long)out.height, (unsigned long)out.channels);
        return;
    }

    // One region read of the window, then one reduction per run. The values move out of the source and
    // into the destination's own buffer; nothing is reinterpreted and nothing is scaled, except by the
    // weight the two feature-channel classes carry.
    CharonMPSImageLayout slice = in;
    slice.count = winCols * winRows * in.channels;
    void *from = CharonMPSImageReadRegion(sourceImage, &slice,
                                          MTLRegionMake2D(winX, winY, winCols, winRows), what);
    if (slice.count && !from)
        return;

    double *result = calloc(runs ? runs : 1, sizeof(double));
    if (!result) {
        CharonMPSRefuse(@"%@: no memory for %lu reduced values, so nothing was written", what,
                        (unsigned long)runs);
        free(from);
        return;
    }

    for (NSUInteger r = 0; r < runs; r++) {
        double total = 0.0;
        double smallest = 0.0, largest = 0.0;
        // Where this run starts and how it moves, in the window's own row-major pixel numbering. A
        // feature-channel run is ONE pixel and walks its CHANNELS, so its step is 0 pixels: `which` is
        // the step index and the pixel does not move. A row or column run is one row or one column of
        // one channel, so its step is the axis's own stride - +1 along a row, +winCols down a column -
        // and the run index carries the channel. One loop does all three axes because the difference
        // between them is a stride and not a different loop, and three loops would then have to be
        // kept in step with each other for no gain.
        //
        // The step being 0 for a feature-channel run is not a shortcut: `at = pixel + s * step` with a
        // step of 1 walks pixels while the step index is also the channel, so the walk reads pixel r+1's
        // first channel when it means pixel r's second, and the differential caught exactly that - the
        // port's answers were the reference's, one pixel behind.
        NSUInteger pixel, step, channel;
        if (_byFeatureChannel) {
            pixel = r;
            step = 0;
            channel = 0;
        } else {
            NSUInteger along = _byColumn ? winCols : winRows;
            NSUInteger spatial = r % along;
            channel = r / along;
            // A ROW run starts at its row's first pixel, `spatial * winCols`, and walks +1 along the
            // row. A COLUMN run starts at its column's FIRST pixel of the first row, which is
            // `spatial` itself, and walks +winCols down the column. Multiplying by winCols on both axes
            // - which is what this had - makes every column after the first walk a whole row stride
            // late, so column 1 read column 0 and the last two columns ran off the end of the window
            // and were skipped by the bound below. That is what the differential caught, and it is
            // written down here because the mistake is easy to make twice: `spatial * winCols` is
            // right for a row and wrong for a column, and the two differ by one multiplication.
            pixel = _byColumn ? spatial : spatial * winCols;
            step = _byColumn ? winCols : 1;
        }
        for (NSUInteger s = 0; s < span; s++) {
            NSUInteger at = pixel + s * step;
            NSUInteger which = _byFeatureChannel ? s : channel;
            if (at >= winCols * winRows || which >= channels)
                continue;
            double value = CharonMPSImageLoad(from, &slice, CharonMPSImageIndex(&slice, at, which));
            // MPSNNReduce.h:414-420, and the weight applies to the two operations its own sentence names.
            // The property is on MPSNNReduceFeatureChannelsSum alone and reads "Each feature channel is
            // multiplied by the weight value to compute a weighted SUM OR MEAN across feature channels" -
            // so it scales the values a sum or a mean combines and nothing else. Scaling a minimum or a
            // maximum would change which value is extremal whenever the weight is negative, and a header
            // that does not ask for it is not read as asking for it. A weight of 0.5, which every
            // feature-channel case sets, leaves a min and a max where they were, so the differential
            // holds the port to the header's own division of the operations rather than to a uniform
            // scale.
            if (_byFeatureChannel && (_operation == CharonMPSReduceSum || _operation == CharonMPSReduceMean))
                value *= (double)_charonWeight;
            if (s == 0 || value < smallest) smallest = value;
            if (s == 0 || value > largest) largest = value;
            total += value;
        }
        switch (_operation) {
            case CharonMPSReduceMin: result[r] = smallest; break;
            case CharonMPSReduceMax: result[r] = largest; break;
            case CharonMPSReduceMean: result[r] = total / (double)span; break;
            case CharonMPSReduceSum: result[r] = total; break;
        }
    }
    free(from);

    // The write, in the row-major order CharonMPSImageWriteRegion takes: Height x Width x
    // FeatureChannels. Each run lands where its own axis says it goes - a row run's values go DOWN the
    // destination's first column, a column run's go ALONG its first row, a feature-channel run's fill
    // the destination in row-major order - and each row or column run carries the channel it reduced.
    // Where that is, is the shape the count forces and the header does not state; the registry row
    // says so rather than claiming it was measured.
    MTLRegion writeRegion = _byFeatureChannel
        ? MTLRegionMake2D(0, 0, winCols, winRows)
        : (_byColumn ? MTLRegionMake2D(0, 0, winCols, 1) : MTLRegionMake2D(0, 0, 1, winRows));
    CharonMPSImageLayout staged = out;
    staged.channels = needChannels;
    staged.count = writeRegion.size.width * writeRegion.size.height * staged.channels;
    void *bytes = calloc(staged.count ? staged.count : 1, staged.elementSize);
    if (!bytes) {
        CharonMPSRefuse(@"%@: no memory for a %lux%lux%lu result, so nothing was written", what,
                        (unsigned long)writeRegion.size.width, (unsigned long)writeRegion.size.height,
                        (unsigned long)staged.channels);
        free(result);
        return;
    }
    for (NSUInteger r = 0; r < runs; r++) {
        NSUInteger x, y, c;
        if (_byFeatureChannel) {
            x = r % winCols;
            y = r / winCols;
            c = 0;
        } else {
            NSUInteger along = _byColumn ? winCols : winRows;
            NSUInteger spatial = r % along;
            c = r / along;
            x = _byColumn ? spatial : 0;
            y = _byColumn ? 0 : spatial;
        }
        // Through CharonMPSImageIndex, and NOT through a byte offset of this file's own: the store
        // takes an ELEMENT index and the helper is what turns a pixel and a channel into one. Adding a
        // hand-computed `pixel * channels + channel` in elements and a second `* elementSize` in bytes
        // counted the channel twice for every run past the first, which is what the differential caught
        // - the port's answers were the reference's, one run behind.
        CharonMPSImageStore(bytes, &staged, CharonMPSImageIndex(&staged, y * writeRegion.size.width + x, c),
                            result[r]);
    }
    CharonMPSImageWriteRegion(destinationImage, &staged, writeRegion, bytes, what);
    free(bytes);
    free(result);
    CharonMPSConsumeReadCount(sourceImage);
}

@end


// The twelve concrete classes. Each differs from the base only in the axis and the operation, which
// is exactly what the header's twelve per-class sentences say, and CharonMPSReduce.h's
// CharonMPSReduceOperation already names the four operations this family has. There is no arithmetic
// here: the walk is the base's, reached through the same `charon_` seam MPSImageReduce12.m uses for
// the MPSImageReduce classes, because a class that declares no encode of its own - which the release's
// own cache says of all twelve - cannot carry one.
#define CHARON_DEFINE_NN_REDUCE(CLASS, COLUMN, FEATURE_CHANNEL, OPERATION)                          \
    @implementation CLASS                                                                          \
    - (instancetype)initWithDevice:(id<MTLDevice>)device                                          \
    {                                                                                              \
        return [self charon_nnReduceWithDevice:device                                             \
                                     byColumn:(COLUMN)                                            \
                             byFeatureChannel:(FEATURE_CHANNEL)                                    \
                                   operation:(OPERATION)];                                        \
    }                                                                                              \
    @end

// Row, column and feature channel, each four times: min, max, mean, sum.
CHARON_DEFINE_NN_REDUCE(MPSNNReduceRowMin, NO, NO, CharonMPSReduceMin)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceColumnMin, YES, NO, CharonMPSReduceMin)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceFeatureChannelsMin, NO, YES, CharonMPSReduceMin)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceRowMax, NO, NO, CharonMPSReduceMax)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceColumnMax, YES, NO, CharonMPSReduceMax)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceFeatureChannelsMax, NO, YES, CharonMPSReduceMax)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceRowMean, NO, NO, CharonMPSReduceMean)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceColumnMean, YES, NO, CharonMPSReduceMean)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceFeatureChannelsMean, NO, YES, CharonMPSReduceMean)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceRowSum, NO, NO, CharonMPSReduceSum)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceColumnSum, YES, NO, CharonMPSReduceSum)
CHARON_DEFINE_NN_REDUCE(MPSNNReduceFeatureChannelsSum, NO, YES, CharonMPSReduceSum)


// MPSNNReduceFeatureChannelsSum's `weight`, against the base's storage. The SDK declares the property
// on this class, so without these it would autosynthesize an ivar of its own that the walk - which
// reads the base's - never sees, and a caller setting the weight would watch the reduction ignore it.
// The accessors keep the release's spelling and the base keeps one piece of state.
@implementation MPSNNReduceFeatureChannelsSum (CharonMPSNNReduce)
- (float)weight { return [self charon_nnReduceWeight]; }
- (void)setWeight:(float)weight { [self charon_setNnReduceWeight:weight]; }
@end
