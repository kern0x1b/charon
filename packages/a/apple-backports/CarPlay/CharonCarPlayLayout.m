#import "CharonCarPlayLayout.h"

// The arithmetic, and the reasoning behind each number, once.
//
// A car's screen is seen from further away than a phone's, so nothing here is sized for a phone: the
// icon floor is the release's own 44-point minimum touch target raised to 48 for a car, the dock is
// wide enough for a clock at 28 points next to a status column, and the grid takes the rest. What is
// NOT here is a resolution: 800x480, 960x540 and 1280x720 all come out of the same arithmetic, and
// tests/backports/host/mapkit-carplay checks exactly that.
#define CHARON_CARPLAY_ICON_FLOOR 48.0
#define CHARON_CARPLAY_DOCK_MINIMUM 120.0
#define CHARON_CARPLAY_DOCK_FRACTION 0.17
#define CHARON_CARPLAY_GRID_MARGIN 24.0
#define CHARON_CARPLAY_ICON_SPACING 18.0
#define CHARON_CARPLAY_LABEL_HEIGHT 22.0
#define CHARON_CARPLAY_MIN_COLUMNS 3
#define CHARON_CARPLAY_MAX_COLUMNS 8
#define CHARON_CARPLAY_MIN_ROWS 2
#define CHARON_CARPLAY_ICON_WIDTH_FRACTION 0.19
#define CHARON_CARPLAY_ICON_HEIGHT_FRACTION 0.28
#define CHARON_CARPLAY_ICON_CEILING 168.0

CharonCarPlayLayout CharonCarPlayLayoutMake(CGSize size, CGFloat scale)
{
    CharonCarPlayLayout layout;
    layout.screen = size;
    layout.scale = scale > 0.0 ? scale : 1.0;
    layout.cornerRadius = 10.0;
    // The gloss is the release's own proportion of a control's height: a little under half, which is
    // what a UIBarStyleBlack button and an iOS 6 table cell both do.
    layout.glossHeight = 0.48;

    // The dock: a fraction of the width, never less than the width a clock and a status column need,
    // and never more than a quarter, so a wide head unit does not lose its grid to the dock.
    CGFloat dock = size.width * CHARON_CARPLAY_DOCK_FRACTION;
    if (dock < CHARON_CARPLAY_DOCK_MINIMUM) {
        dock = CHARON_CARPLAY_DOCK_MINIMUM;
    }
    if (dock > size.width / 4.0) {
        dock = size.width / 4.0;
    }
    layout.dockWidth = dock;
    layout.dock = CGRectMake(0.0, 0.0, dock, size.height);

    // The grid: the rest of the screen, less the margin on every side.
    CGFloat gridLeft = dock + CHARON_CARPLAY_GRID_MARGIN;
    CGFloat gridWidth = size.width - gridLeft - CHARON_CARPLAY_GRID_MARGIN;
    CGFloat gridTop = CHARON_CARPLAY_GRID_MARGIN;
    CGFloat gridHeight = size.height - 2.0 * CHARON_CARPLAY_GRID_MARGIN;
    if (gridWidth < 1.0) { gridWidth = 1.0; }
    if (gridHeight < 1.0) { gridHeight = 1.0; }
    layout.grid = CGRectMake(gridLeft, gridTop, gridWidth, gridHeight);
    layout.iconSpacing = CHARON_CARPLAY_ICON_SPACING;
    layout.labelHeight = CHARON_CARPLAY_LABEL_HEIGHT;

    // The ICON SIDE comes first and the counts follow from it, which is what makes the grid adaptive
    // rather than a fixed number of small icons: an icon is a fraction of the grid's own size, so a
    // bigger head unit gets bigger touch targets and fewer of them, and a small one still gets the
    // floor. The floor is the release's own 44-point minimum touch target raised to 48 for a car,
    // which is seen from further away than a phone; the ceiling keeps an icon from becoming a poster.
    CGFloat side = layout.grid.size.width * CHARON_CARPLAY_ICON_WIDTH_FRACTION;
    CGFloat byHeight = layout.grid.size.height * CHARON_CARPLAY_ICON_HEIGHT_FRACTION;
    if (byHeight < side) {
        side = byHeight;
    }
    if (side < CHARON_CARPLAY_ICON_FLOOR) {
        side = CHARON_CARPLAY_ICON_FLOOR;
    }
    if (side > CHARON_CARPLAY_ICON_CEILING) {
        side = CHARON_CARPLAY_ICON_CEILING;
    }
    layout.iconSide = side;

    // And the counts are what fit, so nothing is ever drawn outside the grid.
    layout.columns = (NSUInteger)floor((layout.grid.size.width + layout.iconSpacing) / (side + layout.iconSpacing));
    if (layout.columns < CHARON_CARPLAY_MIN_COLUMNS) {
        layout.columns = CHARON_CARPLAY_MIN_COLUMNS;
    }
    if (layout.columns > CHARON_CARPLAY_MAX_COLUMNS) {
        layout.columns = CHARON_CARPLAY_MAX_COLUMNS;
    }
    layout.rows = (NSUInteger)floor((layout.grid.size.height + layout.iconSpacing) /
                                    (side + layout.labelHeight + layout.iconSpacing));
    if (layout.rows < 1) {
        layout.rows = 1;
    }
    layout.iconsPerPage = layout.columns * layout.rows;
    return layout;
}

CharonCarPlayIconFrame CharonCarPlayLayoutIconFrame(const CharonCarPlayLayout *layout, NSUInteger column, NSUInteger row)
{
    CharonCarPlayIconFrame frame;
    frame.icon = CGRectZero;
    frame.label = CGRectZero;
    if (!layout || column >= layout->columns || row >= layout->rows) {
        return frame;
    }
    CGFloat cellWidth = layout->iconSide + layout->iconSpacing;
    CGFloat cellHeight = layout->iconSide + layout->labelHeight + layout->iconSpacing;
    // The grid is centred in what it has, so a wide head unit gets the icons in the middle of the
    // area rather than against the dock, and the dock never grows into them.
    CGFloat usedWidth = layout->columns * layout->iconSide + (layout->columns - 1) * layout->iconSpacing;
    CGFloat usedHeight = layout->rows * (layout->iconSide + layout->labelHeight) +
                         (layout->rows - 1) * layout->iconSpacing;
    CGFloat originX = layout->grid.origin.x + (layout->grid.size.width - usedWidth) / 2.0;
    CGFloat originY = layout->grid.origin.y + (layout->grid.size.height - usedHeight) / 2.0;
    frame.icon = CGRectMake(originX + (CGFloat)column * cellWidth, originY + (CGFloat)row * cellHeight,
                            layout->iconSide, layout->iconSide);
    frame.label = CGRectMake(frame.icon.origin.x - layout->iconSpacing / 2.0,
                             CGRectGetMaxY(frame.icon) + 2.0,
                             layout->iconSide + layout->iconSpacing, layout->labelHeight);
    return frame;
}
