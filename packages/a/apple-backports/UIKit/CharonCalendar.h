#import <UIKit/UIKit.h>

// The calendar's own parts reach one another through these methods. The release has no such methods: they are the port's, declared
// here so that UICalendarView, its decorations and its selection behaviours, which are built in separate files, agree on them.

@interface UICalendarView (CharonParts)
// The view's calendar, with the view's time zone applied when one is set; every date the view computes goes through it.
- (NSCalendar *)charon_calendarForDates;
// The day under a point of the view, as the components of that day, or nil on the header, the weekday row, a blank cell or a day outside
// the view's available range.
- (NSDateComponents *)charon_dateAtPoint:(CGPoint)point;
@end

@interface UICalendarViewDecoration (CharonParts)
// Draws the decoration into a day cell's rectangle, at the cell's foot; the cell's number is above it.
- (void)charon_drawInRect:(CGRect)rect;
@end

@interface UICalendarSelection (CharonParts)
// The view the selection behaviour is attached to, or nil when it is not in a calendar view.
- (void)charon_attachToView:(UICalendarView *)view;
// Whether the day is selected now.
- (BOOL)charon_isSelected:(NSDateComponents *)day;
// Whether the day can be selected, asked of the delegate; YES where there is no delegate answer.
- (BOOL)charon_canSelect:(NSDateComponents *)day;
// A tap on a day: the behaviour changes its selection and tells its delegate.
- (void)charon_didTapDay:(NSDateComponents *)day;
@end
