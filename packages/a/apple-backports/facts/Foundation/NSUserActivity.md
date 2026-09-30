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
`eligibleForPrediction` (iOS 12) is carried the same way `eligibleForHandoff` and `eligibleForPublicIndexing` already
were: a plain stored `BOOL`, nothing acting on it. It starts off, unlike handoff: the host answers no for a new
activity, and an application opts in by setting it. Predictions rest on
a system daemon iOS 6 does not run either, exactly as Handoff and the Spotlight index do, and that reasoning did not
stop those two from being honest storage; it does not stop this one. Held against the host's real `NSUserActivity` by
`tests/backports/host/uikit2/useractivity_test.m`.

What later releases added - the referrer URL, the persistent identifier and the content attribute set - is not
declared, so `respondsToSelector:` answers no; the registry lists each that has a decision.
The class does not adopt `NSSecureCoding` or `NSCopying`, which is what the system's does not do either.

`targetContentIdentifier` (iOS 13) is declared and stored as a plain string, as the host's is, and nothing acts on it.

## What the delete class method answers here, and the three rows this family still owes

`+deleteSavedUserActivitiesWithPersistentIdentifiers:completionHandler:` is the 12.0 method, and its
signature and handler are read from the SDK's own `NSUserActivity.h:108`. What it would delete from is
the system's store of saved activities, and this package keeps none: `NSUserActivity` is the port's own
class, its state lives in the object, and nothing it writes survives the process. So the port answers
the contract - call the handler - and says in the log on every call that there was no store, which is the
difference between an answer and a caller left guessing (`NSUserActivity.m:245` for the sibling, `:253` for this one).

Three rows in this family are not answered by code, each for a measured reason:

- `-[NSUserActivityDelegate userActivityWasContinued:]` and
  `-[NSUserActivityDelegate userActivity:didReceiveInputStream:outputStream:]` (both 8.0, the
  `maximum` these rows already carry). Both are declared in the SDK's `NSUserActivity.h` (line 129 and
  :133) and both are *called by the system's continuation*, which is Handoff: 6.1.3 and 4.3 have no
  `continueUserActivity:` to call from and no other device to continue to, so nothing in a program the
  port serves reaches either selector. They are declarations plus a log line for the case where
  something does - which needs a host case that links the port's declaration beside a conforming object
  (the host has neither selector, so the read is sound), not yet written.
- `-[NSFilePresenter accommodatePresentedItemEvictionWithCompletionHandler:]` (17.4). **The port cannot
  implement this one, and the reason is in the SDK:** the 16.4 `NSFilePresenter.h` has no
  `@interface NSFilePresenter` at all - the class is macOS's and its members are marked
  `API_UNAVAILABLE(ios, watchos, tvos)` - and the 26.2 SDK has the 17.4 method as a **Mac Catalyst**
  API, which is what this row's own `source` says. So it is a macOS surface, not one of the iOS
  releases the port carries: there is no release class to extend and nothing on a device to answer it.
  It wants the owner's decision (a Catalyst port, or the row recorded as a macOS-only surface) before
  any code is written.
- `NSPredicateValidating` and `-[NSPredicate allowEvaluationWithValidator:error:]` (both 26.4). Their
  declarations are on **neither** SDK on this machine: absent from the 16.4 (the build SDK, so the port
  would need a Charon header) and absent from the 26.2 tree under `.agent-work/sdk-26.2`, and this
  row's own `source` names SDK 26.5. Without the declaration the validator's required selector and the
  method's return are unreadable, and writing them from the name would be a guess about a contract.
  They owe one SDK newer than 26.2.

## The two continuation members, and how "nothing calls it" was measured

`-[NSUserActivityDelegate userActivityWasContinued:]` and
`-[NSUserActivityDelegate userActivity:didReceiveInputStream:outputStream:]` (both 8.0) are declared by
the SDK the port's programs are compiled against (`NSUserActivity.h:129` and `:133`) and belong to a
protocol an application's own delegate adopts. The caller is the system's **continuation** - Handoff
handing this device an activity another device sent - and the releases this package carries have none:
there is no `continueUserActivity:` to call from and no second device to continue to.

So they are `ignored`, and the claim that status rests on is a claim about this package's own sources,
which is checkable. `tools/called-sites.py` reads every `.m`, `.c` and `.h` in the package, and reports
each kind separately so a declaration cannot pass for a call:

```
$ python3 tools/called-sites.py "userActivityWasContinued:"
userActivityWasContinued:: 0 message send(s), 0 C call(s), 0 other mention(s), in 1878 source file(s)
$ python3 tools/called-sites.py "userActivity:didReceiveInputStream:outputStream:"
userActivity:didReceiveInputStream:outputStream:: 0 message send(s), 0 C call(s), 0 other mention(s), in 1878 source file(s)
```

The strong form is what those numbers give: the selector does not appear **at all**, so nothing in the
package can call it. The search's own control is a selector the port does name and call -
`os_log_type_enabled` comes back `0 message send(s), 1 C call(s), 6 other mention(s)` - and a root with
no sources is refused (`no source under …: nothing was searched, so nothing is claimed`, exit 1).

A message send split over several lines is counted as a mention, not a send, so the send figure is a
lower bound and the mention figure an upper one; for these two rows both are zero, which is the only
form of the claim that is needed.

**Both rows are `absent`**, which is the tree's word for "not there at all, so `respondsToSelector:`
answers honestly": the port declares neither protocol and has no caller, so there is no implementation
of ours and none of the release's on the bands these rows are in. An earlier commit in this series had
them as `ignored`, which the review was right to refuse: `ignored` means the call reaches the
*release's own* implementation, and on these bands there is not one.
