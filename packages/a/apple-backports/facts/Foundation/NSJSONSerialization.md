# NSJSONSerialization, the writing option of iOS 11.0

`NSJSONWritingSortedKeys`, the option that writes a dictionary's keys in order,
arrived in iOS 11.0 with the value `2`.

Source: the ordering read from the host's Foundation, which is the same
implementation the option has had since it arrived; `+dataWithJSONObject:options:error:`
of the arm64 cache of iOS 11.0 (`0x18161acf4`) for the argument checks around it.

## The order

The keys come out in the order of `-localizedStandardCompare:`, not in byte
order: `a`, `á`, `b`, `C` rather than `C`, `a`, `b`, `á`; `item2`, `item9`,
`item10` rather than `item10`, `item2`, `item9`; `ä` before `ae`. Checked
against `-localizedStandardCompare:` on four hundred random sets of keys drawn
from letters of both cases, digits, punctuation, accented Latin, Han and Greek:
no disagreement.

## Why the port does not carry it

The option is a number the compiler writes into the call, and the call goes to
the system's `+dataWithJSONObject:options:error:`, which iOS 6 already has.
There is no selector to add and no call to intercept: the attachment mechanism
adds only what a class does not answer, and replacing a system implementation is
not something the port does. So an application that passes the option on iOS 6
gets its keys in the dictionary's own order and is told nothing. The registry
records this as `ignored`.

Had we a place to stand, the whole implementation would be one comparator.
