# NSUserActivity, iOS 8

Introduced in iOS 8: a description of what the user is doing in an application, so the system can hand it to
another device (Handoff), index it (Spotlight) or offer it to the application again. iOS 9 added the expiry date, the
keywords, the required keys and the eligibility flags.

Source: the host's own Foundation, asked for every answer below and held against the port by the `useractivity` group of
`tests/backports/host/uikit2/run.sh`, which compiles the port with its names changed and puts it beside the system's
class. The shared caches of iOS 6.0 and 7.0 have no activity; the class first appears in the cache of iOS 8.0.

## What the port does as the system does

A new activity has the type it was given, an empty dictionary of user info, `needsSave` on, handoff eligibility on and
everything else off or `nil`. The user info is copied when it is set, `nil` reads back as an empty dictionary, and
`-addUserInfoEntriesFromDictionary:` merges. Setting a value does not change `needsSave`. A web page URL takes `http`
and `https` and raises `NSInvalidArgumentException` for any other scheme, with the system's reason; an activity with no
type raises the system's reason too when the application declares no `NSUserActivityTypes`, and takes the first
declared type when it does. `becomeCurrent` asks the delegate to save, once, after it returns and never at once,
turns `needsSave` off before it does, asks nothing when the activity is current already, and asks again after
`resignCurrent`; `invalidate` leaves the activity usable. `getContinuationStreamsWithCompletionHandler:` answers at
once, with no streams and `NSCocoaErrorDomain` 3328, which is what the system answers for an activity nobody
continues. The delegate is held weakly.

## What it cannot do

iOS 6 has no Handoff, no Spotlight index of activities and no continuation, so an activity is never advertised, indexed
or handed to another device, and the class is `inert`. The delegate messages `userActivityWasContinued:` and
`userActivity:didReceiveInputStream:outputStream:` and the application delegate's continuation messages are never sent.
The system saves a current activity again whenever `needsSave` is set; the port asks once, at `becomeCurrent`.
What later releases added - the referrer URL, prediction eligibility, the persistent
identifier and the content attribute set - is not declared, so `respondsToSelector:` answers no; the registry lists
each that has a decision.
The class does not adopt `NSSecureCoding` or `NSCopying`, which is what the system's does not do either.

`targetContentIdentifier` (iOS 13) is declared and stored as a plain string, as the host's is, and nothing acts on it.
