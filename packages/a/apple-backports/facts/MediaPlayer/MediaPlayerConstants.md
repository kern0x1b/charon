# The MediaPlayer constants the port carries

Thirteen string constants, in two objects, because `release-split` found the band is two:
**`MPMediaPlaylistPropertyCloudGlobalID` first appears at 8.2** and the other twelve at 9.0. The corpus
filed all thirteen under 9.0; the tool decides a ladder, and one file carrying both mixes two releases'
symbols.

The values are Apple's, read from the host's own `MediaPlayer` by `dlsym` and printed as text and bytes
by `tests/backports/host/mediaplayer-constants`. **They are not this symbol's name.** Ten of the thirteen
are dotted `public.*` strings, and `MPNowPlayingInfoPropertyCurrentLanguageOptions` holds the **singular**
`MPNowPlayingInfoPropertyCurrentLanguageOption` — a one-character difference that a naming convention
would have got wrong. Foundation's own constants gave the same warning: 12 of 15 were not their names.

**iOS 6.1.3 exports none of the 31 MediaPlayer constants**, read from that release's dyld cache with the
tools in `charon/tools`, so the port carries every one of them.

A constant is **read, never called**. Nothing here touches `MPMediaLibrary`, `MPMediaQuery` or a library.
