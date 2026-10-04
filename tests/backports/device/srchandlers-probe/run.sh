#!/bin/sh
# A barrier source's cancellation and registration handlers on the emulated iPhone3,1 at 6.1.3 (10B329),
# through heavy.sh, on the route tests/backports/device/vdsp-probe/run.sh uses: the program is run by a bare
# path with no arguments. That is not a choice - measured on 2026-10-04, a command with words after the path
# comes back `fail(spawn error 2)` and the program run by a bare path prints `argc=1 argv0=...`. So the
# program forks one child per scenario, and fork works here: a child that does nothing, that prints, that
# makes a queue, that makes a barrier block, that makes a source and reads a record off it, and that runs a
# dispatch_async and waits for it, all exit 0 on this release.
#
# PREDICTION, written into this file before the run and not changed after it (macOS 27 host, arm64, Apple
# clang 21.0.0 for the build; the guest is this repository's emulated iPhone3,1 at 6.1.3 10B329):
#   - OS_dispatch_source is present on 6.1.3, so the records these shims keep can exist there at all. (At
#     the 4.3 floor it is false, and the shims are inert by construction, which is why this is built at 6.1.3.)
#   - Darwin-6.1.3 answers held=yes: libdispatch-228 calls both handlers from inside dispatch_source_cancel
#     and dispatch_resume and returns, the shape the host was measured to have.
#   - Darwin-6.1.3 answers alone=NO on a CONCURRENT target queue. The barrier bit belongs to the source from
#     iOS 10 (libdispatch-703 marks it DQF_BARRIER_BIT); before that these two handlers are ordinary blocks
#     on the source's target queue. This is the premise of the whole design, and it is what this run is for.
#   - both sides answer alone=yes on a SERIAL target queue: one block at a time there whatever a barrier does.
#   - neverresumed answers ran=no on both sides: a source that was never resumed runs no handler.
#   - retargetbefore and retargetafter answer the same on both sides (the handler follows the new queue), and
#     onqueue returns on both sides rather than deadlocking.
#   - resumecancel answers order=RC on both sides at a gap of 50 ms.
#   - the shims answer held=yes (they submit and return, as ruled) and alone=YES on the concurrent width.
# If alone comes out yes on the system's side at 6.1.3, the premise is wrong, these shims have nothing to fix
# on that release, and this run says so.
#
# The symbol check is the point of the second gate below, not a nicety in it. `add_files` of a shim that
# does not match is a warning xmake carries on with, so a build whose root is one ".." too many links
# without the shims and the run then answers for a program that never had them. And the renaming headers
# must NOT be force-included: with them, a shim's own call to the release is the shim again.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# Four ".." up from this directory (tests/backports/device/srchandlers-probe) is the repository root: the
# directory is device's child, device is backports', backports is tests', tests is the root's.
root=${SRCH_ROOT:-$here/../../../..}
out="$here/run"
mkdir -p "$out"
cd "$here"
export SRCH_ROOT="$root"

device=${SRCH_DEVICE:-iPhone3,1}
release=${SRCH_RELEASE:-6.1.3}
xmake=/opt/homebrew/bin/xmake
heavy=$HOME/Git/projects/ios/coordination/heavy.sh

# Configure, build and install run directly and only the emulator run goes through heavy.sh, which puts it
# in the bulk lane. heavy.sh breaks this project's `xmake f`: measured 2026-10-04 with the same lock in
# place, the same command under heavy.sh fails its configure with every package reported as not found -
# shade, swiftshader, emulator-guest, iphoneos-sdk, ld64, ldid, llvm, firmware-tools - and
# `error: <no error object>`, while run directly it configures with rc=0.
"$xmake" f -p iphoneos -a armv7 -y > "$out/configure.log" 2>&1
"$xmake" -y > "$out/build.log" 2>&1
"$xmake" emulate -d "$device" -r "$release" install > "$out/install.log" 2>&1

program=sourcehandlers
built="$here/build/iphoneos/armv7/release/$program"

# LC_UUID, not a byte hash, and that is 7e035ac0's rule: strip rewrites the bytes before the signature and
# ldid -S changes those again, and neither touches LC_UUID, so the UUID is what identifies a build.
uuid_of() {
  [ -f "$1" ] || { echo "(no file)"; return; }
  /usr/bin/otool -l "$1" 2>/dev/null | awk '/cmd +LC_UUID/ { seen = 1; next } seen && $1 == "uuid" { print $2; exit }'
}

# The image is found by the built binary's own LC_UUID and never by `ls -d <prefix>-* | head -1`: a project's
# configuration is part of its image's name, so a second image appears as soon as the configuration changes
# and the glob cannot tell them apart. Measured 2026-10-04 on another project of this shape, whose glob
# picked srchandlers-4f99d896 (LC_UUID 1C6C7736-258A-3C40-9324-CBB3E15A6A37) while the install had put that
# build in srchandlers-b44a10d3 (0DC8D3B2-A9B3-3EF7-93DE-435995B89F8D).
built_uuid=$(uuid_of "$built")
installed=
for candidate in "$HOME"/.charon/emulator/images.noindex/srchandlersprobe-*/"${device}"_*/rootfs/usr/libexec/$program; do
  [ -f "$candidate" ] || continue
  if [ "$(uuid_of "$candidate")" = "$built_uuid" ]; then
    installed=$candidate
    break
  fi
done
{
  printf 'built     %s\n' "$built"
  printf 'built     LC_UUID %s\n' "$built_uuid"
  printf 'installed %s\n' "${installed:-NOT FOUND}"
  printf 'every image of this project, and the LC_UUID of the program in each:\n'
  for candidate in "$HOME"/.charon/emulator/images.noindex/srchandlersprobe-*; do
    [ -d "$candidate" ] || continue
    printf '  %s  %s\n' "$(basename "$candidate")" \
      "$(uuid_of "$candidate/${device}_10B329/rootfs/usr/libexec/$program")"
  done
  if [ -n "$installed" ]; then
    printf 'the image holding this build was found by its LC_UUID, not by its name\n'
    printf 'HASHES MATCH\n'
  else
    printf 'no image holds a program with this build LC_UUID, so the run is NOT going ahead\n'
    printf 'HASHES MISMATCH\n'
  fi
} > "$out/hash.txt" 2>&1
grep -q "HASHES MATCH" "$out/hash.txt" || { cat "$out/hash.txt"; exit 1; }
cat "$out/hash.txt"

# The six shims are in the binary, and the release's own names are not: the shims are hidden definitions
# under their own names, so a program that calls dispatch_source_cancel reaches libdispatch's, which is what
# makes its system column the release's answer. dispatch_block_create is the one plain name a shim claims,
# with an __asm__ alias, and it is listed so that its presence is not read as a leak. The counts are taken
# from nm's third field, the symbol's own name: a name like _charon_dispatch_source_create contains
# _dispatch_, so a substring count would count the shims as claims on the release's names.
{
  printf 'the six shims, which are hidden definitions under their own names:\n'
  nm "$built" 2>/dev/null | awk '$2 == "t" || $2 == "T" { print $1, $2, $3 }' \
      | grep -E ' _charon_dispatch_(source_create|set_target_queue|source_set_cancel_handler|source_set_registration_handler|source_cancel|resume)$' \
      | sort -k3
  printf 'the release names this binary defines itself (dispatch_block_create is the one a shim claims):\n'
  nm "$built" 2>/dev/null | awk '$2 == "t" || $2 == "T" { print $1, $2, $3 }' | grep -E ' _dispatch_' | sort -k3
} > "$out/symbols.txt" 2>&1
shims=$(awk '$3 ~ /^_charon_dispatch_/' "$out/symbols.txt" | wc -l | tr -d ' ')
renamed=$(awk '$3 ~ /^_dispatch_/' "$out/symbols.txt" | wc -l | tr -d ' ')
cat "$out/symbols.txt"
printf 'the six shims linked: %s; the release names this binary claims: %s\n' "$shims" "$renamed"
if [ "$shims" -ne 6 ] || [ "$renamed" -ne 1 ]; then
  printf 'the binary does not hold the six shims and only dispatch_block_create, so the run is NOT going ahead\n'
  printf 'SYMBOLS MISMATCH\n'
  exit 1
fi
printf 'the six shims are linked and the only release name this binary claims is dispatch_block_create\n'
printf 'SYMBOLS MATCH\n'

"$heavy" "$xmake" emulate -d "$device" -r "$release" -t 900 -s 300 run \
    "/usr/libexec/$program" > "$out/run.log" 2>&1 || true
"$xmake" emulate log > "$out/guest.log" 2>&1 || true
sed 's/\x1b\[[0-9;]*m//g' "$out/run.log"