# The whole-cache rung: 6.1.3 read in one pass, 11378 classes and 1171 protocols

Every other page in this folder decides its rows from the MediaPlayer image alone
(`tools/mach32_methods.py` over the image at `0x31fe3000`, 236 classes, 41 categories). That is the right
rung for a member of a MediaPlayer class and it is not enough for two things in this family: a member of a
class MediaPlayer does not own, and a **protocol** — a protocol's absence is a fact about the whole release,
not about one image. This page is the rung that decides those, and it was run once, through
`coordination/heavy.sh`, at a load of 9.08.

```
CHARON_ROOT=<worktree> xmake l tools/corpus/objc-inventory.lua \
  ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7 > inventory-6.1.3.tsv
12549 lines: 11378 classes, 1171 protocols
```

The reader's controls, from the same file: a class no framework has reads absent, and `MPVolumeView` and
`MPNowPlayingInfoCenter` read present.

## What it settles that the per-image read could not

**`AVPlayerItem.nowPlayingInfo` (16.0)** — the member of an AVFoundation class, which is why this row
waited two turns for it. In the whole cache, `AVPlayerItem` lives in `AVFoundation.framework/AVFoundation`
with **237 own instance selectors and 35 own class selectors**:

| selector | in AVPlayerItem's own 237 |
| --- | --- |
| `status` | **yes** |
| `timedMetadata` | **yes** |
| `duration` | **yes** |
| `MPAVItem` | **yes** — the MediaPlayer category's own method |
| `nowPlayingInfo` | **no** |
| `setNowPlayingInfo:` | **no** |

One class, one reader, a YES and a NO: that is the control that makes the NO mean something. And across the
**whole** 6.1.3 cache exactly **two** classes declare `nowPlayingInfo` in their own instance list —
`MPNowPlayingInfoCenter` (MediaPlayer) and `MRMediaRemoteState` (`PrivateFrameworks/MediaRemote`, a private
framework no application links). Neither is `AVPlayerItem`.

The release's whole-cache **selector list** could not have decided this, and this is the second time that
rung has had to be passed over in this family: `nowPlayingInfo` is on **one** of its 113981 distinct names,
because some class somewhere declares it. The per-cache list is a list of names, not of owners.

**Twenty class and protocol rows, absent from the whole release** — not merely from MediaPlayer's image,
which is the stronger claim and needs this rung for a protocol:

`MPAdTimeRange`, `MPContentItem`, `MPNowPlayingSession`, `MPNowPlayingSessionDelegate`,
`MPPlayableContentManager`, `MPPlayableContentManagerContext`, `MPPlayableContentDataSource`,
`MPPlayableContentDelegate`, `MPSystemMusicPlayerController`, `MPMusicPlayerQueueDescriptor`,
`MPMusicPlayerMediaItemQueueDescriptor`, `MPMusicPlayerStoreQueueDescriptor`, `MPMusicPlayerPlayParameters`,
`MPMusicPlayerPlayParametersQueueDescriptor`, `MPMusicPlayerControllerQueue`,
`MPMusicPlayerControllerMutableQueue`, `MPMusicPlayerApplicationController`, `MPMediaPlaylistCreationMetadata`,
`MPNowPlayingInfoLanguageOption`, `MPNowPlayingInfoLanguageOptionGroup`.

The twenty is the number of NAMES in that list, and the page that lists them is the only place it appears: eleven
classes and four protocols plus five more classes, all read one at a time against the 12549 lines above. A
first draft of this line said sixteen, which is the number of *rows* in the queue those twenty names come
from once the two `MPMusicPlayerControllerQueue` spellings are counted once — a count nobody could recompute,
in a page whose subject is a reader whose whole value is that its numbers can be.

**Every one is new code that cannot shadow anything**, which is what `implemented` over `absent` needs: the
release has no object of that name, so a port class with that name collides with nothing. The 1171 protocol
rows in the file are what make that true for the four protocol rows — a protocol is not a class, its absence
is not visible to a per-image classlist read, and `MPPlayableContentDataSource` and `MPPlayableContentDelegate`
are rows in this family.

## One correction this rung caught in my own earlier reading

The inventory's selector columns are **sign-prefixed** — `-nowPlayingInfo`, `+sharedCommandCenter` — not
bare names. A first pass tested membership of the bare name and reported `status`, `externalMetadata` and
`timedMetadata` as absent from `AVPlayerItem` too, which is impossible and was the sign of a broken test
rather than a surprising cache. Stripping the sign gives the table above. A reader that answers NO to
everything would have passed the `nowPlayingInfo` check while being wrong about `status`, and the two
together are what caught it.

## What it does not settle, and the rung that does

- **A member of a MediaPlayer class.** The per-image read is better: it resolves each of the 41 categories'
  **own** class pointer, which is the clobber question a whole-cache merge cannot answer.
- **The value of a named key.** Neither rung reads the value of `MPMediaPlaylistPropertySeedItems`, and the
  port's own keys prove a value cannot be spelled from a name
  (`facts/MediaPlayer/MediaPlayerConstants.md:8-12`). That needs `tools/cfconst.py` against the release that
  first exports the name — a host differential, which is why `MPMediaPlaylist.seedItems` is still on the
  corpus's blanket reason rather than on this page.
- **Whether a release that gates a library gates it.** `MPMediaLibrary93.m` is measured per-image and says
  so; no cache read can say what a 7.0 device would answer.