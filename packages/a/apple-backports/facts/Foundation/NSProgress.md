# NSProgress, iOS 7 to 11

Source: the host's own Foundation, asked for every case below and held against the backport by the
`progress.*` records of `tests/backports/host/foundation2/run.sh`, and Foundation of iOS 6.0 and 6.1.3 on the
emulator, an iPhone 4S and an iPad 2, through `tests/backports/device/foundation2.m`, which compares the
backport's answers with the records the host wrote.

## What iOS 6 already has

`NSProgress` is in the Foundation of iOS 6.0 and 6.1.x, with most of the surface iOS 7 made public: the
progress of the current thread, `progressWithTotalUnitCount:`, `becomeCurrentWithPendingUnitCount:` and
`resignCurrent`, the two counts, `fractionCompleted`, cancelling and pausing with their handlers, the
`userInfo` and the kind. A class that is there is not backported; what the release lacks is carried as
categories, and the eight ways it answers differently are listed at the end.

## What the backport adds

A progress made with `+discreteProgressWithTotalUnitCount:` has no parent and does not take the current
progress for one: `+progressWithTotalUnitCount:` of the release takes it, and this is the way out of that.

`+progressWithTotalUnitCount:parent:pendingUnitCount:` makes the child with its parent and the given part of
the parent's units, so that the parent's fraction moves as the child's does (a parent of 10 units, a child of 4
given 6 of them: 0.3 with two of the four done, 0.6 with all). A nil parent makes a progress like a discrete
one, and a negative part is accepted. The release links a child to its parent only when it is made, by way of
the current progress, so the port makes the parent current for the moment of the call and lets go of it after;
the current progress is what it was before.

`-performAsCurrentWithPendingUnitCount:usingBlock:` makes the progress current with that part, runs the block
and resigns it. A block that raises leaves the progress current, as the newest release does.

`finished` is true when the progress is determinate and its completed count has reached the total. It is
indeterminate when the total is negative, or is zero with nothing completed, so a total of zero with
three units done is finished and one with none is not; a cancelled progress is finished when its counts say so
and not because it was cancelled.

The two handlers of the release are read back by their getters, which answer the block the release keeps, or
nil when none was set or it was cleared. The block is the one the setter copied, and calling it runs the
handler.

`estimatedTimeRemaining`, `throughput`, `fileOperationKind`, `fileURL`, `fileTotalCount` and
`fileCompletedCount` are not stored on their own: each reads and writes its key of the progress's `userInfo`, the
way the newest release keeps them, so `userInfo` shows them and setting one to nil takes its key out. The keys
are the constants of the release, and they are not the same text on every release - iOS 6 spells the throughput
key `NSProgressThroughput` where the newest spells it `NSProgressThroughputKey` - so an application that reads
the dictionary by the constant sees what the property set, and one that writes the literal text of a newer
release does not.

`NSProgressEstimatedTimeRemainingKey`, `NSProgressFileOperationKindReceiving` and
`NSProgressFileOperationKindUploading` are the strings of the same names, as in the newest release.

## What the release cannot do

An existing progress cannot be attached to a parent afterwards: the release links a child when it is created
and keeps no list of children on the parent, and the link cannot be written into the object from outside -
setting the two fields that hold it left the parent's fraction where it was. `-addChild:withPendingUnitCount:` is
absent for that reason, and the class method above is the way to make a child with its parent.

The release can pause a progress and has no way back, so `-resume` and `resumingHandler` are absent.

`localizedAdditionalDescription` is absent: the newest release composes it from the counts, the throughput, the
time remaining and the file counts in several localized forms, and a rule read off a handful of cases would be
a guess.

## Where iOS 6 answers differently

These are methods of the release itself, which the port does not replace:

- `localizedDescription` is empty; the newest release says `25% completed`, or `Downloading 3 files…` for a file
  kind.
- `fractionCompleted` of a progress whose total is zero is not-a-number, and 0 in the newest release.
- `isIndeterminate` of a new progress is false, and true in the newest release.
- A cancellation handler set on a progress that is already cancelled is not called; the newest release calls
  it at once.
- `initWithParent:userInfo:` takes a parent that is not the current progress, where the newest release raises
  `NSInvalidArgumentException`.
- `resignCurrent` leaves the pending units a progress took uncounted when no child was made from them; the newest
  release counts them as completed, so a parent made current with 6 of 10 units and resigned with no child is 0.6
  done there and 0 here.
- A parent's `completedUnitCount` does not count a finished child's units; its fraction does.
- The keys of the file and throughput constants are spelled without `Key`, as above.
