# The threading model of BLAS and LAPACK, iOS 18.0

`BLASSetThreading` and `BLASGetThreading`, with the enumeration `BLAS_THREADING_MULTI_THREADED`, `BLAS_THREADING_SINGLE_THREADED` and
`BLAS_THREADING_MAX_OPTIONS`, arrived in iOS 18.0: the host's 18.0 cache names both functions, and no cache the port holds below it
does. The values are 0, 1 and 2 - the first enumerator is 0 and the two that follow count on from it, which is the spelling in the
header.

The setting is per thread, held in thread-local storage, and a thread that has set none answers `BLAS_THREADING_MULTI_THREADED`,
which is the value a thread starts with: Accelerate decides how many threads to use. Measured on the host, from a thread that has set
nothing: `BLASGetThreading()` answers 0, `BLASSetThreading(BLAS_THREADING_SINGLE_THREADED)` answers 0 and `BLASGetThreading()` then
answers 1, `BLASSetThreading(BLAS_THREADING_MULTI_THREADED)` answers 0 and `BLASGetThreading()` answers 0 again, and
`BLASSetThreading(99)` answers -1 with `BLASGetThreading()` still answering 0 afterwards: a value the library does not have is refused
and the setting is left as it was.

## The header the build SDK does not have

These five names come from `vecLib/thread_api.h`, which arrived with the API. The SDK the port builds against is 16.4, which has no
such header - `vecLib.framework/Headers` there holds blas_new.h, cblas.h, cblas_new.h, clapack.h, fortran_blas.h, lapack.h,
lapack_types.h, lapack_version.h, vBasicOps.h, vBigNum.h, vDSP.h, vDSP_translate.h, vForce.h, vecLib.h, vecLibTypes.h, vectorOps.h and
vfp.h, and no thread_api.h. So the enumeration and the two prototypes are declared in `Accelerate/BLASThreading18.m` as the header
declares them, and the two entry points are real: they are in the library, and the registry carries all five names as implemented.

What is missing is only the *declaration* on the client side: a program compiled against the lifted 16.4 SDK cannot name
`BLASSetThreading` or `BLASGetThreading`, because nothing includes a header that declares them. Adding `thread_api.h` to the lift
(`modules/apple/lift.lua`, which copies the SDK's own headers with the availability lowered and has no way to add one the SDK does not
carry) is what closes that, and it is a change to a module every band shares. Until it is there these two functions are reachable
through a declaration of their own and are not reachable by including `<Accelerate/Accelerate.h>`, which is a gap in the header and
not in the code; the measurements above are of the code.
