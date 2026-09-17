#import <Foundation/Foundation.h>

BOOL charon_property_list_write(id value, NSURL *url, NSError **error);
id charon_property_list_read(NSURL *url, Class wanted, NSString *kind, NSError **error);

BOOL charon_property_list_write(id value, NSURL *url, NSError **error)
{
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data)
        return NO;
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

id charon_property_list_read(NSURL *url, Class wanted, NSString *kind, NSError **error)
{
    if (!url)
        return nil;
    NSData *data = [[NSData alloc] initWithContentsOfURL:url options:0 error:error];
    if (!data)
        return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error];
    if ([value isKindOfClass:wanted])
        return value;
    if (error)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                                 userInfo:@{NSDebugDescriptionErrorKey: [NSString stringWithFormat:@"%@ did not contain a top-level %@ value", url, kind]}];
    return nil;
}
