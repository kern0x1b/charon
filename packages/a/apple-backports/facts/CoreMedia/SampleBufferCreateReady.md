# The ready-creating and per-sample sample buffers on a release that has neither

iOS 6 carries `CMSampleBufferCreate` and `CMSampleBufferCreateForImageBuffer` with their
`dataReady`/`makeDataReadyCallback` parameters - `AVCapturePhotoOutput.m` and
`AVCaptureDevice+VideoZoom7.m` already call both that way and are gated green in the 6.1.3 band. What it
does not carry is the iOS 8 spelling of the same thing with the readiness fixed on, the per-sample walk
of iOS 8, or the block-taking creators of iOS 12.2. Five functions, all written over the release's own
six, so none of them has to know what a `CMSampleBuffer` is made of.

## The two ready creators

`CMSampleBufferCreateReady` and `CMSampleBufferCreateReadyWithImageBuffer` are the release's own calls
with `dataReady` true and no callback. Nothing else to decide: the buffer is the host's, with the host's
timing, the host's sample sizes and the host's data. Measured over 4 sample counts x 5 timing counts,
with and without a data buffer, and with no out pointer: 143 answers, all the same as the host's
(`tests/backports/host/coremedia7/createready.m`).

## The per-sample walk

`CMSampleBufferCallBlockForEachSample` reads the sample buffer's own sample-size array and per-sample
timing, and for each sample builds a one-sample buffer over *that sample's bytes* with
`CMBlockBufferCreateWithBufferReference`, which the release exports. The release's private
`CMSampleBufferCallForEachSample` was not used: it is a different function with a different contract,
and its signature is not in any SDK on this machine.

Two things the port does not reproduce, both measured:

- **A buffer built with fewer timing entries than samples.** The host answers for the first sample and
  then gives `kCMSampleBufferError_BufferHasNoSampleTimingInfo`; the port asks the release for each
  sample's timing and gives the same error for the first one too. 10 of 12 such answers agree. The
  port's is the release's own answer, unaltered, which is the most defensible reading of "containing its
  timing" in Apple's own words.
- **The temporary buffer's length.** The host's temporary buffer spans the whole data buffer (12 bytes
  for a buffer of one 8-byte sample); the port's is exactly the sample. The sample's own bytes, the
  sample count, the sample size and the timing are the same, and those are what the test compares - the
  total length is not part of the claim, because handing a handler 12 bytes for an 8-byte sample is not
  what "referring to the sample data" means.

## The two block-taking creators

`CMSampleBufferCreateWithMakeDataReadyHandler` and
`CMSampleBufferCreateForImageBufferWithMakeDataReadyHandler` build the buffer with the release's own
creator at the readiness asked for and, when it was not ready, run the handler over the finished buffer
and answer the handler's own status; a failure releases the buffer and leaves the out parameter null,
which is what the host does.

The limit is real and is written down rather than papered over: on this release the handler runs at
creation, not when the application later calls `CMSampleBufferMakeDataReady`, because a system
`CMSampleBuffer` has nowhere to keep a block and the band machinery cannot redefine
`CMSampleBufferMakeDataReady` (the release exports it, so an object carrying that name would be
re-exported rather than kept). For a buffer built from a `CMBlockBuffer` that already holds its bytes -
which is what the parameter is for - the data is ready at creation, so the handler runs at the only
moment the data is ready. An application that builds a buffer over an *empty* block and expects the
handler to run later will find the handler already run and the buffer still not ready unless the handler
made it ready itself, which is the handler's own contract.
