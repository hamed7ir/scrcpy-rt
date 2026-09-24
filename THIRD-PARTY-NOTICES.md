# THIRD-PARTY NOTICES — scrcpy-rt

`scrcpy-rt` is build infrastructure. It **vendors no third-party source**: nothing under
`deps/` is committed here. `scripts/fetch-deps.sh` reconstructs it from pinned, public refs and
refuses to continue if a pin does not match.

## Components of the build

| component | version / pin | licence | linkage |
|---|---|---|---|
| scrcpy (client) | **4.1**, commit `2926c06c5dc3064ae6d8db706f1a98a37cfcf3f0` | **Apache-2.0** | compiled from source into `scrcpy.exe` |
| SDL | **3.2.14** (`release-3.2.14`) | **zlib licence** | **static** — there is no `SDL3.dll` |
| FFmpeg | 8.1.2, via `ffmpeg-rt` | **LGPL-2.1-or-later** | **dynamic** — four of its five DLLs, each replaceable |
| `adb.exe` | AOSP platform-tools 35.0.2, via `adb-rt` | Apache-2.0, **and see the libusb note below** | separate executable |
| `scrcpy-server` | the **v4.1 release asset**, sha256 `deacb991…50cae` | Apache-2.0 | redistributed byte-identical |
| `scrcpy.png`, `disconnected.png` | scrcpy 4.1 `app/data/` | Apache-2.0 | redistributed byte-identical |

## Source patches: zero

`patches/` is empty, in both directions:

- **scrcpy 4.1** — 71/71 translation units compile as-is. The port is four shim headers on the
  include path plus one `getopt_long.c`, all under `cross/`.
- **SDL 3.2.14** — builds for ARM32 as-is against Windows SDK 10.0.19041.0.

Saying so is a point in the port's favour and it is also the licence answer: under Apache-2.0
§4(b) a distributor must state whether the files were modified. **They were not.** What changed
is the build, not the source.

## Files added by this project

| file | what it is |
|---|---|
| `cross/msvc-posix-compat/{sys/types.h, sys/stat.h, unistd.h, getopt.h}` | four shim headers. Each pulls the SDK's own header with `#include_next` and adds only what the UCRT lacks — chiefly `ssize_t`, which scrcpy uses at 69 sites across 27 files |
| `cross/getopt_long.c` | `getopt` / `getopt_long` over Win32 |
| `cross/scrcpy-config.h` | the `config.h` that scrcpy's meson build would otherwise generate |
| `cross/*.cmake`, `cross/*.rsp`, `scripts/*.sh`, `config.sh` | build infrastructure |

All of it was **written for this project**. It is not derived from, and contains no code copied
from, mingw-w64, Cygwin, glibc (LGPL) or any BSD `getopt` implementation — `cross/getopt_long.c`
says so at its head, and it deliberately omits the two GNU behaviours (argv permutation,
`getopt_long_only`) that scrcpy never reaches. That was a deliberate choice: vendoring an
existing single-header implementation would have been quicker and would have attached another
licence to a repository meant for publication, for a few hundred lines that are straightforward
to write directly against Win32.

These files carry this repository's licence and add **no third-party licence obligation**.

## ⚠ libusb is LGPL-2.1-or-later and is linked STATICALLY into the bundled `adb.exe`

A release of `scrcpy-rt` ships `adb.exe` from `adb-rt`, and that binary contains libusb 1.0.28
as a **static** library. Static linking does not remove the LGPL's relinking obligation — it is
met here by publishing **the complete corresponding source and the build scripts**, so anyone
can rebuild `adb.exe` from the same pinned sources with a modified libusb: `adb-rt` commits its
`scripts/`, its `cross/` shims and all three patches, and `adb-rt/scripts/fetch-deps.sh` pins
every upstream component by sha256 or commit SHA. See `adb-rt/THIRD-PARTY-NOTICES.md`.

The FFmpeg DLLs carry the same licence family but are linked **dynamically**, which is the
easier case: replace the DLL.

## Toolchain — used, not redistributed

| | |
|---|---|
| **rt2** — LLVM 23.1.1-rt2 | Apache-2.0 WITH LLVM-exception |
| MSVC toolset 14.44.35207, Windows SDK 10.0.19041.0 | Microsoft, used under their own terms |

## Reference binaries deliberately NOT redistributed

Two 2013 third-party ARM32 prebuilts were used as instruments during this port — an old `adb`
and an old FFmpeg 2.1, both from `files.open-rt.party/Software/`. They answered "can a Surface
RT drive a modern phone?" and "can a Tegra 3 decode H.264 at all?" before any of this was
built. Their licence and provenance are unknown, so they are **not** in this repository and not
in any release from it.
