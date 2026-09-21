# NSURLSession

Source: the host's own Foundation, through the differential run of
`tests/backports/host/session/run.sh`, which puts the system's session and the backport side by side on
the same server and holds both to the same transcript. The host's Foundation is newer than any cache we
hold, so it is the source for behaviour a test can observe; a cache is read where a test cannot see the
answer.

## Following a redirect

`Authorization` is taken off the request the session follows with, whatever the redirect leads to: the
same origin loses it as surely as another one. Everything else the application set travels on, including
`Cookie` set by hand and any header of its own, and the cookie storage adds its cookies to the new request
as it would to any other. The backport did the opposite at first - it kept the header inside one origin and
stripped a set of them when the origin changed - and the differential run named both mistakes.

A session follows at most 20 redirects; the 21st fails with `NSURLErrorHTTPTooManyRedirects` and the failing
URL of the last hop.

## What the release cannot do

`TLSMinimumSupportedProtocol` and `TLSMaximumSupportedProtocol` reach CFNetwork on a modern release and bound
the handshake. iOS 6 hands its requests to NSURLConnection, which takes no such bound, so the backport has
no setters for them - `respondsToSelector:` answers no, and a call raises rather than storing a value that
changes nothing - and the getters answer with the bounds the platform really has, SSLv3 to TLS 1.2. An
application that only reads them runs as it does on a newer release; one that asks before it narrows them
learns that it cannot, and one that narrows them without asking stops at the call.

## The key a background session would have answered under

`+backgroundSessionConfigurationWithIdentifier:` is the name iOS 8 gave the factory iOS 7 shipped as
`+backgroundSessionConfiguration:`, with nothing else changed, so the port answers it with the older one: an
application written against either name gets the same configuration, and the identifier it is given is the
identifier the configuration holds. What the configuration cannot do is below - the transfers run in the process,
since the release has no daemon to hand them to.

`NSURLErrorBackgroundTaskCancelledReasonKey` carries its own name as its value, read from the host's own
Foundation. It is the key an error's `userInfo` holds when the system cancels a background transfer, and
nothing in this release cancels one, because the backport's background configuration runs in the process
like any other session and the daemon that would have reported a reason is not there. The constant is
carried so that an application that reads the key out of an error, or names it in a comparison, builds and
runs; it is never the key of an error the backport makes.

## The constants and a task's priority

Measured against the host's own Foundation, and held by the differential transcripts of
`tests/backports/host/session` and by the device test:

- `NSURLSessionTaskPriorityLow`, `Default` and `High` are 0.25, 0.5 and 0.75, and a new task's priority is
  0.5.
- `-setPriority:` keeps a value from 0 to 1 and ignores anything outside it, leaving the priority it had:
  0.3 followed by -0.1, 1.0001, 2, -5 or infinity still reads 0.3. The test is `priority < 0 || priority >
  1`, so NaN is not outside it and is kept.
- `NSURLSessionTransferSizeUnknown` is -1, and it is what `countOfBytesExpectedToReceive` answers once a
  response has come without a length; before any response it answers 0.
- `NSURLSessionDownloadTaskResumeData` is its own name, and it is the key under which a cancelled download's
  error carries the data to resume from.
