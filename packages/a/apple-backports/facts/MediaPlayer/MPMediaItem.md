# MPMediaItem

The properties Apple documents as conveniences over the item's property dictionary. Each row quotes the
26.2 header line it implements, which is also what decides its release group.

## 7.0 — `MPMediaItem70.m`

    @property (nonatomic, readonly) NSUInteger albumTrackNumber MP_API(ios(7.0));
    @property (nonatomic, readonly) NSUInteger discNumber MP_API(ios(7.0));

What 6.1.3 has, measured with `tools/mach32_methods.py` against the 6.1.3 cache (its test carries the
controls; the reader-independent cross-check: the selector strings are present in the cache 26 times,
`dealloc` 433, a nonsense selector 0):

- `albumTrackNumber` — **not declared** by any of the image's 236 classes in their own instance lists,
  and not in any of its 41 categories. Not on `MPMediaItem` (75 own methods), not on `MPMediaEntity`
  (18), not on `MPConcreteMediaItem` (29), the private class a real item's receiver is.
- `discNumber` — the same: nowhere.
- The accessors they are conveniences over **are** present: `valueForProperty:` is an own method of the
  public `MPMediaEntity`, with `valuesForProperties:`, `mediaLibrary`, `representativeItem`,
  `enumerateValuesForProperties:usingBlock:`, `persistentID`, `copyWithZone:`, `isEqual:` and `hash`.

So the registry semantic for both is **the release does not carry it at all** — zero hits in any class
and zero in any category — and both are carried. Adding them as a category on the public class is safe in
both directions: a real item's concrete class implements nothing here, so nothing is clobbered, and a
port-created item answers from its own dictionary.

Contract, in `tests/backports/host/mediaplayeritem/contract.m`: the port's own source compiled against a
stand-in that answers `valueForProperty:`, checking a present key, a missing key (nil, so 0) and the
header's conversion, with a wrong-key and a wrong-conversion mutant each shown red.
<!-- generated: 80 -->

## 80 - `MPMediaItem80.m`

The 15 members the 26.2 header declares `MP_API(ios(80))`, generated from the one list in
`tests/backports/host/mediaplayeritem/generate.py` together with the getters and the check's table:

    @property (nonatomic, readonly) MPMediaEntityPersistentID albumPersistentID MP_API(ios(80));
    @property (nonatomic, readonly) MPMediaEntityPersistentID artistPersistentID MP_API(ios(80));
    @property (nonatomic, readonly) MPMediaEntityPersistentID albumArtistPersistentID MP_API(ios(80));
    @property (nonatomic, readonly) MPMediaEntityPersistentID genrePersistentID MP_API(ios(80));
    @property (nonatomic, readonly) MPMediaEntityPersistentID composerPersistentID MP_API(ios(80));
    @property (nonatomic, readonly) MPMediaEntityPersistentID podcastPersistentID MP_API(ios(80));
    @property (nonatomic, readonly) NSUInteger albumTrackCount MP_API(ios(80));
    @property (nonatomic, readonly) NSUInteger discCount MP_API(ios(80));
    @property (nonatomic, readonly) NSUInteger beatsPerMinute MP_API(ios(80));
    @property (nonatomic, readonly, getter = isCompilation) BOOL compilation MP_API(ios(80));
    @property (nonatomic, readonly, getter = isCloudItem) BOOL cloudItem MP_API(ios(80));
    @property (nonatomic, readonly) NSString * lyrics MP_API(ios(80));
    @property (nonatomic, readonly) NSString * comments MP_API(ios(80));
    @property (nonatomic, readonly) NSString * userGrouping MP_API(ios(80));
    @property (nonatomic, readonly) NSURL * assetURL MP_API(ios(80));

Each member's dictionary key is the property's own name, which is the documented convention for
MPMediaItem's property constants and the only reading the header's spelling supports. It is **not**
verified against a populated item, because neither this Mac nor 6.1.3 can be given one without a
media library; what *is* measured is that the release carries none of these members, so a
port-created item - one built from a dictionary, which is exactly what the stand-in in the contract
check is - is the only thing that can answer them here.

Declared with a `getter=` attribute, so the property name is not the selector: `compilation` is implemented as `isCompilation`, `cloudItem` is implemented as `isCloudItem`.
<!-- /generated: 80 -->

