// CharonMetalKitProtocols.h — the MetalKit protocols the SDK this package compiles against does not declare,
// transcribed from the SDK that does, by .agent-work/probe/transcribe-protocols.py: the base list,
// the member names, their types and whether each is required or optional, as the compiler reports
// them. Facts only, and API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the
// release it arrived in. A protocol a band's own header already declares is not here.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(9.0))
@protocol MTKViewDelegate <NSObject>
- (void)mtkView:(MTKView * _Nonnull)view drawableSizeWillChange:(CGSize)size;
- (void)drawInMTKView:(MTKView * _Nonnull)view;
@end
