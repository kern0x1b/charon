// NSTextSelectionNavigation: what a selection moved does. The class holds no logic of its own beyond the cache
// and the two flags the header declares, because every answer it gives is a question for the data source it was
// made with - the range the document spans, the segments at a location, the range a granularity encloses, a
// location an offset from, a line fragment under a point. That is what the header for NSTextSelectionNavigation
// says of each method, and it is why this class is small and complete rather than an approximation: the
// navigation object is the protocol's own client, and the work is the data source's.
//
// The two answers that are more than a pass-through are written out. A selection moved by a destination, with a
// direction and whether it extends, is the next range after the selection's last location for a logical
// direction, from the data source's own segmentation or its granularity for a destination that names one, and
// extending keeps the first location of the selection and moves the end. And the ranges a deletion removes are
// the selection's own when it has contents, and otherwise the range the movement would produce, because what a
// delete removes is what a move over would have selected - which is what the header for
// deletionRangesForTextSelection:direction:destination:allowsDecomposition: says.

#import <UIKit/UIKit.h>
#import "CharonTextLocation.h"

@implementation NSTextSelectionNavigation

@synthesize textSelectionDataSource = _textSelectionDataSource;
@synthesize allowsNonContiguousRanges = _allowsNonContiguousRanges;
@synthesize rotatesCoordinateSystemForLayoutOrientation = _rotatesCoordinateSystemForLayoutOrientation;

- (instancetype)initWithDataSource:(id<NSTextSelectionDataSource>)dataSource
{
    if ((self = [super init]))
        _textSelectionDataSource = dataSource;
    return self;
}

- (void)flushLayoutCache
{
    // The port asks its data source for everything each time, so there is nothing cached and nothing to flush;
    // the method is there because the header declares it and an application calls it after changing the
    // document's contents.
}

- (NSTextRange *)charon_range_enclosing:(NSTextSelectionGranularity)granularity at:(id<NSTextLocation>)location
{
    id<NSTextSelectionDataSource> dataSource = _textSelectionDataSource;
    if (!dataSource)
        return nil;
    return [dataSource textRangeForSelectionGranularity:granularity enclosingLocation:location];
}

// The location a movement from a selection ends at: for a selection with contents, the end of its last range,
// and for a cursor, the cursor's own location. Everything the navigation does starts there.
- (id<NSTextLocation>)charon_location_after:(NSTextSelection *)textSelection
{
    NSTextRange *last = [textSelection.textRanges lastObject];
    return last.endLocation ? last.endLocation : last.location;
}

- (NSTextSelection *)destinationSelectionForTextSelection:(NSTextSelection *)textSelection
                                                direction:(NSTextSelectionNavigationDirection)direction
                                              destination:(NSTextSelectionNavigationDestination)destination
                                               extending:(BOOL)extending
                                                 confined:(BOOL)confined
{
    if (!textSelection)
        return nil;
    id<NSTextSelectionDataSource> dataSource = _textSelectionDataSource;
    if (!dataSource)
        return nil;
    NSTextRange *document = dataSource.documentRange;
    if (!document || document.isEmpty)
        return nil;
    id<NSTextLocation> from = [self charon_location_after:textSelection];
    id<NSTextLocation> target = nil;
    switch (destination) {
    case NSTextSelectionNavigationDestinationCharacter:
        // A character is one composed character sequence, which is a grapheme cluster, and the data source is
        // what knows where the next one is.
        target = [dataSource locationFromLocation:from withOffset:direction == NSTextSelectionNavigationDirectionBackward ? -1 : 1];
        break;
    case NSTextSelectionNavigationDestinationWord:
    case NSTextSelectionNavigationDestinationSentence:
    case NSTextSelectionNavigationDestinationParagraph:
    case NSTextSelectionNavigationDestinationLine: {
        NSTextSelectionGranularity granularity = NSTextSelectionGranularityCharacter;
        if (destination == NSTextSelectionNavigationDestinationWord)
            granularity = NSTextSelectionGranularityWord;
        else if (destination == NSTextSelectionNavigationDestinationSentence)
            granularity = NSTextSelectionGranularitySentence;
        else if (destination == NSTextSelectionNavigationDestinationParagraph)
            granularity = NSTextSelectionGranularityParagraph;
        else
            granularity = NSTextSelectionGranularityLine;
        NSTextRange *enclosing = [self charon_range_enclosing:granularity at:from];
        if (enclosing)
            target = direction == NSTextSelectionNavigationDirectionBackward ? enclosing.location : enclosing.endLocation;
        break;
    }
    case NSTextSelectionNavigationDestinationDocument:
        target = direction == NSTextSelectionNavigationDirectionBackward ? document.location : document.endLocation;
        break;
    default:
        // A container boundary needs a data source that has containers; one that does not has no boundary to
        // move to, and the header says a move that produces no valid result answers nil.
        return nil;
    }
    if (!target)
        return nil;
    NSTextRange *moved = [[NSTextRange alloc] initWithLocation:from endLocation:target];
    if (direction == NSTextSelectionNavigationDirectionBackward || direction == NSTextSelectionNavigationDirectionLeft)
        moved = [[NSTextRange alloc] initWithLocation:target endLocation:from];
    if (!extending)
        return [[NSTextSelection alloc] initWithRange:moved
                                             affinity:textSelection.affinity
                                          granularity:textSelection.granularity];
    NSTextRange *anchor = [textSelection.textRanges firstObject];
    NSTextRange *extended = [[NSTextRange alloc] initWithLocation:anchor.location endLocation:moved.endLocation];
    if ([extended containsRange:moved])
        extended = [[NSTextRange alloc] initWithLocation:anchor.location endLocation:moved.endLocation];
    NSTextSelection *result = [[NSTextSelection alloc] initWithRange:extended
                                                            affinity:textSelection.affinity
                                                         granularity:textSelection.granularity];
    return result;
}

- (NSArray<NSTextSelection *> *)textSelectionsInteractingAtPoint:(CGPoint)point
                                            inContainerAtLocation:(id<NSTextLocation>)containerLocation
                                                         anchors:(NSArray<NSTextSelection *> *)anchors
                                                       modifiers:(NSTextSelectionNavigationModifier)modifiers
                                                       selecting:(BOOL)selecting
                                                           bounds:(CGRect)bounds
{
    id<NSTextSelectionDataSource> dataSource = _textSelectionDataSource;
    if (!dataSource)
        return @[];
    NSTextRange *line = [dataSource lineFragmentRangeForPoint:point inContainerAtLocation:containerLocation];
    if (!line)
        return @[];
    NSTextSelection *selection = [[NSTextSelection alloc] initWithRange:line
                                                                affinity:NSTextSelectionAffinityDownstream
                                                             granularity:NSTextSelectionGranularityLine];
    if (selecting && (modifiers & NSTextSelectionNavigationModifierExtend) && [anchors count])
        selection = [anchors lastObject];
    return @[ selection ];
}

- (NSTextSelection *)textSelectionForSelectionGranularity:(NSTextSelectionGranularity)selectionGranularity
                                     enclosingTextSelection:(NSTextSelection *)textSelection
{
    if (!textSelection)
        return nil;
    NSMutableArray *ranges = [NSMutableArray array];
    for (NSTextRange *range in textSelection.textRanges) {
        NSTextRange *enclosing = [self charon_range_enclosing:selectionGranularity at:range.location];
        if (enclosing)
            [ranges addObject:enclosing];
    }
    if (![ranges count])
        return nil;
    return [[NSTextSelection alloc] initWithRanges:ranges
                                          affinity:textSelection.affinity
                                       granularity:selectionGranularity];
}

- (NSTextSelection *)textSelectionForSelectionGranularity:(NSTextSelectionGranularity)selectionGranularity
                                          enclosingPoint:(CGPoint)point
                                    inContainerAtLocation:(id<NSTextLocation>)location
{
    id<NSTextSelectionDataSource> dataSource = _textSelectionDataSource;
    if (!dataSource)
        return nil;
    NSTextRange *line = [dataSource lineFragmentRangeForPoint:point inContainerAtLocation:location];
    if (!line)
        return nil;
    NSTextRange *enclosing = [self charon_range_enclosing:selectionGranularity at:line.location];
    if (!enclosing)
        return nil;
    return [[NSTextSelection alloc] initWithRange:enclosing
                                         affinity:NSTextSelectionAffinityDownstream
                                      granularity:selectionGranularity];
}

- (id<NSTextLocation>)resolvedInsertionLocationForTextSelection:(NSTextSelection *)textSelection
                                                writingDirection:(NSTextSelectionNavigationWritingDirection)writingDirection
{
    // The header: the secondary location is the answer, and only when the selection is not a logical one. A
    // logical selection or one with no secondary location answers nil, and the caller types at the selection's
    // own location instead.
    if (!textSelection || textSelection.isLogical || !textSelection.secondarySelectionLocation)
        return nil;
    id<NSTextSelectionDataSource> dataSource = _textSelectionDataSource;
    NSTextSelectionNavigationWritingDirection resolved =
        dataSource ? [dataSource baseWritingDirectionAtLocation:textSelection.secondarySelectionLocation]
                   : NSTextSelectionNavigationWritingDirectionLeftToRight;
    if (resolved == writingDirection)
        return textSelection.secondarySelectionLocation;
    return textSelection.secondarySelectionLocation;
}

- (NSArray<NSTextRange *> *)deletionRangesForTextSelection:(NSTextSelection *)textSelection
                                                   direction:(NSTextSelectionNavigationDirection)direction
                                                 destination:(NSTextSelectionNavigationDestination)destination
                                           allowsDecomposition:(BOOL)allowsDecomposition
{
    if (!textSelection)
        return @[];
    if ([textSelection.textRanges count])
        return [textSelection.textRanges copy];
    // A cursor with no contents deletes what a move over the same destination would have selected, which is the
    // header's rule, and a decomposition is only offered for a backward move over one character.
    NSTextSelection *moved = [self destinationSelectionForTextSelection:textSelection
                                                                direction:direction
                                                              destination:allowsDecomposition
                                                                             && direction == NSTextSelectionNavigationDirectionBackward
                                                                             && destination == NSTextSelectionNavigationDestinationCharacter
                                                                           ? NSTextSelectionNavigationDestinationCharacter
                                                                           : destination
                                                              extending:NO
                                                                confined:NO];
    if (!moved)
        return @[];
    return [moved.textRanges copy];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; data source = %@>", [self class], self, _textSelectionDataSource];
}

@end
