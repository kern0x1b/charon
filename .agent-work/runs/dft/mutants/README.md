# Mutants for vDSPDFTInterleaved15.m

Applied to a **copy** of the port under this directory, never to the tree. Each is built with the same
three `-D` renames the differential uses and run against the same host.

| mutant | result |
| --- | --- |
| a twiddle's sign flipped (`sign = forward ? -1.0 : 1.0` -> `sign = 1.0`) | **17 checks, 0 failures — NOT DETECTED** |

**One mutant run, and it does not go red, so the differential is not yet a check.** The mutation landed -
`double sign = 1.0;` is at line 88 of the mutant copy and the tree still carries the conditional - and the
binary builds and runs. So the port's output is *bit identical* to the host's with the forward sign flipped,
which means the sign is not reaching the arithmetic the way the source reads.

The five remaining mutants have not been run. They are not counted here as passing and the row's record does
not claim a mutation.

## What would settle it

The port's twiddle sign is the only thing the mutation touches, so either the sign is compensated somewhere in
the real path - the split's `W_k` carries its own `e^{-i*pi*k/N}` and a double flip would cancel - or the
differential is not calling the port's function at all. The first is checked by flipping the **split's** sign
instead and seeing whether the real-to-complex forward goes red; the second by printing which symbol the
`charon_host_*` call actually binds to. Neither has been done.
