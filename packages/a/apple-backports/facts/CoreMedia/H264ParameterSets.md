# CMVideoFormatDescriptionGetH264ParameterSetAtIndex

Introduced in iOS 7.0. iOS 6 has CMVideoFormatDescription and the `avcC` sample description atom, so the function reads the parameter sets from the atom of the description.

- A description that is NULL, is not video, is not `avc1` or has no `avcC` atom answers -12710 and leaves every output as it was.
- Otherwise every output is zeroed first; a record shorter than 6 bytes or of a version other than 1 answers -12712.
- The NAL unit header length is `(byte 4 & 3) + 1`, and is all that is read when it is the only output asked for.
- The sets are the SPS group, the PPS group and, for profiles 100, 110, 122 and 144 when bytes remain, the extension group, numbered in that order.
- The pointer and size are set when the index is met and the call ends there when no count is asked for; the count is set only when the whole record parsed; an index not below the count answers -12712.

The behaviour was found by putting generated descriptions, records cut at every length and records with trailing bytes to the host's CoreMedia, over six indexes and all sixteen combinations of outputs, and holding the port to it: tests/backports/host/coremedia.
