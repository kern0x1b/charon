// CharonMetalProtocols.h — the Metal protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <Metal/Metal.h> for that body, and
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol MTLAccelerationStructure;

@protocol MTLAccelerationStructureCommandEncoder;

@protocol MTLBinaryArchive;

@protocol MTLBinding;

@protocol MTLBlitCommandEncoder;

@protocol MTLBufferBinding;

@protocol MTLCaptureScope;

@protocol MTLCommandBufferEncoderInfo;

@protocol MTLComputeCommandEncoder;

@protocol MTLComputePipelineState;

@protocol MTLCounter;

@protocol MTLCounterSampleBuffer;

@protocol MTLCounterSet;

@protocol MTLDepthStencilState;

@protocol MTLDrawable;

@protocol MTLDynamicLibrary;

@protocol MTLFunction;

@protocol MTLFunctionHandle;

@protocol MTLFunctionLog;

@protocol MTLFunctionLogDebugLocation;

@protocol MTLFunctionStitchingAttribute;

@protocol MTLFunctionStitchingNode;

@protocol MTLHeap;

@protocol MTLIntersectionFunctionTable;

@protocol MTLLogContainer;

@protocol MTLObjectPayloadBinding;

@protocol MTLResource;

@protocol MTLSamplerState;

@protocol MTLSharedEvent;

@protocol MTLTextureBinding;

@protocol MTLThreadgroupBinding;

@protocol MTLVisibleFunctionTable;
