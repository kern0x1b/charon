# Forcing a decoded predicate or sort descriptor to be evaluated, iOS 7.0

Source: the SDK 26.2 headers, whose own comment is "Force a predicate which was securely decoded to
allow evaluation" (and the same for `NSSortDescriptor` and `NSExpression`).

The restriction is that an object read out of a secure archive must not be evaluated until the
application says so. **iOS 6.1.3 has no such restriction**: its `NSCoder` carries no allow-evaluation
flag, and a predicate decoded from an archive is evaluable the moment it exists. So on this release the
state the method promises is the state that already holds, and calling it changes nothing -- which is
the answer iOS 6 itself gives, and not a stub.

The flag is kept beside the object rather than dropped, and it is read back through
`-allowsEvaluation`, so the state travels with the object and an archive written by a newer system and
read here answers the question the property asks. What the port does not have is a way to make an
object that is *not* evaluable, because nothing on this release ever makes one.
