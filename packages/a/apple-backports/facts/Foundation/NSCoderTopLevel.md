# Decoding a top-level object with an error, iOS 9

Source: the host's own Foundation, macOS 27, through the differential run of
`tests/backports/host/foundation2/run.sh`, which decodes archives with the right key, a missing one, a nil
value, no key at all, the wrong classes and corrupt data; the device test holds iOS 6 to the same records.

`-decodeTopLevelObjectForKey:error:`, `-decodeTopLevelObjectOfClass:forKey:error:`,
`-decodeTopLevelObjectOfClasses:forKey:error:` and `-decodeTopLevelObjectAndReturnError:` all wrap the
matching plain decode - `decodeObjectForKey:`, `decodeObjectOfClass:forKey:`,
`decodeObjectOfClasses:forKey:` and `decodeObject` - and turn what that raises or answers into an error
instead of an exception or silence:

- an exception from the plain decode becomes `NSCoderReadCorruptError` (4864), its reason carried as
  `NSDebugDescriptionErrorKey`;
- a plain decode that raises nothing but answers nil - a key that is not there, a value that is nil, or
  `decodeObject` with no key at all when the archive was written with one - becomes an error too, domain
  `NSCocoaErrorDomain` code 4865. A real class mismatch under secure coding is the exception case above,
  not this one; this is the case of nothing to decode at all;
- a failure the coder already recorded through `-failWithError:` is read back and takes precedence over
  either.

A key that is really there, and a class or a set of classes the decoded object belongs to, answer the
object and no error, whichever of the four is asked and whichever initializer the unarchiver was made
with - `initForReadingWithData:`, `initForReadingFromData:error:` or one that already reads a whole
archive at once behave the same.
