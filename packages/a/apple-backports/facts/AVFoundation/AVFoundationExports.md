# AVFoundation names the release already exports

The SDK dates some AVFoundation constants after iOS 6, and asked one by one with `dlsym` after every
framework of the release was loaded, iOS 6 exports fourteen of them. They are the release's own and are not
carried here, and the registry says so where an earlier record had them absent.

Source: an iPad 2 running 6.1.3 and the iOS 6.0 emulator.

## What the release exports

The five track association types `AVTrackAssociationTypeAudioFallback`, `...ChapterList`,
`...ForcedSubtitlesOnly`, `...SelectionFollower` and `...Timecode`, and the video colour keys and values
`AVVideoColorPropertiesKey`, `AVVideoColorPrimariesKey`, `AVVideoColorPrimaries_ITU_R_709_2`,
`AVVideoColorPrimaries_SMPTE_C`, `AVVideoTransferFunctionKey`, `AVVideoTransferFunction_ITU_R_709_2`,
`AVVideoYCbCrMatrixKey`, `AVVideoYCbCrMatrix_ITU_R_601_4` and `AVVideoYCbCrMatrix_ITU_R_709_2`. What an
`AVAssetWriter` of iOS 6 does with the colour keys was not compared with a newer release: the names are exported,
which is what an application that links against them needs, and nothing more is claimed.
