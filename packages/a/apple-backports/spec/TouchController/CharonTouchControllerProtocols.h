// CharonTouchControllerProtocols.h - the TouchController protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// Every protocol in this file is transcribed here, so it imports no framework header: their members name classes this header forward-declares. A file with a forward-declared protocol in it does import <TouchController/TouchController.h>, for that one body.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

typedef enum TCColliderShape TCColliderShape;
@class TCControlLabel;
API_AVAILABLE(ios(26.0))
@protocol TCControl <NSObject, TCControlLayout>
@property (nonatomic, readonly, strong) TCControlLabel * _Nonnull label;
@property (nonatomic, readonly, assign, unsafe_unretained) TCColliderShape colliderShape;
@property (nonatomic, readonly, assign, unsafe_unretained, getter=isPressed) BOOL pressed;
@property (nonatomic, readwrite, assign, unsafe_unretained, getter=isEnabled) BOOL enabled;
- (void)handleTouchBeganAtPoint:(CGPoint)point;
- (void)handleTouchMovedAtPoint:(CGPoint)point;
- (void)handleTouchEndedAtPoint:(CGPoint)point;
@optional
@property (nonatomic, readwrite, assign, unsafe_unretained) NSTimeInterval highlightDuration;
@end

typedef enum TCControlLayoutAnchor TCControlLayoutAnchor;
typedef enum TCControlLayoutAnchorCoordinateSystem TCControlLayoutAnchorCoordinateSystem;
API_AVAILABLE(ios(26.0))
@protocol TCControlLayout <NSObject>
@property (nonatomic, readwrite, assign, unsafe_unretained) TCControlLayoutAnchor anchor;
@property (nonatomic, readwrite, assign, unsafe_unretained) TCControlLayoutAnchorCoordinateSystem anchorCoordinateSystem;
@property (nonatomic, readwrite, assign, unsafe_unretained) CGPoint offset;
@property (nonatomic, readwrite, assign, unsafe_unretained) NSInteger zIndex;
@property (nonatomic, readwrite, assign, unsafe_unretained) CGSize size;
@property (nonatomic, readonly, assign, unsafe_unretained) CGPoint position;
@end
