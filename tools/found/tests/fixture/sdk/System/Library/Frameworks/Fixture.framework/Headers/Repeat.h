// Repeats declarations of Fixture.h with other parameter names: the extractor emits the first one only.
typedef int FXCount;
/** Runs the total.
 *  The total is added to the sum. */
void FXRun(int total);
void FXVersioned(void) __attribute__((availability(ios, introduced=17.0)));
