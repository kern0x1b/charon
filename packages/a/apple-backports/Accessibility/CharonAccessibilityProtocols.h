// CharonAccessibilityProtocols.h - what the generated protocol sources of this library import.
//
// modules/apple/backports.lua writes one source per release a library's implemented protocol rows
// arrived in, and every one of them opens with `#import "CharonAccessibilityProtocols.h"`. The
// framework's own header is what the generated source needs: a name it references has to have a body
// where the source is compiled, or clang has a forward reference and no metadata to emit, and the
// object the whole mechanism exists for would carry none.
//
// Both protocols of the two groups this library carries are declared by the SDK the package compiles
// against, so nothing is transcribed here and the two forward declarations below are only so that a
// reader sees which names the generated sources name. If a later group brings a protocol the SDK of
// 16.4 does not declare - AXMathExpressionProvider with AXMathExpression.h, and the two protocols of
// the content and braille-map groups - that name is transcribed here, from the SDK that declares it,
// and its member list is written out with the kinds and types the header gives it.
//
// Usage: nothing imports this by hand. It is the one header the build's own generated sources name.
#import <Accessibility/Accessibility.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol AXChart;

@protocol AXDataAxisDescriptor;

// AXBrailleMapRenderer arrived with a later group, in 15.2, and a generated protocol source names it too.
// The 16.4 SDK declares it in AXBrailleMap.h, which the umbrella import above brings in, so a forward
// declaration is the whole of what this file owes it - the same as the two above, and the same as what
// tools/transcribe-protocols.py writes for a protocol the SDK the package compiles against defines.
@protocol AXBrailleMapRenderer;
