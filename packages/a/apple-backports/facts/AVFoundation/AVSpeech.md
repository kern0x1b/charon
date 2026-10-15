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

## AVSpeechSynthesisVoice (slice 2, measured; committed, the gate is not yet run on it)

The release's voice listing, read in the 6.1.3 guest (`tests/backports/host/avf-speech/voices/probe.m`, run with
`xmake emulate -d iPhone4,1 -r 6.1.3 run /usr/libexec/avfspeechvoices`, pass):

- `VoiceServices.framework` is not loaded in a process by default: `NSClassFromString(@"VSSpeechSynthesizer")` is nil
  until the framework is dlopen'd. Loaded by path, the class answers.
- Class methods (names from `tools/corpus/objc-inventory.lua` on the 6.1.3 cache, found by the probe on the image):
  `+availableLanguageCodes` (36 codes), `+availableVoicesForLanguageCode:` (one `NSString` name per code),
  `+availableVoices` (the names for the current language: one, `Samantha`, on the guest's en-US), `+isSystemSpeaking`.
- The 36 voices: one per language code, named by the release: ar-SA Maged, cs-CZ Zuzana, da-DK Ida, de-DE Anna,
  el-GR Alexandros, en-AU Karen, en-GB Daniel, en-IE Moira, en-US Samantha, en-ZA Tessa, es-ES Monica, es-MX Paulina,
  fi-FI Mikko, fr-CA Julie, fr-FR Thomas, hi-IN Lekha, hu-HU Eszter, id-ID Damayanti, it-IT Silvia, ja-JP Kyoko,
  ko-KR Yuna, nl-BE Ellen, nl-NL Xander, no-NO Stine, pl-PL Agata, pt-BR Raquel, pt-PT Joana, ro-RO Simona,
  ru-RU Milena, sk-SK Laura, sv-SE Alva, th-TH Narisa, tr-TR Aylin, zh-CN Ting-Ting, zh-HK Sin-Ji, zh-TW Ya-Ling.
  The same set is on the image's file system: `VoiceServices.framework/TTSResources/<code>/clc_<code>_<voice>_cfg1.dat`
  (72 `clc_` files: a language pack and a voice per code).
- The listing carries no identifier, no quality and no gender. `quality` is Default for every voice on the image (the
  listing has no quality field), and the host's 180 voices are all quality 1, which is Default.
- The listing is in `voices/listing-6.1.3.txt` (the probe's own lines, pass on iPhone4,1 6.1.3 at time scale 10). The
  host's test stub (`tests/backports/host/avf-speech/voice-checks.m`) holds these 36 pairs, and run.sh checks it.

The host (macOS, measured in the run folder `.agent-work/runs/v-avspeech3/host/`, not committed) answers differently in
size and form: 180 `speechVoices` with identifiers such as `com.apple.voice.compact.en-US.Samantha`, and on this macOS
there is no VoiceServices framework (dlopen finds none, and `VSSpeechSynthesizer` is absent), so the port's listing is
empty on the host and the differential feeds the port the 6.1.3 listing through the stub. The rules the port follows,
measured on the host:

- `voiceWithLanguage:nil` is the current language's voice (Samantha). A bare language answers the current language's
  voice when the current language has that primary language (`en` is Samantha under en-US, Daniel under en-GB, Thomas
  for `fr` under fr-FR); otherwise the first voice of that language in the host's order (`en` is Karen under de-DE,
  `fr` is Amelie under en-US). `en-NZ` answers as `en`. `xx-YY` and the empty string answer nil.
- `voiceWithIdentifier:` answers nil for nil, an unknown identifier, `com.apple.voice.compact.en-US.Samantha ` (a
  trailing space), and `AVSpeechSynthesisVoiceIdentifierAlex` on this host. It ignores case: `...zh-HK.SinJi` answers
  Sinji, as `...zh-HK.Sinji` does.
- The identifier of a voice (measured with `host-match2.m`): where the host's voiceWithLanguage: with the release's code
  gives a voice with the release's name (accents and hyphens folded), the identifier is the host's. That is 22 of the
  36: the table in `AVSpeechSynthesisVoice7.m` (`CharonHostIdentifiers`). Most are `com.apple.voice.super-compact.<code>.<name>`;
  en-US Samantha is `com.apple.voice.compact.` (the one `compact` on the host); the host's identifier drops the hyphen
  (`Ting-Ting` is `Tingting`, `Sin-Ji` is `Sinji`). The other 14 voices have no host voice under their name and language
  (ar-SA Maged, da-DK Ida, el-GR Alexandros, fr-CA Julie, fi-FI Mikko, hu-HU Eszter, it-IT Silvia, no-NO Stine,
  pl-PL Agata, pt-BR Raquel, ro-RO Simona, th-TH Narisa, tr-TR Aylin, zh-TW Ya-Ling). Their identifier is built by the
  host's pattern, `com.apple.voice.super-compact.<code>.<name>` with the hyphen dropped, and the host answers nil for
  each (checked by voice-checks.m). That built identifier is the one thing in this section not measured on a host
  voice: the coordinator's ruling of 2026-10-15 (the identifier is the host's; a voice the host lacks gets the host's
  pattern) is in `coordination/crutches.md`.
- `currentLanguageCode` is the first preferred language with its region filled from the locale. Measured with
  `-AppleLanguages "(xx)" -AppleLocale yy` (the locale override works only as command-line arguments): `fr-CA` with
  locale `en_GB` gives `fr-CA` (the language wins); `ja` with `ja_JP` gives `ja-JP`; `de` with `de_DE` gives `de-DE`;
  `(de)` with `en_US_POSIX` gives `de-DE`; `en-GB` gives `en-GB`. Two divergences from a plain tag: `zh-Hans-CN`
  gives `cmn-CN`, and `ar-SA` gives `ar-001` (the host's list has no `ar-SA`, and `sr-Latn-RS` also gives `ar-001`).
  The port resolves the tag against the release's own codes: exact match, else the first code of the same primary
  language, else the tag itself.

The port (`AVFoundation/AVSpeechSynthesisVoice7.m`) builds `speechVoices` from the listing (36 on 6.1.3), answers
`voiceWithLanguage:` and `voiceWithIdentifier:` over that list, and `currentLanguageCode` as above. The host
differential is `tests/backports/host/avf-speech/voice-checks.m` (run.sh, four locale variants, a planted identifier
that goes red). The pinned divergences: the release's ar-SA against the host's ar-001 (the answers of `ar`, `ar-SA`,
nil under ar-SA, and currentLanguageCode), and the host's cmn-CN against the release's zh-CN (zh-Hans-CN).

Not done in this slice: the gate on this tree, the release split, and the speaking
engine (`AVSpeechSynthesizer`). The 6.1.3 selectors of `VSSpeechSynthesizer` for speaking are in the inventory, and
the delegate protocol `VSSpeechSynthesizerDelegate` is there too (`speechSynthesizer:didFinishSpeaking:withError:`,
`speechSynthesizer:willSpeakRangeOfSpeechString:`, the start, pause and continue callbacks): the delegate order and
the no-voice behaviour are not measured yet.
