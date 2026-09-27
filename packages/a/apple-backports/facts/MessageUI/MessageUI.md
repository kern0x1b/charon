# MessageUI on the release's own compose controllers

Everything here is a question asked of the release and answered from it. The release's own
`MFMessageComposeViewController` and `MFMailComposeViewController`, read out of the armv7 6.1.3
cache's ObjC metadata with `objc.binary_inventory`, are:

    MFMessageComposeViewController
      -body  -setBody:  -recipients  -setRecipients:  -messageComposeDelegate
      -setMessageComposeDelegate:  -smsComposeControllerSendStarted:  -smsComposeControllerCancelled:
      +canSendText  +initialize  +-_canSendText  +-_serviceAvailabilityChanged:  +-_setupAccountMonitor
      +-_startListeningForAvailabilityNotifications  +-_updateServiceAvailability
    MFMailComposeViewController
      +canSendMail  +maximumAttachmentSize
      -setSubject:  -setToRecipients:  -setCcRecipients:  -setBccRecipients:  -setMessageBody:isHTML:
      -addAttachmentData:mimeType:fileName:  -mailComposeDelegate  -setMailComposeDelegate:
      -_validEmailAddressesFromArray:  -_addAttachmentData:mimeType:fileName:
      -autosaveWithHandler:  -hasAutosavedMessageWithIdentifier:  -removeAutosavedMessageWithIdentifier:
      -recoverAutosavedMessageWithIdentifier:  -requestFramesForAttachmentsWithIdentifiers:resultHandler:
      -finalizeCompositionValues  -initWithNibName:bundle:  -initWithURL:

That is the whole of the difference between the two composers on this release, and it is what the
three class methods are asked about rather than a table written here:

- `+canSendSubject` is YES exactly when the release's controller has `-setSubject:`. It does not, so
  the answer is NO - which is also the truth about iOS 6, whose SMS composer has no subject field.
- `+canSendAttachments` is YES exactly when it has `-addAttachmentData:typeIdentifier:filename:`. It
  does not, so NO - also the truth: iOS 6's Messages sends a text message and has no path to send an
  attachment with.
- `+isSupportedAttachmentUTI:` is the first of those *and* a check that the release's own
  MobileCoreServices store knows the identifier, through `UTTypeConformsTo` against `public.data`
  (public from iOS 3 to 14). On this release the first half is already NO, so the answer is NO; on a
  release whose composer can take attachments the second half is a real lookup in that release's own
  type store, not a list in this file.

The two add methods record what they were given when the composer can take it and answer NO when it
cannot, which is the header's own answer for an attachment that will not go in. `-attachments` then
reports the controller's real contents, so on this release it is empty because nothing can be put in
it - a report about the controller, not a placeholder.

**The two keys of the array are the release's own constants, and this release has neither.**
`MFMessageComposeViewControllerAttachmentURL` and
`MFMessageComposeViewControllerAttachmentAlternateFilename` are absent from the armv7 6.1.3 cache's
symbol table - measured with `dump-cache.lua` over the whole cache, where both names do not appear at
all - so an array the port built would carry keys of its own making and an application reading
`MFMessageComposeViewControllerAttachmentURL` out of it would get nil. The gate's first run of this
delivery caught the reference at link time ("Undefined symbols ... `_CGRectGetWidth`, `_CGRectZero`"
and, had it got that far, these two). So both keys are asked of the release at run time through
`dlsym`, an attachment is not recorded unless the release really has both, and `-attachments` builds
its dictionaries with the release's own strings. On this release the answer is an empty array for two
independent reasons - the composer cannot take an attachment, and the keys do not exist - and both are
true.

## The three that cannot do their work here

- `-disableUserAttachments` hides affordances the release's sheet does not have, and
  `subject` names a field it does not have. Both are `inert`, both say so once in the log.
- `-setUPIVerificationCodeSendCompletion:` is the one-time-code sheet of iOS 17. The block reports
  whether a code the user pasted was sent, and the system is what recognises the code. There is
  nothing here that recognises one, so the block is copied, kept and never called. Calling it with
  either answer would tell the application that something happened which did not.

## The two collaboration factories

`-[MFMessageComposeViewController insertCollaborationItemProvider:]` answers NO and
`-[MFMailComposeViewController insertCollaborationItemProvider:completionHandler:]` calls its
completion with NO: the document interaction that draws a collaboration row came later, and neither
composer of this release has a view to insert one into. `NSItemProvider` itself is real - the port
carries it (`registry/Foundation/base.json`, `facts/Foundation/NSItemProvider.md`) - so the argument
is a real object; there is simply nowhere to put it.

## The one row of this framework that is not here

`MFMessageComposeViewController.message` is not implemented by this delivery. Its contract is a round
trip: setting it copies an `MSMessage`'s recipients, subject, body, attachments and URL into the
composer's own fields, and reading it builds an `MSMessage` back out of what the user has typed.
`MSMessage` is a class of the **Messages** framework and the port does not carry it yet
(`coordination/corpus/ledger/Messages.tsv`: `MSMessage` and its 19 sibling rows are all `missing`),
so there is no message to copy from or build. Writing a property that stores the value without
applying it is exactly the silent fake `COORDINATION.md` §2 forbids, so the row stays open and comes
back with the Messages framework that owns the class.

## Not measured against a host

Neither compose controller exists on the host, so there is no differential for this framework; both
are iOS-only classes with no macOS counterpart under Mac Catalyst. The measurement here is the
release's own metadata, quoted above.
