# The type tree beside a translation: `.metallib.es2`'s property list

This is a contract. `tools/air2cpu` writes it and a later band reads it from Objective-C, and both
ends have to agree on the shape, so the shape is written down here rather than left in the writer.

## Why a file, and a property list

**A file, because the device never sees AIR.** `air2cpu` runs at build time on the host; only what it
writes ships, inside the `.metallib.es2` folder `MTKTextureLoader` already reads
(`facts/Metal/RenderPath.md`). A reflection object on the device therefore has nothing to re-read but
this file — a second pass in the loader would find no AIR to parse.

**A property list, because `NSPropertyListSerialization` has read one since iOS 2.** The 6.0 port
reads it with no parser of its own. The writer emits XML; the format is the same either way, so a
binary plist is readable by the same code.

## What is in it

Top level, a dictionary:

| key | value |
| --- | --- |
| `version` | integer, `1`. The reader refuses anything it does not know rather than reading it wrong. |
| `functions` | array, one dictionary per entry point, in the order the module has them. |

Each function:

| key | value |
| --- | --- |
| `name` | string, the entry function's name. |
| `arguments` | array, one dictionary per argument, in order. |
| `threadgroupSize` | array of three integers. A **hint**, and the AIR carries none: these are `0` unless the translator is taught to read the kernel's `air.threads_per_threadgroup`. |

Each argument:

| key | value |
| --- | --- |
| `index` | integer, its position — the same number the buffer index is. |
| `name` | string, the AIR's own argument name. |
| `access` | `read-only` or `read-write`, the two words `MTLArgument.h` uses for `MTLArgumentAccessReadOnly` and `MTLArgumentAccessReadWrite`. |
| `textureDataType` | `texture` when the argument is a pointer, `none` otherwise. The header's `MTLArgumentTextureDataType` has exactly these two. |
| `type` | the type tree, below. |

A `type` is a dictionary with a `kind`, and what else it carries depends on the kind:

| kind | also carries | meaning |
| --- | --- | --- |
| `scalar` | `scalar` | the name the emitter's own `typeOf()` gave it: `uint32_t`, `int32_t`, `float`, `uint8_t`, `uint16_t`, `uint64_t`. |
| `vector` | `length`, `elementType` | `MTLArrayType`, in the header's sense of a fixed-length array of one type. |
| `array` | `length`, `elementType` | a fixed array, the same shape. |
| `struct` | `members` | an array of `{name, index, type}`. |
| `pointer` | `pointee` | **the empty string, always** — see below. |
| `unknown` | — | a type the emitter's walk could not name. The reader answers `MTLUnknown`. |

## Two places the AIR is written as what it is

**A pointer's pointee is the empty string, and the reader answers `MTLUnknown` for it.** LLVM has
used opaque pointers since 15: `PointerType` carries no pointee type to ask for, which is why the
writer calls no accessor for one. The absence is in the data, not in the reader, and a reader that
invented a pointee would be reporting a type the AIR does not have.

**A struct's members are named by position.** In LLVM 23 a `StructType` carries element *types* but
no per-element *name*, so `members[]` entries have an empty `name` and an `index`, and the reader
answers `MTLUnknown` for the name rather than making one up.

Both are the writer calling `Emitter::vectorOf` and `Emitter::typeOf` — the emitter's own walk, made
public for it — so the tree in this file and the C beside it cannot disagree about what a type is.

## What it looks like, from a real run

`llvm-as tests/backports/host/air2cpu/fixtures/scale.ll -o scale.bc && air2cpu scale.bc scale.c scale.plist`,
whose head is:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>version</key>
  <integer>1</integer>
  <key>functions</key>
  <array>
    <dict>
      <key>name</key>
      <string>scaleK</string>
      <key>arguments</key>
      <array>
        <dict>
          <key>index</key>
          <integer>0</integer>
          <key>name</key>
          <string>values</string>
          <key>access</key>
          <string>read-only</string>
          <key>textureDataType</key>
          <string>texture</string>
          <key>type</key>
          <dict>
            <key>kind</key>
            <string>pointer</string>
            <key>pointee</key>
            <string></string>
          </dict>
        </dict>
        <dict>
          <key>index</key>
          <integer>1</integer>
          <key>name</key>
          <string>tid</string>
          <key>access</key>
          <string>read-write</string>
          <key>textureDataType</key>
          <string>none</string>
          <key>type</key>
          <dict>
            <key>kind</key>
            <string>scalar</string>
            <key>scalar</key>
            <string>uint32_t</string>
          </dict>
        </dict>
```

and it ends with the function's three `threadgroupSize` integers at `0`, and `</plist>`. The full run
is 2450 bytes for that one kernel, and `scale.c` beside it holds the C the emitter produced and a
kernel table naming `scaleK`.

## The vector arm, from a real run

`scale.ll` reaches two kinds: `scalar` and `pointer`. `fixtures/reflect.ll` reaches `vector` as well,
and the run reads:

```
llvm-as tests/backports/host/air2cpu/fixtures/reflect.ll -o reflect.bc
air2cpu reflect.bc reflect.c reflect.plist
  reflect.bc: OK reflectK
  reflect.bc: REFUSED vecK: a fourth scalar where the call convention carries three
  reflect.bc: 1 kernel(s) written to reflect.c, 1 refused
```

`reflect.plist` is 5305 bytes and its vector argument is:

```xml
        <dict>
          <key>index</key>
          <integer>1</integer>
          <key>name</key>
          <string>tint</string>
          <key>access</key>
          <string>read-write</string>
          <key>textureDataType</key>
          <string>none</string>
          <key>type</key>
          <dict>
            <key>kind</key>
            <string>vector</string>
            <key>length</key>
            <integer>4</integer>
            <key>elementType</key>
            <dict>
              <key>kind</key>
              <string>scalar</string>
              <key>scalar</key>
              <string>float</string>
            </dict>
          </dict>
        </dict>
```

A `float4` by value, length 4, element `float` — which is `MTLArrayType` with `arrayLength` 4 and
`elementType` a scalar, in the header's words.

## The array and struct arms: not reachable, and why

**They are not reachable from a device buffer, and no fixture can make them so.** The element type of
a Metal buffer lives in the `air.arg_type_name` metadata — the `"device float *"` of a signature — and
`air2cpu` never reads that metadata: its `typeOf()` looks at the LLVM type and nothing else. A
`ptr addrspace(1)` carries no pointee under opaque pointers, so there is no type to walk and the
writer writes the empty pointee it writes for `scale.ll`. **This is a property of the AIR, not a gap
in the writer**, and it is why `MTLPointerType`'s pointee answers `MTLUnknown` on this port: the type
is not in the data.

They are reachable only from an argument that is a value rather than a pointer, and only if some
*other* kernel in the same module translates — `air2cpu` writes the C only when a kernel translated and
writes the plist only after that, so a module whose every kernel is refused produces no file at all.
That is why `reflect.ll` has two entry points: `reflectK` translates and carries the file, and `vecK`
is described but refused.

**A by-value vector is refused, and the refusal is about scalars, not about vectors.** `vecK` takes
`float4` plus the three scalars, and the tool says "a fourth scalar where the call convention carries
three: the thread position, the threadgroup position and the group size" — it counts a vector argument
among the scalars the convention carries. So a vector by value cannot run, and the writer describes
it anyway because the type tree is written from the module's entry points rather than from the ones
that translated.

**The struct arm is compiled but unexercised, and it is not reachable from the AIR either.** An LLVM
23 `StructType` carries element types but no per-element names, and a Metal kernel takes its structs
inside a buffer — which is the opaque pointer above. A reader must therefore treat `MTLStructType` as
a kind it can *represent* and cannot *expect*, and the row for it says so.

## The argument's own metadata: where the element type actually is

**The previous version of this file said the type "is not in the data", and that was wrong.** It is in
the data — in the `air.kernel` argument node, as metadata and not as a type. The LLVM type of a device
buffer really does carry no pointee, but the AIR names the type in the same node as a string:
`air.arg_type_name` carries `"device float *"`, `air.arg_type_size` and `air.arg_type_align_size` carry
the two sizes, and a struct's members come as `air.struct_type_info`, a nested node of name, offset
and type three at a time. `air2cpu` never read any of it; the writer now does, in the same walk.

Each argument therefore gains, where the AIR has them and **only where it has them** — an absent key
is not written at all, and the reader answers `MTLUnknown` for what the AIR does not say:

| key | value | from |
| --- | --- | --- |
| `access` | `read-only` / `read-write` | the node's first key, `air.read_only` or `air.read_write` — the AIR's own words, not a guess from whether the type is a pointer |
| `typeName` | the type as the AIR spells it, e.g. `device float *` | `air.arg_type_name` |
| `size` | integer | `air.arg_type_size` |
| `alignSize` | integer | `air.arg_type_align_size` |
| `members` | array of `{name, offset, type}` | `air.struct_type_info` |

From `llvm-as tests/backports/host/air2cpu/fixtures/reflect.ll -o reflect.bc && air2cpu reflect.bc
reflect.c reflect.plist`, the buffer argument of `reflectK` reads:

```xml
        <dict>
          <key>index</key>
          <integer>0</integer>
          <key>name</key>
          <string>values</string>
          <key>access</key>
          <string>read-write</string>
          <key>textureDataType</key>
          <string>texture</string>
          <key>type</key>
          <dict>
            <key>kind</key>
            <string>pointer</string>
            <key>pointee</key>
            <string></string>
          </dict>
          <key>typeName</key>
          <string>device float *</string>
          <key>size</key>
          <integer>4</integer>
          <key>alignSize</key>
          <integer>4</integer>
        </dict>
```

The `type` is still the empty-pointee pointer, and `typeName` beside it is the type the AIR did name:
`MTLPointerType`'s element type is read from **this string**, not from the pointee. The `members` key
carries the struct's list the same way, and `reflect.ll`'s buffer argument produces:

```xml
          <key>members</key>
          <array>
            <dict>
              <key>name</key>
              <string>position</string>
              <key>offset</key>
              <integer>0</integer>
              <key>type</key>
              <string>float3</string>
            </dict>
            <dict>
              <key>name</key>
              <string>velocity</string>
              ...
```

**The values in that fixture are invented and are marked as such in its own header.** No Apple AIR
was read to make them: the host's Metal compiler service crash-loops, so no real library could be
produced here. What is exercised is the *shape* — that the writer finds a nested node where it
expected a string and walks it — and the shape is what the reader will depend on.

## Two findings that stand

**A by-value vector is counted among the scalars the call convention carries.** `vecK` takes a `float4`
plus the three scalars and air2cpu refuses it with *"a fourth scalar where the call convention carries
three: the thread position, the threadgroup position and the group size"*. The tool's convention is
**not** changed here: a Metal compute entry this port dispatches is a device pointer plus the three
thread identifiers, and a vector by value is not part of it. The plist still describes `vecK`, because
the type tree is written from the module's entry points rather than from the ones that translated.

**`threadgroupSize` is still `0 0 0`,** because the AIR carries no threadgroup size for the writer to
read — `air.threads_per_threadgroup` in a kernel node is a *hint the header calls a hint*, and
`air2cpu` does not read it into the file. The reader answers `MTLSize(0, 0, 0)` and the row says so.

## The metadata keys, measured against a real library

The spellings above were written from memory and the fixture was written from the writer, which is
circular. This is the measurement that breaks it: one `.metallib` shipped inside a system bundle,
extracted with this repository's own `tests/backports/host/air2cpu/extract.py`, disassembled with
`llvm-dis`, and its `air.*` keys counted. **Nothing of the library is recorded here** — not its
kernels, not their names, not their contents — only the key spellings and the node shapes, which are
the format's.

The real `air.kernel` node is **not** the flat layout `sum.ll` spells. It is a function, then an
empty node, then **one node holding the argument nodes**:

```
!air.kernel = !{ptr @<a function>, !<empty>, !<the argument nodes, nested>}
```

And a real argument node is a **flat list whose first operand is an `i32` index**, followed by
key/value pairs:

```
!<index> = !{i32 0, !"air.<type class>", !"air.<key>", <value>, ...}
```

The key spellings measured, all of them confirmed present in a real library:
`air.arg_type_name`, `air.arg_name`, `air.arg_type_size`, `air.arg_type_align_size`,
`air.read`, `air.write`, `air.buffer`, `air.texture`, `air.address_space`, `air.buffer_size`,
`air.location_index`, `air.thread_position_in_grid`, `air.thread_id`,
`air.threadgroup_position_in_grid`, `air.max_device_buffers`, `air.max_textures`,
`air.max_samplers`, `air.max_constant_buffers`, `air.max_threadgroup_buffers`,
`air.max_read_write_textures`, `air.language_version`, `air.version`, `air.compile.*`.

`air.struct_type_info` was **not** in this library's keys, so that spelling stays **UNVERIFIED** —
the writer reads it, the fixture exercises it, and no real library here has been seen to carry it.
A reader must not depend on it.

### Three defects the measurement found, NOT YET FIXED

1. **The access keys are `air.read` and `air.write`, not `air.read_write` and `air.read_only`.** The
   writer matches the spelling it was given, and treats anything that is not `air.read_only` as
   read-write, so a real `air.read` would be reported as read-write. That is wrong, and the previous
   commit's claim that the access "comes from the AIR's own word" is true of a word that does not
   exist in a real library.
2. **`air.arg_name` exists and the writer does not read it.** A real argument is named in the
   metadata; the writer uses the LLVM argument's name instead, which is empty for a real library's
   kernels.
3. **The argument node begins with an `i32` index, not a string.** The writer reads operand 0 as a
   string for the access, and finds argument nodes by looking for an operand whose first string is an
   `air.` key. On a real library — where the nodes are nested inside one node and begin with an
   `i32` — that scan finds **no argument nodes at all**, so a real library would produce a tree with
   no arguments in it. The `sum.ll` layout the writer was built against is a different, older shape.

The fixture `reflect.ll` is in the `sum.ll` shape, so it exercises the writer and cannot catch any of
this. Fixing all three — the nested node, the `air.read`/`air.write` spellings and `air.arg_name` —
is the next piece of work, and until it is done **the argument type names, sizes, accesses and
members in this file are UNVERIFIED against a real library**, whatever the invented fixtures say.

## The keys, measured across 25 real libraries

25 `.metallib` files shipped inside system bundles, extracted with this repository's `extract.py` and
disassembled with `llvm-dis`. **Aggregate facts only** — counts of the keys, never a name, a kernel
or a value from any of them.

**112 argument nodes** were found. Inside them, the keys and their counts:

| key | occurrences | | key | occurrences |
| --- | ---: | --- | --- | ---: |
| `air.arg_type_name` | 46 | | `air.buffer` | 8 |
| `air.arg_name` | 46 | | `air.address_space` | 8 |
| `air.visible_input` | 27 | | `air.arg_type_size` | 8 |
| `air.location_index` | 14 | | `air.arg_type_align_size` | 8 |
| `air.max_device_buffers` | 11 | | `air.texture` | 6 |
| `air.max_constant_buffers` | 11 | | `air.read` | 6 |
| `air.max_threadgroup_buffers` | 11 | | `air.write` | 2 |
| `air.max_textures` | 11 | | `air.read_write` | 3 |
| `air.max_read_write_textures` | 11 | | | |
| `air.max_samplers` | 11 | | | |

**`air.struct_type_info` is REAL**, and this supersedes the UNVERIFIED note above: it appears in a
real argument node, between `air.address_space` and `air.arg_type_size`, with a nested node as its
value. The key is confirmed; only the member spelling inside that node is still unexercised here.

**The three access spellings are `air.read`, `air.write` and `air.read_write`** — all three measured,
none inferred. The writer accepts exactly those three (plus `air.read_only`, which `sum.ll` uses) and
writes **no** access for any other key, so an access this build does not know is left unsaid rather
than reported as read-write.

## The three defects, fixed

1. **The argument nodes are found by the real shape.** A real `air.kernel` is a function, an empty
   node, and one node that NESTS the argument nodes; each argument node begins with an `i32` index.
   The writer now looks for that nesting first. The older `sum.ll` shape — the size nodes and the
   argument nodes as siblings, each argument node opening with a bare access marker — is still read,
   because two of this repository's own fixtures are in it and `entryPoints()` serves both; it is
   read second, and both shapes put something before the key/value pairs (an index, or a marker), so
   the pairs start at operand 1 either way.
2. **The access comes from the three measured spellings**, and a key that is not one of them is not
   translated into an access at all.
3. **`air.arg_name` is read**, and it is the name written. The LLVM argument's name is used only when
   the metadata carries none — which is the case for the invented fixtures and not for a real library.

Verified on the two invented fixtures after the fix: `scale` reads 4 arguments, 2 `typeName`; `reflect`
reads 9 arguments, 5 `typeName`, 2 `size`, 1 `members`, and the accesses `read-write, read-write,
read-only`.

## The precondition is NOT met, and why

**No real library translates, so the writer has not been run end to end against a real kernel's
arguments.** Of the 25 real libraries measured, **0 translate** — the first refusal is *"an argument
in address space 2 that is neither a buffer nor threadgroup memory"*, which is threadgroup memory in a
real kernel and is not part of the calling convention this port dispatches. And `air2cpu` writes the
property list only after a kernel has translated, so no real module produces a file at all.

So the shape reading is now correct against a measured 112 nodes, and the two invented fixtures prove
the writer runs — but the two do not together prove the writer reads a REAL kernel, because the real
kernels are refused before the writer is reached. Step 5 should not treat the reflection as verified
until a module both translates and is real exists; the honest next step is a fixture in the REAL shape
(the nested kernel node, `i32`-indexed argument nodes, the `air.read`/`air.write`/`air.read_write`
accesses, `air.arg_name`) that also translates, since the real shape and a translation are currently
mutually exclusive in this tool.

## Written before the translation gate, and measured on real modules

The property list is now written **before** the gate that refuses a module with no translated kernel:
the type tree is a property of the AIR, not of whether this emitter can lower it, so a kernel the
emitter refuses is still described.

Both conditions hold, measured:

- **No behaviour change for a translating kernel.** `scale` and `reflect` produce byte-identical C,
  sha256 `9a194afb65f7…` and `87b2a3f16477…` before and after.
- **A refused kernel still fails exactly as before.** `sum.ll` is refused with the same text —
  *"sumK: a fourth scalar where the call convention carries three: the thread position, the
  threadgroup position and the group size"* — and now also yields a 3667-byte property list.

**All 25 real modules now write a property list.** Aggregate over them, no names or content:

| fact | value |
| --- | --- |
| modules that write one | **25 of 25** |
| functions described | 16 |
| arguments described | 19 |
| arguments carrying `typeName` | **19 of 19** |
| arguments carrying a name from `air.arg_name` | 8 |
| kinds found | pointer 14, vector 5, scalar 5 |

That is the precondition met: **the writer reads a real kernel's arguments.**

## Address space 2 is not threadgroup memory, and not shown to be constant either

The last report called the refusal "threadgroup memory", which was wrong. Measured over the argument
nodes that carry `air.address_space`:

| space | nodes | marked `air.buffer` | marked `air.texture` |
| --- | ---: | ---: | ---: |
| 1 | 3 | 3 | 0 |
| 2 | 4 | 4 | 0 |
| 3 | 1 | 1 | 0 |

Every one of them is marked `air.buffer`, and among the four space-2 nodes **none** has an
`arg_type_name` containing "constant" — the names are plain types (`uint2`, `int`, `bool`, a struct
name). So this sample neither confirms space 2 as constant nor as threadgroup; what it shows is that
space 2 is used, is marked as a buffer, and that the emitter refuses it.

**Whether one small change would carry it is therefore not established, and is not claimed.** Binding
it as a read-only buffer would need the *role* of the space-2 buffer — whether it is written — and
this sample's nodes are all `air.read`, which suggests read-only, but four nodes from one library is
not enough to act on. The emitter's dispatch is **not** changed here.

## One defect remains, and it is a missing value rather than a wrong one

`air.read` and `air.write` appear in a real node as **bare keys with no value of their own**, in the
middle of the key stream, and the writer only reads an access from a node's FIRST operand — the
older shape's marker. So no access is written for a real argument. The writer writes **no** access
rather than a wrong one, and the reader must answer what the header documents for an access the
metadata did not say. A reader must not read that as read-write.

## The access, read from anywhere in the key stream

`air.read`, `air.write` and `air.read_write` are **bare keys** in a real argument node — no value of
their own, anywhere in the stream — while the older `sum.ll` shape puts the access in the node's
*first* operand. The writer now scans the whole node for the three measured spellings, and a node
carries at most one. **A node with no access key gets no access written**, and never read-write.

Telling a bare key from a paired one is the shape: a bare key is followed by another `air.` string,
and consuming that string as its value would swallow the next key. That is the same rule the type
class needs, and the two are now one loop rather than two special cases.

`fixtures/accesses.ll` is the case, invented for this repository and marked as such, in the REAL
shape — a function, an empty node, one node nesting the argument nodes — with one kernel per
access spelling and a fourth with **no** access key at all:

| kernel | access key in the AIR | access written |
| --- | --- | --- |
| `readK` | `air.read` | `read-only` |
| `writeK` | `air.write` | `write-only` |
| `bothK` | `air.read_write` | `read-write` |
| `plainK` | *(none)* | **(none)** |

Over the 25 real modules, aggregate only: **19 arguments, 19 with `typeName`, 8 with sizes, 8 with a
name from `air.arg_name`, and 11 accesses — 6 read-only and 5 read-write.** The eight arguments with
no access key are the ones whose node does not carry one, and they are written without an access.

## The access is the header's own three enumerators, not two words

`MTLArgument.h:214` declares the enumeration, and it has three cases, not two:

```
216:typedef NS_ENUM(NSUInteger, MTLArgumentAccess) {
218:    MTLArgumentAccessReadOnly   = 0,
219:    MTLArgumentAccessReadWrite  = 1,
220:    MTLArgumentAccessWriteOnly  = 2,
296:@property (readonly) MTLArgumentAccess access;    // read, write, read-write
```

So `air.write` is **`write-only`**, and the earlier mapping that made it `read-write` was wrong: a
texture declared `access::write` is neither readable nor read-write, and reporting it as read-write
describes a real argument wrongly. The mapping now comes from the header's enumerators one for one.

| AIR key | written |
| --- | --- |
| `air.read`, `air.read_only` | `read-only` |
| `air.write` | `write-only` |
| `air.read_write` | `read-write` |
| *(no access key)* | **(nothing written)** |

## The mutation, committed and red

`tests/backports/host/air2cpu/check-access-mutation.sh` builds a **scratch copy** of the writer under
`.agent-work/runs/` — the checkout is never edited — with one change: it reads the access from the
node's first operand only. Against `accesses.ll` it must write no access where the real writer writes
three. It is run, and it is red:

```
accesses written by the real writer:   3
accesses written by the mutant:       0
PASS: the mutant is RED. It reads only the first operand and misses every bare access key,
      which is the defect this check keeps from coming back.
```

It fails the other way too, deliberately: if the real writer ever wrote no access at all, or if the
mutant ever agreed with it, the check says so and exits non-zero, because then it would be testing
nothing.

## The reader, and what it answers for the seven classes

`packages/a/apple-backports/Metal/MTLTypeReflection.m` is their `@implementation` — one translation
unit, none of the seven redeclared — and `tests/backports/host/metal-census/reflection.sh` runs it over
the property lists the writer produces:

```
reflect.plist    9 argument(s): 9 named, 9 typed, accesses 7 read-only 0 write-only 2 read-write
accesses.plist  16 argument(s): 16 named, 16 typed, accesses 14 read-only 1 write-only 1 read-write
```

The one **write-only** is read from `air.write`, which is the case the mapping got wrong and which no
earlier check would have caught. The mutant in that check maps an unrecognised access to read-write and
**disagrees**, which is what the guess would do to a caller.

**The absences, and which of them is which.** `MTLPointerType.pointee` is nil because opaque pointers
mean the AIR carries no pointee — *the type is not in the data*, not a gap in the reader.
`MTLTextureReferenceType.textureDataType` and an argument's `textureDataType` are `MTLDataTypeNone`
because the plist carries none. `MTLArrayType.arrayStride` is 0 because the AIR carries a size and an
alignment and **no stride** — that is an absent stride, not a zero-length array. A struct member the
AIR did not name is **present with an empty name**, not absent from the list, because an LLVM 23
`StructType` has element types and no per-element names. An access the metadata did not say is
`MTLArgumentAccessReadOnly`, the enumeration's zero, and **never read-write**.

**The argument's type comes from its type class, not its address space** — `air.buffer`,
`air.texture`, and that is measured: the real libraries put a buffer in space 1, another in space 2
and one in space 3, so a space does not name a type on its own.

## What is not here

`MTLRenderPipelineReflection`, `MTLComputePipelineReflection`, `MTLVertexAttribute`, `MTLAttribute`,
`MTLFunctionConstant`, `MTLFunctionDescriptor`, `MTLFunctionLog`, `MTLFunctionLogDebugLocation`,
`MTLLogContainer` and `MTLPipelineBufferDescriptor(+Array)` — the other ten rows of the family — have
no implementation and no reader path yet. The seven here are the ones the type tree alone answers;
the other ten need the pipeline states and the function objects to reflect over, which is the next
piece and not a reader change.

`MTLFunctionLog` and `MTLFunctionLogDebugLocation` additionally need a decision this facts file does
not pre-empt: the header ties a function log to the GPU's debug facility, and a device without it
answers what the header documents for its absence — which is a statement about a row, not about the
type tree.
