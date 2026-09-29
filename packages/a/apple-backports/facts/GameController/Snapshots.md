# The gamepad snapshots of iOS 7.0 and 9.0

A snapshot saves a game's own values into data and reads them back, so a game can be replayed. The
data is not a private blob: the header describes it, as a packed structure whose first four bytes are
a version and a size, and the fields after them in a stated order. So the port writes the header's
layout and not an approximation of it, and data the port wrote reads back through any of the ten
functions.

## What was measured, and against what

The host's own `GameController` under macOS 27, with no controller connected, is the oracle. The
harness is `tests/backports/host/gamecontroller`: the `snapshot functions` group drives the host's
ten functions and the port's ten over the same inputs and compares the answers line by line. It is
612 lines of that group inside a run of **9188 checks, 0 different**.

The three families of reader do not ask the data the same question, and the harness found all three
rules wrong on the port's first attempt:

| reader | what it takes | measured |
| --- | --- | --- |
| the gamepad's V100 | a whole 36-byte structure, and a version that is not zero | 35 bytes → 0; 36 bytes with version `0x4140` → 1; 36 bytes with version 0 → 0; empty data → 0 |
| the extended and micro readers | a header that declares no size larger than the structure | 63 bytes that declare 999 → 0; 63 that declare 63 → 1; 59 bytes whose declared size is `0x4141` → 0; 59 that declare 59 → 1 |
| all four extended and micro readers | data too short to hold a header | empty data → 1; 4 bytes of junk → 0 (its declared size is `0x4141`) |

The encoders are the header's own rule that data which declares no version and no size gets the
current version and `sizeof` implicitly:

| structure | bytes | first four |
| --- | --- | --- |
| `GCGamepadSnapShotDataV100` | 36 | `0001 2400` — version `0x0100`, size 36 |
| `GCExtendedGamepadSnapShotDataV100` | 60 | `0001 3c00` — version `0x0100`, size 60 |
| `GCExtendedGamepadSnapshotData` | 63 | `0101 3f00` — version `0x0101`, size 63 |
| `GCMicroGamepadSnapshotData` | 20 | `0001 1400` — version `0x0100`, size 20 |

and a structure that already carries a version and a size keeps both: version `0x0200` and size 999
encode as `0002 e703`.

The two version constants are the header's own enumerations, taken at compile time by
`GCSnapshots16.m` from the very enumeration the header names: `GCExtendedGamepadSnapshotDataVersion2`,
which is `0x0101`, and `GCMicroGamepadSnapshotDataVersion1`, which is `0x0100`. Nothing reads them out
of the host at run time, and cannot: the framework is cache-resident here, so a run-time lookup of
them is not a measurement of anything this port does. (An earlier draft of these rows named a run-time
lookup as the source; that was wrong about the mechanism, and the values were right because the header
states them.) There is no
version symbol for the plain gamepad, and the registry carries no row for one: its structure declares
`0x0100` in a comment, which is what this port writes.

## One object per release

The ten functions and the two constants do not share a release, so they are three objects, split by
what the ladder first exports:

- `GCSnapshots7.m` — the plain game's V100 pair and the extended game's V100 pair, both at 7.0;
- `GCSnapshots9.m` — the micro game's V100 pair, whose symbols the ladder first exports at 10.0.1,
  which is why `GCMicroGamepad9.m` is named for 9 and not for 10.0.1;
- `GCSnapshots16.m` — the four current functions and both version constants, first exported at 16.0,
  the rule `GCConstants16.m` already follows.

The shared encoding and decoding are `static inline` in `CharonGCSnapshot.h`, so each object holds
its own copy and no object names a symbol another one defines — which is the failure
`A C function shared between backport files` describes.

## The mutants

`sh tests/backports/host/gamecontroller/mutants.sh` changes one rule at a time and requires the
differential to fail. Five mutants, five noticed, each with the line it was meant to produce:

| mutant | noticed | the difference |
| --- | --- | --- |
| the gamepad reader takes one byte less | yes, 2 lines | 35 bytes: host 0, port 1 |
| the gamepad reader stops reading the version | yes, 20 lines | a 36-byte header of version 0: host 0, port 1 |
| the readers stop reading the declared size | yes, 20 lines | a 24-byte header: host micro 0, port micro 1 |
| the encoders stop filling an empty version | yes, 5 lines | `00012400` against `00002400` |
| the encoders stop filling an empty size | yes, 5 lines | `00012400` against `00010000` |

## What is not here, and why

The three snapshot classes and the three `-saveSnapshot` methods that make them are **not** in this
series and carry no registry row: an object that defines a class a row still lists absent stops the
gate with "listed as absent, but what is built answers it". Their code is kept out of the series, in
the slice's `.agent-work/fin/slice2/GCSnapshotObjects.m`, ready for the round trip that measures
them. The host's own snapshot object cannot be driven on this machine:
`-[GCGamepadSnapshot setSnapshotData:]` reaches `-[GCControllerAxisInput _setValue:queue:]` through
`-[GCPhysicalInputProfile(Legacy) setDpad:x:y:]` and raises `NSInvalidArgumentException`, and the
same path then segfaults, so a host differential over the objects is not available. The port's own
round trip — save, encode, rebuild from the data, the same values — is the measurement that family
needs, and it is the next slice.

The touchpad's own members are not here for the same kind of reason: the host answers
`[[GCControllerTouchpad alloc] init]` with nil and offers no `+initWithTouchSurfaceHandler:`, so with
no controller connected it has no touchpad for a differential to reach. `GCKeyboard` answers for
`keyboardInput` that it does not implement the member at all on macOS.
