#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UTType : NSObject <NSCopying>

@property (readonly, copy) NSString *identifier;
@property (readonly, nullable, copy) NSString *preferredFilenameExtension;
@property (readonly, nullable, copy) NSString *preferredMIMEType;
@property (readonly, nullable, copy) NSString *localizedDescription;
@property (readonly, copy) NSDictionary<NSString *, NSArray<NSString *> *> *tags;
@property (readonly, getter=isDynamic) BOOL dynamic;
@property (readonly, getter=isDeclared) BOOL declared;
@property (readonly, getter=isPublicType) BOOL publicType;

+ (nullable instancetype)typeWithIdentifier:(NSString *)identifier;
+ (nullable instancetype)typeWithFilenameExtension:(NSString *)filenameExtension;
+ (nullable instancetype)typeWithFilenameExtension:(NSString *)filenameExtension conformingToType:(nullable UTType *)supertype;
+ (nullable instancetype)typeWithMIMEType:(NSString *)mimeType;
+ (nullable instancetype)typeWithMIMEType:(NSString *)mimeType conformingToType:(nullable UTType *)supertype;
+ (nullable instancetype)typeWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(nullable UTType *)supertype;
+ (NSArray<UTType *> *)typesWithTag:(NSString *)tag tagClass:(NSString *)tagClass conformingToType:(nullable UTType *)supertype;

- (BOOL)conformsToType:(UTType *)type;
- (BOOL)isSupertypeOfType:(UTType *)type;
- (BOOL)isSubtypeOfType:(UTType *)type;

@end

FOUNDATION_EXPORT UTType *UTTypeItem;
FOUNDATION_EXPORT UTType *UTTypeContent;
FOUNDATION_EXPORT UTType *UTTypeData;
FOUNDATION_EXPORT UTType *UTTypeDirectory;
FOUNDATION_EXPORT UTType *UTTypeURL;
FOUNDATION_EXPORT UTType *UTTypeFileURL;
FOUNDATION_EXPORT UTType *UTTypeText;
FOUNDATION_EXPORT UTType *UTTypePlainText;
FOUNDATION_EXPORT UTType *UTTypeUTF8PlainText;
FOUNDATION_EXPORT UTType *UTTypeImage;
FOUNDATION_EXPORT UTType *UTTypePDF;

NS_ASSUME_NONNULL_END
