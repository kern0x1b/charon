#!/bin/sh
# Disassemble one function of one image of a real dyld shared cache, at the address the release gives
# it, so a pc-relative reference (`adrp`/`add` to a literal, a `bl` inside the image) can be read as
# the address the release itself uses.
#
#   CHARON_ROOT=<worktree> sh tools/corpus/disasm.sh <cache> <image substring> <lo> <hi>
#
# The route, and why each step is here: the bytes come from the project's own cache reader
# (skeleton-table.lua's `bytes`), never from a disassembler pointed at the cache file -- a Mach-O at
# 0, with every segment at the wrong place, decodes to something that looks like code and is not.
# `.byte` in a .s keeps the assembler from deciding what the bytes mean, and `clang -c -arch arm64e`
# picks the arm64e assembler. llvm-objdump -d then prints them; the addresses it prints are the
# offsets into the block, so they are shifted by `lo` here to become the release's own addresses,
# which is the point of the whole exercise.
#
# Nothing is written outside the worktree's own scratch directory, and the cache is opened read only.

set -e

if [ -z "$CHARON_ROOT" ]; then
    echo "usage: CHARON_ROOT=<worktree> sh tools/corpus/disasm.sh <cache> <image> <lo> <hi>" >&2
    exit 2
fi
if [ $# -ne 4 ]; then
    echo "usage: CHARON_ROOT=<worktree> sh tools/corpus/disasm.sh <cache> <image> <lo> <hi>" >&2
    exit 2
fi

cache=$1
image=$2
lo=$3
hi=$4

base=$((0x$lo))
size=$((0x$hi - 0x$lo))
if [ "$size" -le 0 ]; then
    echo "disasm.sh: the window must be non-empty, got $lo .. $hi" >&2
    exit 2
fi

scratch=$CHARON_ROOT/.agent-work/runs/disasm
mkdir -p "$scratch"

raw=$scratch/bytes-$lo.txt
xmake l "$CHARON_ROOT/tools/corpus/skeleton-table.lua" "$cache" "$image" bytes "$lo" "$size" > "$raw"

# The reader prints its own header lines first (`#...`); the byte lines are the rest. A run with no
# byte lines is a read that failed, and an empty .s would assemble to nothing and disassemble to
# nothing -- which looks like a function with no instructions in it.
grep -v '^#' "$raw" > "$scratch/hex-$lo.txt" || true
if [ ! -s "$scratch/hex-$lo.txt" ]; then
    echo "disasm.sh: the reader returned no bytes for $lo in $image" >&2
    exit 1
fi

expected=$(printf '%s' "$(tr -d '\n' < "$scratch/hex-$lo.txt")" | wc -c | tr -d ' ')
if [ "$expected" != "$((size * 2))" ]; then
    echo "disasm.sh: asked for $size bytes, the reader returned $((expected / 2))" >&2
    exit 1
fi

{
    echo "        .text"
    echo "        .globl charon_disassembled"
    echo "charon_disassembled:"
    awk '{for (i = 1; i <= length($0); i += 2) printf "        .byte 0x%s\n", substr($0, i, 2)}' \
        "$scratch/hex-$lo.txt"
} > "$scratch/bytes-$lo.s"

clang -c -arch arm64e -o "$scratch/bytes-$lo.o" "$scratch/bytes-$lo.s"
llvm-objdump -d "$scratch/bytes-$lo.o" \
    | awk -v base="$base" '
        # macOS awk has no strtonum and does not promise to read "0x.." out of a field as a number,
        # so the offset is converted here rather than by the shell or by the awk implementation.
        function hexvalue(text,   i, c, n) {
            n = 0
            for (i = 1; i <= length(text); i++) {
                c = tolower(substr(text, i, 1))
                n = n * 16 + index("0123456789abcdef", c) - 1
            }
            return n
        }
        /^ *[0-9a-f]+:$|^ *[0-9a-f]+:/ {
            offset = $1
            sub(/:$/, "", offset)
            here = hexvalue(offset)
            there = here + base
            text = substr($0, index($0, ":") + 1)
            printf "%s:\t%s\n", sprintf("%#x", there), text
            # A pc-relative operand was resolved by objdump against a program counter it does not
            # have: the block sits at 0 in the object, so every address it prints for a literal or a
            # branch is wrong by the base of the block. The two rules are different and both are the
            # instruction: ADRP adds the page of the PC, a branch adds the PC itself. Getting this
            # wrong produces an address inside no mapping, which is what a hand decode did on
            # 2026-10-03, so it is printed here rather than left to the reader.
            operand = text
            sub(/^.*[ \t]0x/, "", operand)
            sub(/[^0-9a-f].*$/, "", operand)
            if (operand == "" || operand !~ /^[0-9a-f]+$/) next
            if (text ~ /\tadrp[ \t]/) {
                printf "\t; adrp page %s; the add that follows adds its immediate to it\n", \
                    sprintf("%#x", hexvalue(operand) + (there - there % 4096) - (here - here % 4096))
            } else if (text ~ /\t(b|bl)[ \t]/) {
                printf "\t; branch target %s\n", sprintf("%#x", hexvalue(operand) + there - here)
            }
        }'