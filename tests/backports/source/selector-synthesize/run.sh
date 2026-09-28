#!/bin/sh
# The selector/synthesize check, with its two proofs. It reports what it finds and never fails the
# tree: a collision is a question for the owning band, not a gate error. What it does fail on is
# itself - if it cannot find the known shape, or finds one where there is none, it says so and stops,
# because then its output is not evidence.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
exec python3 "$here/check.py" "$@"
