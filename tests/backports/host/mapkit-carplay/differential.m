// The car home screen's geometry, at the three head-unit resolutions the CarPlay design names.
//
// The layout is a pure function of the head unit's screen, and this compiles the port's own file and
// asks it what it decides -- so there is no second copy of the arithmetic here to drift from. What is
// checked are the properties the car screen's own constraints require:
//
//   * the dock is on the side, a sensible fraction of the width, and never eats the grid;
//   * every icon is at least the release's own touch-target floor raised for a car;
//   * the grid's icons all fit inside the grid, and a bigger head unit gets BIGGER icons, not more of
//     the same small ones -- which is what "adaptive" has to mean on a car;
//   * the page fits the icons: columns times rows, and nothing is drawn off the page.
#import <Foundation/Foundation.h>
#import <math.h>
#import "CharonCarPlayLayout.h"

// The column cap the layout applies, restated so the test can tell "fewer because they do not fit"
// from "fewer because it is capped".
#define CHARON_MAX_COLUMNS 8

static int failures = 0;
static int checked = 0;

static void ok(NSString *what) { checked++; printf("ok %s\n", [what UTF8String]); }

static void bad(NSString *what, NSString *detail)
{
    checked++;
    failures++;
    printf("FAIL %s: %s\n", [what UTF8String], [detail UTF8String]);
}

static BOOL near(double a, double b, double tolerance) { return fabs(a - b) <= tolerance; }

static void check(CGSize screen, double wantIconFloor)
{
    CharonCarPlayLayout layout = CharonCarPlayLayoutMake(screen, 1.0);
    NSString *name = [NSString stringWithFormat:@"%.0fx%.0f", screen.width, screen.height];
    printf("# %s: dock %.0f wide, grid %.0fx%.0f, %d columns x %d rows = %d a page, icon %.0f\n",
           [name UTF8String], layout.dockWidth, layout.grid.size.width, layout.grid.size.height,
           (int)layout.columns, (int)layout.rows, (int)layout.iconsPerPage, layout.iconSide);

    if (layout.dock.origin.x != 0.0 || layout.dock.size.height != screen.height) {
        bad([name stringByAppendingString:@" dock"], @"the dock is not at the side, the full height");
    } else {
        ok([name stringByAppendingString:@": the dock is at the side for the full height"]);
    }
    if (layout.dockWidth > screen.width / 4.0 + 0.001) {
        bad([name stringByAppendingString:@" dock width"], @"the dock is more than a quarter of the screen");
    } else {
        ok([name stringByAppendingString:@": the dock is under a quarter of the screen"]);
    }
    if (layout.grid.origin.x < layout.dock.size.width) {
        bad([name stringByAppendingString:@" grid"], @"the grid starts inside the dock");
    } else {
        ok([name stringByAppendingString:@": the grid starts clear of the dock"]);
    }
    if (layout.iconSide < wantIconFloor) {
        bad([name stringByAppendingString:@" icon side"],
             [NSString stringWithFormat:@"%.0f, under the %.0f a thumb on a car screen must hit",
              layout.iconSide, wantIconFloor]);
    } else {
        ok([name stringByAppendingString:[NSString stringWithFormat:@": every icon is %.0f or more", layout.iconSide]]);
    }
    // The columns are what fit, not what anyone decided: the icon side comes first and the counts
    // follow from it, so this checks that they are consistent with the icon side rather than equal to
    // a number guessed here, which is what would let the two drift apart.
    double cellWidth = layout.iconSide + layout.iconSpacing;
    double cellHeight = layout.iconSide + layout.labelHeight + layout.iconSpacing;
    NSUInteger fitsWide = (NSUInteger)floor((layout.grid.size.width + layout.iconSpacing) / cellWidth);
    NSUInteger fitsHigh = (NSUInteger)floor((layout.grid.size.height + layout.iconSpacing) / cellHeight);
    if (layout.columns > fitsWide || (layout.columns < fitsWide && layout.columns < CHARON_MAX_COLUMNS)) {
        bad([name stringByAppendingString:@" columns"],
             [NSString stringWithFormat:@"%d columns for icons of %.0f, where %d fit across",
              (int)layout.columns, layout.iconSide, (int)fitsWide]);
    } else {
        ok([name stringByAppendingString:
            [NSString stringWithFormat:@": %d columns of %.0f-wide icons is what fits",
             (int)layout.columns, layout.iconSide]]);
    }
    if (layout.rows > fitsHigh) {
        bad([name stringByAppendingString:@" rows"],
             [NSString stringWithFormat:@"%d rows, where only %d fit", (int)layout.rows, (int)fitsHigh]);
    } else {
        ok([name stringByAppendingString:
            [NSString stringWithFormat:@": %d rows is what fits", (int)layout.rows]]);
    }

    // Every icon and label of the page is inside the grid, and the last one is not past the edge.
    for (NSUInteger row = 0; row < layout.rows; row++) {
        for (NSUInteger column = 0; column < layout.columns; column++) {
            CharonCarPlayIconFrame frame = CharonCarPlayLayoutIconFrame(&layout, column, row);
            CGRect box = CGRectUnion(frame.icon, frame.label);
            if (!CGRectContainsRect(CGRectInset(layout.grid, -0.5, -0.5), box)) {
                bad([name stringByAppendingString:@" an icon"],
                     [NSString stringWithFormat:@"column %d row %d is outside the grid",
                      (int)column, (int)row]);
                return;
            }
        }
    }
    ok([name stringByAppendingString:@": every icon of the page is inside the grid"]);

    // An index off the page is refused rather than drawn, so a caller cannot run off the grid.
    CharonCarPlayIconFrame off = CharonCarPlayLayoutIconFrame(&layout, layout.columns, 0);
    if (!CGRectIsEmpty(off.icon) || !CGRectIsEmpty(off.label)) {
        bad([name stringByAppendingString:@" off the page"], @"an index past the last column still has a rect");
    } else {
        ok([name stringByAppendingString:@": an index past the last column is refused"]);
    }
    if (layout.iconsPerPage != layout.columns * layout.rows) {
        bad([name stringByAppendingString:@" page count"], @"the page is not columns times rows");
    } else {
        ok([name stringByAppendingString:[NSString stringWithFormat:@": %d a page", (int)layout.iconsPerPage]]);
    }
}

int main(void)
{
    // 800x480 is the 15:9 standard of Table 23-9, 960x540 and 1280x720 are the 16:9 pair. The
    // expected column counts are the floor arithmetic on the grid each one leaves, and the expected
    // icon floor is the release's own 44-point touch target raised for a car.
    check(CGSizeMake(800.0, 480.0), 48.0);
    check(CGSizeMake(960.0, 540.0), 48.0);
    check(CGSizeMake(1280.0, 720.0), 48.0);

    // And the adaptive claim itself: a bigger head unit gets BIGGER icons, not more small ones.
    CharonCarPlayLayout small = CharonCarPlayLayoutMake(CGSizeMake(800.0, 480.0), 1.0);
    CharonCarPlayLayout large = CharonCarPlayLayoutMake(CGSizeMake(1280.0, 720.0), 1.0);
    checked++;
    if (large.iconSide > small.iconSide) {
        ok([NSString stringWithFormat:@"adaptive: 1280x720 icons are %.0f against 800x480's %.0f",
            large.iconSide, small.iconSide]);
    } else {
        failures++;
        printf("FAIL adaptive: 1280x720 icons are %.0f and 800x480's are %.0f, so the grid is not "
               "sized from the screen\n", large.iconSide, small.iconSide);
    }

    // A scale other than 1 does not change the point layout: the head unit's points are its pixels
    // over its own scale, and the grid is laid out in points.
    // A 2x head unit is 1920x1080 PIXELS at a scale of 2, which is 960x540 POINTS -- the same layout.
    CharonCarPlayLayout atOne = CharonCarPlayLayoutMake(CGSizeMake(960.0, 540.0), 1.0);
    CharonCarPlayLayout atTwo = CharonCarPlayLayoutMake(CGSizeMake(960.0, 540.0), 2.0);
    checked++;
    if (near(atOne.iconSide, atTwo.iconSide, 0.5) && atOne.columns == atTwo.columns) {
        ok(@"a 2x head unit at twice the pixels is the same layout in points");
    } else {
        failures++;
        printf("FAIL the scale changes the layout: %.0f icons and %d columns at 1x against %.0f and "
               "%d at 2x\n", atOne.iconSide, (int)atOne.columns,
               atTwo.iconSide, (int)atTwo.columns);
    }

    fflush(stdout);
    printf("%d checks, %d failures\n", checked, failures);
    return failures == 0 ? 0 : 1;
}
