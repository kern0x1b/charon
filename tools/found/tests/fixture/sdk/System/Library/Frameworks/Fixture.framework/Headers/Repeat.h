// Repeats declarations of Fixture.h with other parameter names: the extractor emits the first one only.
//! A //! comment is not a doc comment of the doc mode: the typedef below has no doc text.
typedef int FXCount;
/** Runs the total.
 *  The total is added to the sum. */
void FXRun(int total);
void FXVersioned(void) __attribute__((availability(ios, introduced=17.0)));
/// Doubles a value.
int FXDouble(int value);
#define FX_TYPE_AVAILABLE __attribute__((availability(ios, introduced=16.0)))
typedef const struct FXString *FXStringRef;
extern const FXStringRef __nonnull FXConstName;
extern const char *const FXConstPointer;
extern char *const FXPointerConst;
extern const char *FXPointerToConst;
extern const int FXConstInt;
extern FX_TYPE_AVAILABLE const FXStringRef FXMacroConst;
extern FX_TYPE_AVAILABLE char *const FXMacroPointer;
#define FX_REFINED_FOR_SWIFT __attribute__((swift_private))
extern const FXStringRef FX_REFINED_FOR_SWIFT __nonnull FXRefinedName;
