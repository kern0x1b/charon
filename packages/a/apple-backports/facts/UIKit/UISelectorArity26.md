// Facts: eight 26.0 selectors of UIKit's ios26 band were defined without their argument, and what the
// SDK, the object and the registry each said about it.
//
// THE DEFECT.  Eight methods of UIKit26_0.m were declared with no parameter where the SDK 26.2 header
// declares one, and a parameter is part of an Objective-C selector.  So the object exported eight names
// no Apple SDK has ever declared, and the eight selectors the queue's rows name - and that an
// application calls - were absent, so a call raised `unrecognized selector sent to instance` against
// this library.  Four of the eight rows carried the wrong spelling as well, which is why the mistake
// survived: the row and the definition agreed with each other and both differed from the SDK.
//
//   object before                                    SDK 26.2 declares
//   - (UIColor *)colorByApplyingContentHeadroom       - (UIColor *)colorByApplyingContentHeadroom:(CGFloat)contentHeadroom
//   - (void)alignLeft                                 - (void)alignLeft:(nullable id)sender
//   - (void)alignCenter                               - (void)alignCenter:(nullable id)sender
//   - (void)alignRight                                - (void)alignRight:(nullable id)sender
//   - (void)alignJustified                            - (void)alignJustified:(nullable id)sender
//   - (void)newFromPasteboard                         - (void)newFromPasteboard:(nullable id)sender
//   - (void)performClose                              - (void)performClose:(nullable id)sender
//   - (void)toggleInspector                           - (void)toggleInspector:(nullable id)sender
//
// WHAT THE HEADER SAYS, read out of the SDK on this machine.  $SDK below is the 26.2 SDK the registry's
// own surface was generated from (`coordination/corpus/sdk-26.2-surface.tsv`, 145301 rows, whose
// `introduced` column is what a row's `introduced` means).
//
//   SDK=$(ls -d $HOME/.xmake/packages/i/iphoneos-sdk/26.2/*/Developer.app/Contents/Developer/\
//         Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.2.sdk | head -1)
//
//   grep -n 'colorByApplyingContentHeadroom' $SDK/System/Library/Frameworks/UIKit.framework/Headers/UIColor.h
//   64:- (UIColor *)colorByApplyingContentHeadroom:(CGFloat)contentHeadroom API_AVAILABLE(ios(26.0), \
//      tvos(26.0), watchos(26.0), visionos(26.0)) NS_SWIFT_NAME(applyingContentHeadroom(_:));
//
//   grep -n -E '^- \(void\)(alignLeft|alignCenter|alignRight|alignJustified|newFromPasteboard|\
//        performClose|toggleInspector):' $SDK/System/Library/Frameworks/UIKit.framework/Headers/UIResponder.h
//   40:- (void)newFromPasteboard:(nullable id)sender API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(watchos);
//   53:- (void)alignLeft:(nullable id)sender API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(watchos);
//   54:- (void)alignCenter:(nullable id)sender API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(watchos);
//   55:- (void)alignJustified:(nullable id)sender API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(watchos);
//   56:- (void)alignRight:(nullable id)sender API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(watchos);
//   73:- (void)toggleInspector:(nullable id)sender API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(watchos);
//   75:- (void)performClose:(nullable id)sender API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(watchos);
//
// The same grep over the whole of $SDK/System/Library/Frameworks returns the UIColor line and nothing
// else, so there is no second, argument-less spelling anywhere in the SDK:
//
//   grep -rn 'colorByApplyingContentHeadroom' $SDK/System/Library/Frameworks/
//   .../UIKit.framework/Headers/UIColor.h:64:- (UIColor *)colorByApplyingContentHeadroom:(CGFloat)contentHeadroom ...
//
// WHAT otool PRINTS, because the commit that introduced the defect gave a reason for it and the reason
// is what let it through.  8da6723e0 says: "__objc_methname prints a no-argument selector WITHOUT its
// trailing colon, so -[UIColor colorByApplyingContentHeadroom:] is in the object as
// colorByApplyingContentHeadroom.  A check that compared the queue's spelling exactly reported 117 of
// 125 - it was wrong about the check, not about the code."  That is false, and a three-method probe
// shows it.  This is the command, and its whole output:
//
//   cat > /tmp/probe.m <<'EOF'
//   @interface Probe : NSObject
//   @end
//   @implementation Probe
//   - (id)noArgument { return self; }
//   - (id)oneArgument:(double)x { return self; }
//   - (id)twoArguments:(double)x and:(double)y { return self; }
//   @end
//   EOF
//   clang-23 -c -fobjc-arc -target armv7-apple-ios6.1.3 -isysroot <16.4 SDK> -w \
//       -include Foundation/Foundation.h /tmp/probe.m -o /tmp/probe.o
//   otool -v -s __TEXT __objc_methname /tmp/probe.o
//   probe.o:
//   Contents of (__TEXT,__objc_methname) section
//   00000104  noArgument
//   0000010f  oneArgument:
//   0000011c  twoArguments:and:
//
// `oneArgument:` is printed WITH its trailing colon.  So the section never dropped a colon: the object
// carried a method with no parameter, and the row was renamed to match it.  The comment above those
// seven definitions in UIKit26_0.m already said "an unrelated object also answers YES to -alignLeft:",
// with the colon, while the bodies below it had none.
//
// WHAT THE OBJECT CARRIES NOW, read out of the object rather than out of the source - the same read the
// registry check makes, and the check's own spelling:
//
//   clang-23 -c -fobjc-arc -target armv7-apple-ios6.1.3 -isysroot <16.4 SDK> -Wall \
//       packages/a/apple-backports/UIKit/UIKit26_0.m -o /tmp/UIKit26_0.o
//   otool -v -s __TEXT __objc_methname /tmp/UIKit26_0.o | sed -n 's/^[0-9a-f]*  //p' | grep -E \
//       '^(colorByApplyingContentHeadroom:|align(Left|Center|Right|Justified):|newFromPasteboard:|\
//       performClose:|toggleInspector:)$'
//   colorByApplyingContentHeadroom:
//   alignLeft:
//   alignCenter:
//   alignRight:
//   alignJustified:
//   newFromPasteboard:
//   performClose:
//   toggleInspector:
//
// 160 selectors in the object, the same 160 as before the fix: eight definitions changed their spelling
// and no definition was added or removed.  The eight queue rows that the object's exports did not answer
// - the whole of the "117 of 125" gap - are these eight.
//
// WHY NOTHING ELSE IN THE BAND HAS THIS DEFECT.  The same three commands were run over every row of the
// band's queue: each of the 124 rows' selectors and class names is looked up in the object's
// __objc_methname and __objc_classname, and each of the 50 property rows is resolved to the accessors
// its SDK declaration implies.  Every other row is present under its own spelling, and the 92
// implemented method rows' return types were compared with the SDK's declarations the same way: the
// only disagreement is UIViewPropertyAnimator.flushUpdates, which the SDK declares a readwrite BOOL
// property and the object defined as `- (void)flushUpdates`.  facts/UIKit/UIContentUnavailable26.md
// carries that one.
//
// THE SEVEN EDIT ACTIONS ARE MEMBERS OF A PROTOCOL, so what this fix does NOT change is where they live.
// UIResponderStandardEditActions is a @protocol in every release the port stages, and A CATEGORY CANNOT
// BE ON A PROTOCOL, so the seven are categories on NSObject and the seven rows spelled with the
// protocol's own name stay `absent`, each naming the NSObject row that carries its selector.  Those
// seven `-[NSObject ...:]` rows are the ones whose `api` token was re-spelled here; their own `effect`
// text already named the selectors with the colon, so the spelling was the only thing about them that
// was wrong.