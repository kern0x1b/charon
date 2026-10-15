# AVSpeech: the utterance, its rate constants

Three classes of AVFAudio's speech API - `AVSpeechUtterance`, `AVSpeechSynthesisVoice`,
`AVSpeechSynthesizer` - and the constants and delegate protocol around them. Before iOS 7 there was no
public speech API on this release (6.1.3 exports none of the classes), so an application that strong-imports
them fails to load: dyld stops it at launch, which is why these are carried and not reported `absent`
(COORDINATION.md section 2).

This file covers the iOS 7-9 rows. The iOS 10+ and iOS 13+ rows (`attributedSpeechString`,
`speechUtteranceWithAttributedString:`, `prefersAssistiveTechnologySettings`, `outputChannels`, the
personal-voice and SSML and marker rows, `writeUtterance:`) are not carried here and the registry stays silent
on them.

## AVSpeechUtterance (slice 1)

A data class: the text, a voice and four numbers, held as the caller set them. Nothing speaks yet; the engine
that does is the second half of this file.

Measured against the host's own class (`tests/backports/host/avf-speech/run.sh`, 88 checks, host and port in one
binary; a planted pitch-floor control goes red with 5 failures):

- **Defaults.** `+speechUtteranceWithString:` and `-initWithString:` give rate 0.5, pitchMultiplier 1,
  volume 1, both delays 0, voice nil. A plain `-init` gives every number 0 (measured: rate 0, pitch 0,
  volume 0). So the port overrides `initWithString:` and does not override `init`.
- **Setters.** Measured on the host with the inputs listed in checks.m:
  - `rate`: a negative value and NaN become 0. Nothing above is clamped (2 stays 2, infinity stays infinity).
  - `pitchMultiplier`: a value below 0.5 and NaN become 0.5. Nothing above is clamped (3 stays 3).
  - `volume`: a negative value and NaN become 0. Nothing above is clamped (2 stays 2).
  - `preUtteranceDelay` and `postUtteranceDelay`: no clamp at all (-1 stays -1).
- **The string is retained, not copied.** A caller who appends to its `NSMutableString` after building the
  utterance sees the change on both the host and the port.
- **Copy.** `-copy` gives a new object with every number, the same string and the same voice object.
- **Secure coding.** Both declare `NSSecureCoding`. The archive keys are `speechString`, `voice`, `rate`,
  `pitchMultiplier`, `volume`, `preUtteranceDelay`, `postUtteranceDelay` (read with `plutil -p` on the host's
  archive). Decoding without secure coding raises `NSInvalidUnarchiveOperationException` on the host, so the
  port's decode is the secure one.

### The divergence: speechString on a secure round trip

The host's encoder writes `speechString` as nil: in the host's archive the `speechString` key refers to object 0,
which is `$null`, though the utterance held `hello there`. A secure decode on the host therefore returns an
utterance whose `speechString` is nil. The port encodes the string and decodes it back. This is pinned in
checks.m as a divergence: if the host ever keeps the string, the check goes red and this file has to be read
again.

Why the port keeps the string rather than copying the host: the host is a macOS build, and nothing measured here
says iOS 7 writes nil. The port answers what an application expects from a round trip. If the device run shows
iOS 7 writing nil too, the port follows it and this entry changes.

### The voice on decode (narrowed in slice 2)

`-initWithCoder:` decodes `voice` as `NSObject` for now. Naming `AVSpeechSynthesisVoice` in this image would make it
import a class the 6.1.3 release does not carry, and that import fails at load. Slice 2 carries the class and
narrows the decode to it.

### Rate constants

`AVSpeechUtteranceDefaultSpeechRate` 0.5, `AVSpeechUtteranceMinimumSpeechRate` 0.0,
`AVSpeechUtteranceMaximumSpeechRate` 1.0, each `const float`. The host's own AVFAudio gives the same three values
(checks.m, the "constant" lines). The iOS 7.0 armv7 shared cache, read with `tools/corpus/cache-value.lua`, gives
bytes `0000003f` (0.5), `00000000` (0.0) and `0000803f` (1.0) for the three names, so the values are the release's,
not typed from the header. The cache tool's storage column reads 198530148 for the default rate and 4 for the other
two: noted, not explained, and the bytes agree with the host.

Read from the iOS 6.1.3 armv7 cache with the same tool, none of the three names exists: a dash for each (the
ledger, `AVFAudio.tsv`, rows 51-53, says so too). The same run read `AVSpeechSynthesizer` as absent from 6.1.3.
