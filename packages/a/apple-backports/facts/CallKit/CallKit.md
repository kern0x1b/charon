# CallKit of iOS 10 and 11

CallKit came in iOS 10.0: an application that places and takes calls of its own reports them to the system through a `CXProvider`, asks the system to change
them through a `CXCallController`, and watches every call of the device through a `CXCallObserver`. iOS 11.0 added `includesCallsInRecents` to the
configuration and the two shorthand requests of the call controller. The release keeps no call of its own: the truth about which calls exist lives in
`callservicesd`, and each of the three classes is a client of it.

Source: the CallKit of the host, read under Mac Catalyst by `tests/backports/host/callkit/run.sh` - the four error domains as data, the defaults of
`CXProviderConfiguration`, the deadline of an action, the completeness of a transaction, the keys a `CXStartCallAction` archives under, the equality of a
handle and what a copy of an action and of a transaction is - and SDK 16.4's headers for the surface. What the host will not answer is written down under
*What is not carried*.

## What iOS 6 has instead

Nothing. `callservicesd` arrived with CallKit, and iOS 6 runs no daemon that holds the calls of the device, publishes them to an application, or takes a
transaction from one. There is also no way to write one that another application would find: the port installs libraries into processes, not services into
the system.

So the broker is per process. `CharonCallBroker` is the one place in an application that knows which calls exist, and the provider, the call controller and
the call observer of that application meet there. An application sees its own calls and no others, which is what a single application using CallKit for its
own VoIP calls - the case the ports have - sees anyway. Two applications do not see each other's calls, and that is the one place the port cannot follow the
release. The cellular calls of the release are the one thing that does cross the boundary, and they come in through `CTCallCenter`.

## What the port does

- The four error domains are the release's own strings, to the character: `com.apple.CallKit.error`, `com.apple.CallKit.error.incomingcall`,
  `com.apple.CallKit.error.requesttransaction` and `com.apple.CallKit.error.calldirectorymanager`. An error of the port carries the domain and the code and
  no user info, as the release's do, so `-localizedDescription` falls back to Foundation's wording for an unknown domain.
- A new `CXProviderConfiguration` allows 2 call groups of 5 calls each, supports no video, includes its calls in recents, and supports no handle type; its
  `ringtoneSound` and `iconTemplateImageData` are nil. Those are the release's defaults, read off the host. `-initWithLocalizedName:` is the iOS 10
  initializer and keeps the name; `-init` is the iOS 14 one and leaves it nil. A provider's `configuration` is a copy both when it is set and when it is
  read, so an application cannot change a running provider's configuration behind its back.
- A `CXAction` carries its deadline from the moment it is made, before any provider has seen it, and how long it is belongs to the class: ten minutes for
  `CXStartCallAction`, one minute for `CXAnswerCallAction`, and five seconds for `CXAction` itself and for ending, holding, muting, grouping and playing
  DTMF. Those three numbers are the release's, read off the host. Fulfilling or failing an action no provider holds does nothing and leaves `isComplete` NO -
  the release leaves it incomplete too, because fulfilling is a message to whatever is performing the action and there is nobody to send it to.
- A `CXTransaction` is complete when every action of it is, so a transaction with no actions is complete from the start, as the release's is. A copy of a
  transaction is a new transaction whose actions are copies; a copy of an action is a new action of the same class with the same UUID.
- A `CXHandle` is equal to another of the same type and value, hashes with it, and copies to an equal object that is not the same one. It archives with
  secure coding and comes back equal.
- An action archives under the release's key names - `UUID`, `callUUID`, `handle`, `contactIdentifier`, `isVideo`, `onHold`, `muted`,
  `callUUIDToGroupWith`, `digits`, `type` - and its completeness under `complete`, where the release writes a `state` of its own whose values this band has
  no reading of. An archive of the port is read only by the port.
- `-[CXProvider setDelegate:queue:]` takes the main queue when it is given none, and the delegate is told `providerDidBegin:` on the next turn of that
  queue, so setting the delegate returns first. Every message to a delegate and every completion block runs on that queue.
- `-reportNewIncomingCallWithUUID:update:completion:` makes the call, hands it to the broker and calls the completion with nil; a UUID a call already has
  fails with `CXErrorCodeIncomingCallErrorCallUUIDAlreadyExists`, and an invalidated provider or a missing UUID with
  `CXErrorCodeIncomingCallErrorUnknown`. `-reportCallWithUUID:updated:` merges the update over the one the call has, so a field left nil keeps what the call
  already carried. `-reportOutgoingCallWithUUID:connectedAtDate:` is what makes an outgoing call connected; `-reportCallWithUUID:endedAtDate:reason:` ends
  it.
- `-[CXCallController requestTransaction:completion:]` refuses a transaction before any provider sees it, in this order: a transaction with no actions is
  `EmptyTransaction`, a process with no provider is `UnknownCallProvider`, an action that is not a call action is `InvalidAction`, a start action for a
  call UUID that is already there is `CallUUIDAlreadyExists`, a start action past the configuration's `maximumCallGroups` is `MaximumCallGroupsReached`, and
  any other call action for a UUID no call has is `UnknownCallUUID`. The completion says whether the transaction was taken, not whether its actions were
  performed: an action taken and then failed reaches the delegate of the provider, and the completion has already run with no error.
- A transaction the controller takes reaches the delegate whole through `provider:executeTransaction:` when the delegate answers YES to it, and action by
  action through the `perform…Action:` methods when it does not. An action whose `perform…` method the delegate does not answer fails at once, rather than
  leaving a call waiting on something nothing will perform. An action still incomplete at its own deadline times out: it finishes as failed and the delegate is
  told `provider:timedOutPerformingAction:`. Each action of a transaction runs out on its own clock, so a transaction that starts a call and mutes it has
  ten minutes for the one and five seconds for the other.
- A fulfilled action is what changes the call. A start action records when the call started connecting, an answer action connects it, an end action ends it
  and takes it out of the broker, and the held, muted and group actions set those. A failed start or answer action ends the call as
  `CXCallEndedReasonFailed`, since the call only exists because the action was asked for and there is nothing for it to be; a failed end, hold, mute or
  group action leaves the call as it was.
- `-[CXProvider invalidate]` fails every action of every transaction it has not finished, ends every call it holds as `CXCallEndedReasonFailed`, drops the
  provider out of the broker and tells the delegate `providerDidReset:`.
- A `CXCallObserver` answers the calls of the broker and tells its delegate, on the queue it was given or the main queue, whenever one appears, changes or
  ends. What the delegate is handed is a snapshot taken while the broker held its lock, so the call does not change under it. A `CXCall` is equal to another
  with the same UUID and hashes with it.
- The observer reports the calls of the device and not only the application's, which on iOS 6 means the cellular ones. `CTCallCenter` is there from iPhone
  OS 4 and is the whole of what a third party may see of them - an identifier and one of four states - and it is what the port watches. Making the first
  `CXCallObserver` of the process is what starts the watch, so an application that never asks for one never loads the call centre. A call CoreTelephony
  first shows as `CTCallStateDialing` is outgoing and one it first shows as `CTCallStateIncoming` is incoming; `CTCallStateConnected` connects it and
  `CTCallStateDisconnected` ends it as `CXCallEndedReasonRemoteEnded`. A cellular call gets a UUID of the port's making, kept for as long as the call
  lasts, since CoreTelephony's identifier is a string and CallKit's is a UUID.
- A cellular call belongs to no provider of this process, and an action the call controller is asked for against one is refused as
  `CXErrorCodeRequestTransactionErrorUnknownCallProvider` - which is what is true - rather than handed to a delegate that never made that call. The same
  refusal covers a call of another provider in the same process.
- CallKit does not configure an application's audio, and neither does the port: the application sets its own category and mode while it performs the
  action, and what the system does is activate the session and say so. A call of a provider connecting activates the shared `AVAudioSession` and the
  delegate is told `provider:didActivateAudioSession:`; the provider's last connected call going away deactivates it, with
  `AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation`, and the delegate is told `provider:didDeactivateAudioSession:`. iOS 6 has the category, the
  mode and `-setActive:withOptions:error:` the contract needs. A cellular call is none of the application's audio and moves nothing.

## What is not carried

The call directory - `CXCallDirectoryManager`, `CXCallDirectoryProvider`, `CXCallDirectoryExtensionContext` and its delegate - is absent: it is an
application extension, and iOS 6 loads no extensions. `+[CXProvider reportNewIncomingVoIPPushPayload:completion:]` is absent: it arrived in iOS 14.5 and
reports a call out of a PushKit payload this release has no push of. `CXErrorDomainNotificationServiceExtension` is absent for the same reason.

What the release does with a cellular call beyond the four states is out of reach: `CTCallCenter` gives no direction for a connected call, no hold state and
no handle, so a cellular call of the port has `onHold` NO and an update of nothing. CoreTelephony of iOS 6 does export `CTCallDial`, `CTCallAnswer`,
`CTCallHold` and `CTCallDisconnect`, so acting on a cellular call is reachable in principle; whether CommCenter lets an unentitled process do it is
untested, and until it is tested the port refuses rather than pretends.

Two behaviours the host would not answer, because a tool without the VoIP entitlement never gets past CallKit's own entitlement check (every request came
back `CXErrorCodeRequestTransactionErrorUnentitled`, code 1, and no delegate method was ever called): the order in which a transaction is refused, and
whether `providerDidBegin:` and `providerDidReset:` arrive and when. The order above is the order the header's enumeration lists the failures in and the
order the port checks them in; it is reasoned, not read, and the entry says so. `CXErrorCodeUnentitled` and the rest of `CXErrorCode` are cases of an
enumeration the compiler writes into the application, so the package carries nothing of them; the port never answers `Unentitled`, since there is no
entitlement to hold an application to.

The port's `-description` is its own. The release's carries the ivars of a CallKit far newer than iOS 10 - `state`, `commitDate`, `handles`, a dozen flags
the iOS 10 header has no property for - and there is nothing to be gained from following a text no application reads.

## The system call screen

The screen an incoming call is shown on belongs to SpringBoard, which no library loaded into an application can draw in, so what the library carries is one
side of a bridge and the screen itself is a tweak's business. The two sides speak in Darwin notifications and a file, because that is what crosses the
boundary on this release: a notification reaches every process whatever its sandbox and carries nothing, and a file carries the call but only where both
sides may reach it - `/var/mobile/Library/Caches/org.charon.callkit`, made by whichever side runs first and writable by everyone, since an application and
SpringBoard are not the same user and share no group.

A provider reporting an incoming call writes the UUID, the caller's name, the handle and its type, whether there is video, the application's bundle
identifier and the configured ringtone, and posts `org.charon.callkit.incoming`. What the person does on the screen comes back as
`org.charon.callkit.answered` or `org.charon.callkit.declined` with the UUID in a file beside it, and the library turns it into an ordinary
`CXAnswerCallAction` or `CXEndCallAction` run through the provider - so the delegate is called exactly as it is when the application answers from its own
interface, and there is one path through the state machine instead of two. The screen is taken down when the call is answered, since from there on it is
the application's own interface, and when the call ends.

Without that tweak none of this is heard: the library writes a file nobody reads and posts a notification nobody hears, and the calls of the application
work exactly as they do with no screen. Nothing on this path can refuse, raise or fail a call.
