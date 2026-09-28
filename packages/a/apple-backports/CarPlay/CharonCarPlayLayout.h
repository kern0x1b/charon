// The geometry of the car home screen, as a pure function of the head unit's screen.
//
// This is the part a host differential can decide exactly, and it is the part the video path depends
// on: every size here comes from the head unit's own pixel size and from the car's readability
// constraints (a six-inch display and touch targets a thumb can hit), never from a hard-coded
// resolution. The three resolutions the design names -- 800x480 (15:9, Table 23-9), 960x540 (16:9)
// and 1280x720 (16:9) -- are the three the differential checks, and nothing in this file is
// specialised to any of them.
//
// The units are the head unit's own points, which is its pixel size divided by the scale the setup
// message carried; at 1.0 that is the pixel size itself, which is what a 30-pin head unit reports.
// Foundation and Core Graphics and nothing else, on purpose: the layout is pure geometry, so a host
// differential can compile this very file on macOS and check the three head-unit resolutions without
// a UIKit (which exists there only for Catalyst).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

NS_ASSUME_NONNULL_BEGIN

// One icon's place on the grid: the rect it is drawn in, and the rect its label is drawn in. Both are
// in the screen's own coordinate space, origin top left, so a caller can hand them straight to the
// drawing code and to a hit test.
typedef struct CharonCarPlayIconFrame {
    CGRect icon;
    CGRect label;
} CharonCarPlayIconFrame;

// The layout, for one head unit screen. Every field is derived; none is stored as a constant.
typedef struct CharonCarPlayLayout {
    CGSize screen;          // the head unit's own size, in its points
    CGFloat scale;          // its pixel size over its point size
    CGFloat dockWidth;      // the dock at the side
    CGRect dock;            // where it is
    CGRect grid;            // what is left for the icons
    NSUInteger columns;     // icons across
    NSUInteger rows;        // icons down
    NSUInteger iconsPerPage;
    CGFloat iconSide;       // one icon's side
    CGFloat iconSpacing;    // between icons, and between the icon and its label
    CGFloat labelHeight;
    CGFloat cornerRadius;   // the release's own corner radius for a plate
    CGFloat glossHeight;    // how tall the gloss on a button or an icon plate is
} CharonCarPlayLayout;

#ifdef __cplusplus
extern "C" {
#endif

// The layout for a head unit screen of `size` points at `scale`. This is the one function the whole
// home screen is built from, and the one the host differential compares.
//
// The sizes are the car's constraints made arithmetic: an icon is never smaller than a thumb can hit
// (44 points, the release's own minimum touch target, and a car screen is seen from further away
// than a phone, so the floor is higher), the dock is wide enough for a clock and a status column, and
// the grid takes whatever is left.
CharonCarPlayLayout CharonCarPlayLayoutMake(CGSize size, CGFloat scale);

// One icon's frame for a cell at (column, row) of a page. Returns CGRectZero for an index off the
// page, so a caller cannot draw outside the grid by accident.
CharonCarPlayIconFrame CharonCarPlayLayoutIconFrame(const CharonCarPlayLayout *layout,
                                                     NSUInteger column, NSUInteger row);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
