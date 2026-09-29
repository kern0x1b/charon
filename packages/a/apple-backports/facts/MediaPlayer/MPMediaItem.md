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
