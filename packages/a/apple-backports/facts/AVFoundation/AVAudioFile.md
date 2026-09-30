# AVAudioFile

The first owner the bulk generator named, and the first one where the rule has to decide two different
answers inside a single class.

**The rule, written once for this owner, applied to every row:**

> A row is **CARRIED** when it is data the port can hold or compute from what the caller gave it — a
> URL, a format, a length, a frame position, a buffer the caller handed over. A row is **INERT AS APPLE
> DOCUMENTS** when the only honest answer comes from something this device lacks — a real decoder or
> encoder for a compressed format, or the media-library service behind one. Nothing here reaches a
> capture device, a route or a key server.

## Where the generator put it

`tools/corpus/generate-ledger-objects.py` over the AVFAudio ledger, demand-ordered, with `_NSFileSize`
planted as a control and a nonsense symbol in none of the fifteen held caches:

    AVAudioFile ledger rows: 16, of which code/code+lift: 16, demanded: 4
    demand#136  class     AVAudioFile                             introduced=8.0  rung=8.0
    demand#377  method    -[AVAudioFile initForReading:error:]                    rung=NONE-OF-THE-15
    demand#378  method    -[AVAudioFile readIntoBuffer:error:]                    rung=NONE-OF-THE-15
    demand#446  property  AVAudioFile.processingFormat                            rung=NONE-OF-THE-15

The class is carried from the **8.0** rung and every member arrived at or after it, so the two files
are the shape the criteria use: `AVAudioFile8.m` **defines the class** (4.3 and 6.1.3 do not export it,
so a category alone would leave `check_registry` counting the row unbuilt and stop the band build),
and `AVAudioFile8Members.m` is a **category** for the members, which a band's staging never drops.
`CharonAVAudioFileStorage.h` holds the storage because two files must see it and a class extension in
one of them is invisible to the other.

## The two halves, and where the line is

**CARRIED — the URL-backed data is real.** `-initForReading:error:` opens the URL the caller named,
reads the bytes at it, and recognises a plain RIFF/WAVE container by walking its chunks to `fmt `.
That is not a decoder and claims nothing about a compressed format — which is the point: a file it can
recognise it can serve, and a file it cannot recognise is refused rather than guessed at. For such a
file `url`, `length`, `processingFormat`, `fileFormat` and `framePosition` are the values the port
computed from the bytes, and `isOpen` is real.

**INERT AS APPLE DOCUMENTS — anything needing a decoder.** A file that is not plain WAVE returns nil
with `NSFileReadUnknownError`, which is what `AVAudioFile` reports for a file it could not be opened
for reading. `-writeFromBuffer:error:` answers `NO` with `NSFileWriteUnknownError` rather than
discarding a buffer silently, because writing needs an encoder and a writable destination and the port
has neither.

## Two signatures the compiler corrected, and it was right

The first version of the two reads returned an `AVAudioPCMBuffer *`. The header says both return
**`BOOL` and fill the caller's buffer**, and the compiler rejected it. It was right: a caller that
passes a buffer expects *that* buffer filled, and returning a different one would leave the caller's
untouched while looking like success. Both now fill the caller's buffer, cap the copy at
`buffer.frameCapacity` and at the frames asked for, and answer `YES`.

The same pass found that the release declares every initialiser `nullable` and that
`-initForReading:commonFormat:interleaved:error:` takes an `AVAudioCommonFormat` **enum**, not a format
pointer. Both are now as the header has them; a category that redeclares a release method with a
different type is a different selector's worth of promise.

## What the differential settles here, and what it cannot

`tests/backports/host/avf-descriptors` is one program linked twice, so `AVAudioFile` joins the same
structural table as the rest of the set: presence, superclass, `alloc`/`init`, and the eleven members
an **instance** answers — `url`, `length`, `framePosition`, `isOpen`, `processingFormat`, `fileFormat`,
the two reads, `-close` and `-writeFromBuffer:error:`. The host answers every one of them too, so that
half is a real comparison.

It cannot settle the **values**: the host's `AVAudioFile` is a class cluster whose `-init` needs a real
file, and this differential has no file to point it at, so the port's `length` and `processingFormat`
have no host counterpart here. Those are `~` rows, held against the port's own unmutated baseline.
