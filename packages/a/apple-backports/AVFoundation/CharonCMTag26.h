#import <CoreMedia/CoreMedia.h>
#import <CoreFoundation/CoreFoundation.h>

// CMTag, CMTagCollection and CMTaggedBufferGroup, transcribed from the SDK 26.2 headers the port is
// written against, which is what every band does for surface that arrived after the SDK the toolchain
// resolves (Intents' CharonIntents262.h, CloudKit's CharonCKSyncEngine26.h, CarPlay's and WebKit's).
// The declarations below are 26.2's own, character for character, and nothing here is invented; the
// names the port adds beyond the SDK are listed in the delivery for rule R4.
//
//   iPhoneOS26.2.sdk/System/Library/Frameworks/CoreMedia.framework/Headers/CMTag.h
//   .../CMTagCollection.h
//   .../CMTaggedBufferGroup.h

#if !__has_include(<CoreMedia/CMTag.h>)

typedef CF_ENUM(FourCharCode, CMTagCategory)
{
	kCMTagCategory_Undefined CF_REFINED_FOR_SWIFT	= 0,
	kCMTagCategory_MediaType 						= 'mdia',
	kCMTagCategory_MediaSubType 					= 'msub',
	kCMTagCategory_TrackID 							= 'trak',
	kCMTagCategory_ChannelID 						= 'vchn',
	kCMTagCategory_VideoLayerID						= 'vlay',
	kCMTagCategory_PixelFormat 						= 'pixf',
	kCMTagCategory_PackingType						= 'pack',
	kCMTagCategory_ProjectionType 					= 'proj',
	kCMTagCategory_StereoView 					= 'eyes',
	kCMTagCategory_StereoViewInterpretation 	= 'eyip',
} CF_REFINED_FOR_SWIFT;

typedef CF_ENUM( uint32_t, CMTagDataType ) {
	kCMTagDataType_Invalid CF_REFINED_FOR_SWIFT	= 0,
	kCMTagDataType_SInt64						= 2,
	kCMTagDataType_Float64 						= 3,
	kCMTagDataType_OSType 						= 5,
	kCMTagDataType_Flags 						= 7,
} CF_REFINED_FOR_SWIFT;

typedef uint64_t CMTagValue CF_REFINED_FOR_SWIFT;

struct CMTag {
	CMTagCategory category;
	CMTagDataType dataType;
	CMTagValue value;
} CF_REFINED_FOR_SWIFT;
typedef struct CMTag CMTag CF_REFINED_FOR_SWIFT;

CF_INLINE Boolean CMTagIsValid( CMTag tag ) CF_REFINED_FOR_SWIFT
{
	return tag.dataType != kCMTagDataType_Invalid;
}

CF_INLINE CMTagValue CMTagGetValue( CMTag tag ) CF_REFINED_FOR_SWIFT
{
	return tag.value;
}

CF_INLINE CMTagDataType CMTagGetValueDataType( CMTag tag ) CF_REFINED_FOR_SWIFT
{
	return tag.dataType;
}

CF_INLINE CMTagCategory CMTagGetCategory( CMTag tag ) CF_REFINED_FOR_SWIFT
{
	return tag.category;
}

typedef CF_ENUM(OSStatus, CMTagCollectionError)
{
	kCMTagCollectionError_ParamErr 							= -15740,
	kCMTagCollectionError_AllocationFailed 					= -15741,
	kCMTagCollectionError_InternalError 					= -15742,
	kCMTagCollectionError_InvalidTag						= -15743,
	kCMTagCollectionError_InvalidTagCollectionDictionary	= -15744,
	kCMTagCollectionError_InvalidTagCollectionData			= -15745,
	kCMTagCollectionError_TagNotFound						= -15746,
	kCMTagCollectionError_InvalidTagCollectionDataVersion 	= -15747,
	kCMTagCollectionError_ExhaustedBufferSize 				= -15748,
	kCMTagCollectionError_NotYetImplemented					= -15749
} CF_SWIFT_UNAVAILABLE("Unavailable in Swift");

typedef Boolean (*CMTagCollectionTagFilterFunction)(CMTag tag, void *context) CF_SWIFT_UNAVAILABLE("Unavailable in Swift");

typedef const struct CM_BRIDGED_TYPE(id) OpaqueCMTagCollection * CMTagCollectionRef
    CF_REFINED_FOR_SWIFT;
typedef struct CM_BRIDGED_TYPE(id) OpaqueCMutableTagCollection * CMMutableTagCollectionRef CF_SWIFT_UNAVAILABLE("Unavailable in Swift");
typedef struct CM_BRIDGED_TYPE(id) OpaqueCMTaggedBufferGroup * CMTaggedBufferGroupRef
    CF_REFINED_FOR_SWIFT;

typedef void (*CMTagCollectionApplierFunction)(CMTag tag, void *context) CF_SWIFT_UNAVAILABLE("Unavailable in Swift");
typedef CMTag (*CMTagCollectionApplyUntilResult)(void);

CF_EXPORT const CFStringRef kCMTagCategoryKey CF_SWIFT_UNAVAILABLE("Unavailable in Swift");
CF_EXPORT const CFStringRef kCMTagValueKey CF_SWIFT_UNAVAILABLE("Unavailable in Swift");
CF_EXPORT const CFStringRef kCMTagDataTypeKey CF_SWIFT_UNAVAILABLE("Unavailable in Swift");

CF_EXPORT const CMTag kCMTagInvalid CF_REFINED_FOR_SWIFT;

#endif

// The port's own class behind the bridged reference, named so it cannot collide with the SDK's.
// The collection's class is declared in CharonCMTagSupport.h, next to its implementation, so
// this header carries only the tag types it needs.

