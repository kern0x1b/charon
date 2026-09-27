#import <UIKit/UIKit.h>
#import <MessageUI/MessageUI.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "../CharonSayOnce.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// What the release's own compose controller can carry, read off its own metadata rather than
// assumed: iOS 7 is where -addAttachmentData:typeIdentifier:filename: and the subject field arrived,
// so a controller that has neither has nowhere to put either. Both questions below are answered from
// that, so the answers follow the release rather than this file.

static BOOL charon_release_sends_attachments(void)
{
    return [MFMessageComposeViewController instancesRespondToSelector:@selector(addAttachmentData:typeIdentifier:filename:)];
}

static BOOL charon_release_sends_subject(void)
{
    return [MFMessageComposeViewController instancesRespondToSelector:@selector(setSubject:)];
}

// A type the release's own store knows: UTTypeConformsTo answers for an identifier it holds a record
// for, and is public from iOS 3 to 14.
static BOOL charon_release_knows_type(NSString *uti)
{
    return uti.length ? UTTypeConformsTo((__bridge CFStringRef)uti, CFSTR("public.data")) : NO;
}

static NSMutableDictionary *CharonAttachmentsOf(MFMessageComposeViewController *controller)
{
    return objc_getAssociatedObject(controller, @selector(attachments));
}

// The two properties are declared again here, widened where the header has them readonly, because
// @dynamic in a category needs a declaration of its own to answer to; the accessors below are the
// ones the release's class and this category share.
@interface MFMessageComposeViewController (Charon7)
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *attachments;
@property (nonatomic, copy, nullable) NSString *subject;
@end

@implementation MFMessageComposeViewController (Charon7)

@dynamic attachments, subject;

+ (BOOL)canSendSubject
{
    return charon_release_sends_subject();
}

+ (BOOL)canSendAttachments
{
    return charon_release_sends_attachments();
}

+ (BOOL)isSupportedAttachmentUTI:(NSString *)uti
{
    return charon_release_sends_attachments() && charon_release_knows_type(uti);
}

// The composer this release has has no attachment row, so an attachment is never added and the array
// below stays empty. The answers are the header's own - NO - reached through +canSendAttachments,
// not a constant and not a fabricated YES.
- (BOOL)addAttachmentURL:(NSURL *)attachmentURL withAlternateFilename:(NSString *)alternateFilename
{
    if (![self.class canSendAttachments] || !attachmentURL)
        return NO;
    NSMutableDictionary *attachments = CharonAttachmentsOf(self);
    if (!attachments) {
        attachments = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, @selector(attachments), attachments, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    attachments[alternateFilename.length ? alternateFilename : attachmentURL.lastPathComponent] = attachmentURL;
    return YES;
}

- (BOOL)addAttachmentData:(NSData *)attachmentData typeIdentifier:(NSString *)uti filename:(NSString *)filename
{
    if (![self.class canSendAttachments] || !attachmentData || ![self.class isSupportedAttachmentUTI:uti])
        return NO;
    NSMutableDictionary *attachments = CharonAttachmentsOf(self);
    if (!attachments) {
        attachments = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, @selector(attachments), attachments, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    attachments[filename.length ? filename : uti] = attachmentData;
    return YES;
}

- (NSArray<NSDictionary *> *)attachments
{
    NSMutableArray *attachments = [NSMutableArray array];
    [CharonAttachmentsOf(self) enumerateKeysAndObjectsUsingBlock:^(NSString *name, id value, BOOL *stop) {
        NSURL *url = [value isKindOfClass:[NSURL class]] ? value : nil;
        [attachments addObject:@{MFMessageComposeViewControllerAttachmentURL: url ?: name,
                                 MFMessageComposeViewControllerAttachmentAlternateFilename: name}];
    }];
    return [attachments copy];
}

- (void)disableUserAttachments
{
    charon_say_once_for(@"MFMessageComposeViewController.disableUserAttachments",
                        @"CharonMessageUI: this release's compose controller has no attachment row to disable - "
                        @"+canSendAttachments answers NO, so the camera and photo affordances it would hide are not there.");
}

- (NSString *)subject
{
    return objc_getAssociatedObject(self, @selector(subject));
}

- (void)setSubject:(NSString *)subject
{
    objc_setAssociatedObject(self, @selector(subject), subject, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (![self.class canSendSubject])
        charon_say_once_for(@"MFMessageComposeViewController.subject",
                            @"CharonMessageUI: this release's compose controller has no subject field, so the value is "
                            @"kept and read back but never shown to the sender.");
}

// The verification-code sheet arrived with iOS 17, and it is the system that recognises the code in
// what the user typed. There is nothing here that recognises one, so the block is kept and never
// called: the completion says whether a code was sent, and calling it with either answer would tell
// the application that something happened which did not.
- (void)setUPIVerificationCodeSendCompletion:(void (^)(BOOL didSend))completion
{
    objc_setAssociatedObject(self, @selector(setUPIVerificationCodeSendCompletion:), [completion copy],
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (completion)
        charon_say_once_for(@"MFMessageComposeViewController.setUPIVerificationCodeSendCompletion:",
                            @"CharonMessageUI: the verification-code completion is kept and never called - this release's "
                            @"Messages has no one-time-code detection, so there is no code for it to send.");
}

// The composer this release has has no row a collaboration attachment could go into: the document
// interaction came later, and the release has no such view to insert one into.
- (BOOL)insertCollaborationItemProvider:(NSItemProvider *)itemProvider
{
    charon_say_once_for(@"MFMessageComposeViewController.insertCollaborationItemProvider:",
                        @"CharonMessageUI: this release's compose controller has no collaboration row, so the item provider "
                        @"is not inserted and the call answers NO.");
    return NO;
}

@end
