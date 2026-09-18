# NSData: base64, byte ranges and a buffer that is not copied, iOS 7

Source: the host's own Foundation, asked case by case, and the differential run of
`tests/backports/host/foundation2/run.sh`, which encodes every length from 0 to 80 bytes under eighteen
combinations of options, decodes a corpus of well formed and malformed input, and compares every answer
with the system's.

## Encoding

`-base64EncodedStringWithOptions:` and `-base64EncodedDataWithOptions:` answer the same text, one as a
string and one as its ASCII bytes. Empty data answers an empty result, not nil.

A line length option wraps the output, and the line ending is `\r\n` unless it is asked to be otherwise:
`64CharacterLineLength` alone already ends its lines with a carriage return and a line feed.
`EndLineWithCarriageReturn` on its own makes them `\r`, and asking for both endings gives `\r\n` again.
A line ending option without a line length does nothing at all - there are no lines to end. Asking for
both lengths at once also does nothing: neither wrapping happens. No line ending is added after the last
line.

## Decoding

`-initWithBase64EncodedString:options:` and `-initWithBase64EncodedData:options:` answer nil for anything
that is not base64, and they are strict: a space or a newline in the middle is enough, and so is padding
that does not complete the last group, or symbols after the padding.
`NSDataBase64DecodingIgnoreUnknownCharacters` drops everything outside the alphabet and the padding
before reading, so `QU JD` becomes the three bytes `41 42 43`. An empty string answers empty data rather
than nil.

## The other two

`-enumerateByteRangesUsingBlock:` hands the bytes over in as few ranges as the data is stored in: a
hundred thousand contiguous bytes arrive as one range covering the whole length. Setting the block's
`stop` ends the walk.

`-initWithBytesNoCopy:length:deallocator:` takes the buffer as it is and calls the block when the data is
deallocated, with the same pointer and length it was given - it is the block, and not the data, that
frees anything. The block is called even when the buffer is NULL and the length is zero, and that call
happens at deallocation, not before: a data object still alive has not called it.
