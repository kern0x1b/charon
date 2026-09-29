#import "CharonMetal.h"

// The type tree, read back on the device.
//
// The device never sees AIR: air2cpu runs at build time on the host and writes a property list
// beside the translation it produced, and that file is the only description of a kernel's arguments
// that reaches the device. facts/Metal/TypeTree.md is its contract and every key read here is named
// by it.
//
// MTLArgument.h declares these as CLASSES - MTLType at :229 and its subclasses at :252, :261, :277
// and :292, MTLStructMember at :234, MTLArgument at :306 - and this file is their @implementation the
// way CharonMetalTexture.m is CharonMetalTexture's. They are not redeclared here; they are implemented
// where the SDK declares them.
//
// The plist is read with NSPropertyListSerialization, which has read one since iOS 2, so this adds no
// parser of its own. Every absence is the same absence: the AIR did not say it, and this does not
// invent it.

// MTLStructMember's own storage, in the same file and for the same reason as MTLType's: this TU
// implements the class, so the ivars the implementation needs live beside it, not in a category.
@interface MTLStructMember () {
@protected
    NSString *_memberName;
    NSUInteger _memberOffset;
    NSDictionary *_memberNode;
}
@property (nonatomic, copy) NSString *charonMemberName;
@property (nonatomic, assign) NSUInteger charonMemberOffset;
@property (nonatomic, strong) NSDictionary *charonMemberNode;
@end

// The storage is on MTLType because all six classes derive from it, and it is declared in a CLASS
// EXTENSION in this same file - not in a category, which the non-fragile ABI refuses - so that the
// subclass implementations further down read the ivars directly without accessors between them.
@interface MTLType () {
@protected
    NSDictionary *_node;
    MTLType *_element;
    NSMutableArray *_members;
}
- (instancetype)initWithNode:(NSDictionary *)node;
@end


// MTLDataType from the plist's own scalar name, which is the name the emitter's typeOf() gave the
// type. MTLDataTypeNone is the header's own "no type" case (MTLArgument.h:17) and is what an absent
// or unknown scalar answers - not a case picked to be near.
static MTLDataType CharonDataTypeFromScalar(NSString *scalar)
{
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = (@{@"int32_t": @(MTLDataTypeInt), @"uint32_t": @(MTLDataTypeUInt),
                    @"uint8_t": @(MTLDataTypeUChar), @"uint16_t": @(MTLDataTypeUShort),
                    @"uint64_t": @(MTLDataTypeULong), @"float": @(MTLDataTypeFloat)});
    });
    NSNumber *found = scalar.length ? table[scalar] : nil;
    return found ? (MTLDataType)found.unsignedIntegerValue : MTLDataTypeNone;
}

// The class a node of a given kind is, built from the node. Every accessor that answers "the struct
// type", "the array type" and so on asks this one function with the node it reads, so a member and an
// argument cannot disagree about which kind names which class.
static id CharonTypedNode(NSDictionary *node, Class wanted)
{
    if (![node isKindOfClass:[NSDictionary class]])
        return nil;
    NSString *kind = node[@"kind"];
    if ([wanted isEqual:MTLStructType.class] && [kind isEqualToString:@"struct"])
        return [[MTLStructType alloc] initWithNode:node];
    if ([wanted isEqual:MTLArrayType.class] &&
        ([kind isEqualToString:@"array"] || [kind isEqualToString:@"vector"]))
        return [[MTLArrayType alloc] initWithNode:node];
    if ([wanted isEqual:MTLTextureReferenceType.class] && [kind isEqualToString:@"texture"])
        return [[MTLTextureReferenceType alloc] initWithNode:node];
    if ([wanted isEqual:MTLPointerType.class] && [kind isEqualToString:@"pointer"])
        return [[MTLPointerType alloc] initWithNode:node];
    return nil;
}

// The tree itself: the plist, read once, and the functions and arguments in it.
@interface CharonMetalTypeTree : NSObject {
@protected
    NSDictionary *_document;
}
+ (instancetype)treeWithContentsOfFile:(NSString *)path;
- (NSArray *)functions;
- (NSDictionary *)functionNamed:(NSString *)name;
- (NSArray *)argumentsOfFunction:(NSDictionary *)function;
@end

@implementation CharonMetalTypeTree

+ (instancetype)treeWithContentsOfFile:(NSString *)path
{
    CharonMetalTypeTree *tree = [[CharonMetalTypeTree alloc] init];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data)
        return tree;
    id document = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if (![document isKindOfClass:[NSDictionary class]])
        return tree;
    // A version this build does not know is not read. The contract names the versions, and reading a
    // shape this build has never seen would be a guess about keys it cannot check.
    if ([document[@"version"] integerValue] != 1)
        return tree;
    tree->_document = document;
    return tree;
}

- (NSArray *)functions
{
    return _document[@"functions"] ?: @[];
}

- (NSDictionary *)functionNamed:(NSString *)name
{
    for (NSDictionary *function in [self functions])
        if ([function[@"name"] isEqualToString:name])
            return function;
    return nil;
}

- (NSArray *)argumentsOfFunction:(NSDictionary *)function
{
    NSArray *arguments = function[@"arguments"];
    return [arguments isKindOfClass:[NSArray class]] ? arguments : @[];
}

@end

@implementation MTLType

- (instancetype)initWithNode:(NSDictionary *)node
{
    if ((self = [super init])) {
        _node = [node isKindOfClass:[NSDictionary class]] ? node : @{};
        NSDictionary *element = _node[@"elementType"];
        if (element)
            _element = [[MTLType alloc] initWithNode:element];
    }
    return self;
}

- (MTLDataType)dataType
{
    return CharonDataTypeFromScalar(_node[@"scalar"]);
}

// The type's own name: the scalar's name where the AIR gave one, the arg_type_name where it did, and
// the empty string where the AIR gave neither. A name is not invented from a kind.
- (NSString *)charonName
{
    return _node[@"scalar"] ?: _node[@"typeName"] ?: @"";
}

- (NSUInteger)charonSize
{
    return [_node[@"size"] unsignedIntegerValue];
}

- (NSUInteger)charonAlignment
{
    return [_node[@"alignSize"] unsignedIntegerValue];
}

// The kind's own word, which is what decides which class an argument's type is. A kind this build
// does not know leaves the caller with MTLType, which is the base of the five and answers MTLDataTypeNone.
- (NSString *)charonKind
{
    return _node[@"kind"] ?: @"";
}

// The member list of a struct, built on first use from the air.struct_type_info the plist carries.
- (NSMutableArray *)charonMemberList
{
    if (!_members) {
        _members = [NSMutableArray array];
        for (NSDictionary *member in _node[@"members"]) {
            if (![member isKindOfClass:[NSDictionary class]])
                continue;
            MTLStructMember *made = [[MTLStructMember alloc] init];
            made.charonMemberName = member[@"name"] ?: @"";
            made.charonMemberOffset = [member[@"offset"] unsignedIntegerValue];
            made.charonMemberNode = member[@"type"];
            [_members addObject:made];
        }
    }
    return _members;
}

@end

// MTLStructType: the members air.struct_type_info carried, by position, and the lookup by name. A
// member the AIR did not name is in the list with an empty name, because an LLVM 23 StructType has
// element types and no per-element names - the absence is in the data, and a name invented here would
// be a name the shader does not have.
@implementation MTLStructType

- (NSArray<MTLStructMember *> *)members
{
    return [self charonMemberList];
}

- (MTLStructMember *)memberByName:(NSString *)name
{
    for (MTLStructMember *member in [self members])
        if ([member.name isEqualToString:name])
            return member;
    return nil;
}

@end

// MTLArrayType: the element and the length, where the AIR carried both. A vector and an array are the
// same shape in the plist and one class answers for both, which is what MTLArray.h says the type is.
@implementation MTLArrayType

// The header's elementType is an MTLDataType, not a type object: the data type of the element, read
// from the element's own scalar, and MTLDataTypeNone where the AIR gave the element none. The element
// as an object is what the four element...Type accessors below answer.
- (MTLDataType)elementType
{
    NSDictionary *element = _node[@"elementType"];
    return [element isKindOfClass:[NSDictionary class]] ? CharonDataTypeFromScalar(element[@"scalar"])
                                                        : MTLDataTypeNone;
}

- (MTLStructType *)elementStructType
{
    return CharonTypedNode(_node[@"elementType"], MTLStructType.class);
}

- (MTLArrayType *)elementArrayType
{
    return CharonTypedNode(_node[@"elementType"], MTLArrayType.class);
}

- (MTLTextureReferenceType *)elementTextureReferenceType
{
    return CharonTypedNode(_node[@"elementType"], MTLTextureReferenceType.class);
}

- (MTLPointerType *)elementPointerType
{
    return CharonTypedNode(_node[@"elementType"], MTLPointerType.class);
}

- (NSUInteger)arrayLength
{
    return [_node[@"length"] unsignedIntegerValue];
}

// The stride is 0, and that is the absence rather than a value: the AIR carries a size and an
// alignment and no stride, and a stride computed from them would be wrong for a padded element.
- (NSUInteger)stride
{
    return 0;
}

@end

// MTLPointerType: the pointee is nil, always. LLVM has used opaque pointers since 15, so the AIR
// carries no pointee type at all - the absence is in the data, and a pointee invented here would name
// a type the shader does not have.
@implementation MTLPointerType

// The four the member audit found undefined, each read from the node the plist carries. The header's
// own comments are the contract: elementType is the element's data type, alignment is the "min
// alignment for the element data type" and dataSize is "sizeof(T) for T *argName" - and the AIR
// carries exactly those two numbers as size and alignSize, so they are MEASURED, not defaulted.
- (MTLDataType)elementType
{
    NSDictionary *element = _node[@"elementType"];
    return [element isKindOfClass:[NSDictionary class]] ? CharonDataTypeFromScalar(element[@"scalar"])
                                                        : MTLDataTypeNone;
}

- (MTLArgumentAccess)access
{
    // The same three words MTLArgument reads, from the same key, and the same rule: a key this build
    // does not know is the enumeration's zero rather than a guess.
    NSString *access = _node[@"access"];
    if ([access isEqualToString:@"read-write"])
        return MTLArgumentAccessReadWrite;
    if ([access isEqualToString:@"write-only"])
        return MTLArgumentAccessWriteOnly;
    return MTLArgumentAccessReadOnly;
}

- (NSUInteger)alignment
{
    return [_node[@"alignSize"] unsignedIntegerValue];
}

- (NSUInteger)dataSize
{
    return [_node[@"size"] unsignedIntegerValue];
}

- (MTLType *)pointee
{
    return nil;
}

// The two element accessors the header declares on a pointer: nil, for the same reason as pointee.
- (MTLStructType *)elementStructType
{
    return nil;
}

- (MTLArrayType *)elementArrayType
{
    return nil;
}

@end

// MTLTextureReferenceType: the texture's data type is MTLDataTypeNone, the header's own "no type",
// because the plist carries no texture data type for an argument of this kind. 2D would be a guess
// from a name.
@implementation MTLTextureReferenceType

// textureType, access and isDepthTexture, the three the audit found undefined. textureType is the one
// with no measured answer: the plist carries no texture type for a texture argument, and
// MTLTextureType's enumeration has no "none" case - it starts at 2D. So the value below is a DEFAULT
// and the facts file says so: a texture argument this port carries is a 2D texture, and the header's
// own list is "texture1D, texture2D..." - a caller reading it back gets the shape the port builds.
- (MTLTextureType)textureType
{
    return MTLTextureType2D;
}

- (MTLArgumentAccess)access
{
    NSString *access = _node[@"access"];
    if ([access isEqualToString:@"read-write"])
        return MTLArgumentAccessReadWrite;
    if ([access isEqualToString:@"write-only"])
        return MTLArgumentAccessWriteOnly;
    return MTLArgumentAccessReadOnly;
}

- (BOOL)isDepthTexture
{
    // NO, and the absence is the plist's: it carries no depth flag for an argument of this kind, so
    // there is nothing that says the texture is a depth one.
    return NO;
}

- (MTLDataType)textureDataType
{
    return MTLDataTypeNone;
}

@end

// MTLStructMember: the name, the offset and the data type the metadata carried, and the four typed
// accessors the header declares as nullable. Each returns the subclass its plist kind names and nil
// where the kind names none, which is what a nullable MTLStructType * says for a member that is not a
// struct - and nil is also what a member whose kind this build does not know gets.
@implementation MTLStructMember

@synthesize charonMemberName = _memberName;
@synthesize charonMemberOffset = _memberOffset;
@synthesize charonMemberNode = _memberNode;

- (NSString *)name
{
    return _memberName ?: @"";
}

- (NSUInteger)offset
{
    return _memberOffset;
}

- (MTLDataType)dataType
{
    return [_memberNode isKindOfClass:[NSDictionary class]]
               ? CharonDataTypeFromScalar(_memberNode[@"scalar"]) : MTLDataTypeNone;
}

- (MTLStructType *)structType
{
    return CharonTypedNode(_memberNode, MTLStructType.class);
}

- (MTLArrayType *)arrayType
{
    return CharonTypedNode(_memberNode, MTLArrayType.class);
}

- (MTLTextureReferenceType *)textureReferenceType
{
    return CharonTypedNode(_memberNode, MTLTextureReferenceType.class);
}

- (MTLPointerType *)pointerType
{
    return CharonTypedNode(_memberNode, MTLPointerType.class);
}

- (NSUInteger)argumentIndex
{
    return [_memberNode isKindOfClass:[NSDictionary class]] ? [_memberNode[@"index"] unsignedIntegerValue] : 0;
}

@end

// MTLArgument: one argument, as the metadata node for it reads.
//
// The AIR says what kind of thing an argument is in two places that agree: its type class
// (air.buffer, air.texture) and its address space. The type class is the one used here, because it is
// what the argument node names and it is not a number that has to be mapped. The address space is
// worth recording beside it and is not used to decide anything: MTLArgument.h:196-201 gives
// MTLArgumentTypeBuffer = 0, MTLArgumentTypeThreadgroupMemory = 1, MTLArgumentTypeTexture = 2 and
// MTLArgumentTypeSampler = 3, and the measured real libraries put a buffer in space 1, another buffer
// in space 2 and one more in space 3, so a space does not name a type on its own.
// MTLArgument is declared by the port's own header as well as by MTLArgument.h:306, so this is a
// CATEGORY carrying only the two method declarations, and the storage goes into the @implementation's
// own braces - which the non-fragile ABI allows and which is why the classes above use extensions.
@interface MTLArgument (CharonTypeTree)
- (instancetype)initWithNode:(NSDictionary *)node;
@end

@implementation MTLArgument {
    NSDictionary *_argument;
}

- (instancetype)initWithNode:(NSDictionary *)node
{
    if ((self = [super init]))
        _argument = [node isKindOfClass:[NSDictionary class]] ? node : @{};
    return self;
}

- (NSString *)name
{
    return _argument[@"name"] ?: @"";
}

- (NSUInteger)index
{
    return [_argument[@"index"] unsignedIntegerValue];
}

// The two enumeration words the plist carries, mapped from the header's own enumerators. An access
// the AIR did not say is MTLArgumentAccessReadOnly - the enumeration's zero - because a key this
// build does not know is not a read-write, and the argument's effect is written from the access the
// metadata carried.
- (MTLArgumentType)type
{
    NSString *class = _argument[@"typeClass"];
    if ([class isEqualToString:@"texture"])
        return MTLArgumentTypeTexture;
    if ([class isEqualToString:@"sampler"])
        return MTLArgumentTypeSampler;
    if ([class isEqualToString:@"threadgroup"])
        return MTLArgumentTypeThreadgroupMemory;
    return MTLArgumentTypeBuffer;
}

- (MTLArgumentAccess)access
{
    NSString *access = _argument[@"access"];
    if ([access isEqualToString:@"read-write"])
        return MTLArgumentAccessReadWrite;
    if ([access isEqualToString:@"write-only"])
        return MTLArgumentAccessWriteOnly;
    return MTLArgumentAccessReadOnly;
}

// An argument of a kernel this port dispatches is bound before the dispatch is encoded, so it is
// active; an argument of one that was refused is never reached. The port records the refusal, it does
// not make an argument inactive.
// active is a @property with getter=isActive, so the property and the method are ONE thing here and
// the implementation is the method the header names.
- (BOOL)isActive
{
    return YES;
}

- (NSUInteger)bufferAlignment
{
    return [_argument[@"alignSize"] unsignedIntegerValue];
}

- (NSUInteger)bufferDataSize
{
    return [_argument[@"size"] unsignedIntegerValue];
}

- (MTLDataType)bufferDataType
{
    return CharonDataTypeFromScalar(_argument[@"scalar"]);
}

- (MTLStructType *)bufferStructType
{
    return CharonTypedNode(_argument, MTLStructType.class);
}

- (MTLPointerType *)bufferPointerType
{
    return CharonTypedNode(_argument, MTLPointerType.class);
}

- (MTLArrayType *)bufferArrayType
{
    return CharonTypedNode(_argument, MTLArrayType.class);
}

// The threadgroup members answer 0 and nil: a threadgroup argument is one the AIR marked in address
// space 3, and the plist carries no size or alignment for one. That is the absence, not a zero-length
// threadgroup, and the row says which is which.
- (NSUInteger)threadgroupMemoryAlignment
{
    return 0;
}

- (NSUInteger)threadgroupMemoryDataSize
{
    return 0;
}

// MTLTextureType's "no type" case. The 26.2 headers spell the enumeration MTLTextureType with
// MTLTextureTypeUnknown = 0, and the port's own headers may not carry the name, so it is a named
// constant at the enumeration's own zero rather than a number that only looks like one.
- (MTLTextureType)textureType
{
    return (MTLTextureType)0;
}

- (MTLDataType)textureDataType
{
    return MTLDataTypeNone;
}

- (BOOL)isDepthTexture
{
    return NO;
}

- (NSUInteger)arrayLength
{
    return [_argument[@"arrayLength"] unsignedIntegerValue];
}

@end
