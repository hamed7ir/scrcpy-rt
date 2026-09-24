# UPSTREAM — what this repository builds, and whose work it is

`scrcpy-rt` is **build infrastructure for scrcpy**. It is not a fork of scrcpy and it contains
no scrcpy source. [`scripts/fetch-deps.sh`](scripts/fetch-deps.sh) reconstructs every component
below from its own project, **verifies each one against the pin recorded here — a sha256 for
the tarball, a commit SHA for the git components — and refuses to continue on a mismatch**.

## Components

| component | upstream | version | pinned by | licence | patches from here |
|---|---|---|---|---|---|
| **scrcpy** (client) | [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) | **v4.1** | commit SHA | Apache-2.0 | **0** |
| **SDL** | [libsdl-org/SDL](https://github.com/libsdl-org/SDL) | **3.2.14** | commit SHA | Zlib | **0** |
| **scrcpy-server** | [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) | **v4.1** | file sha256 | Apache-2.0 | **0** |
| FFmpeg | via **`ffmpeg-rt`** (this project) | 8.1.2 | — | LGPL-2.1-or-later | 0 |
| `adb.exe` | via **`adb-rt`** (this project) | platform-tools 35.0.2 | — | Apache-2.0 (+ libusb LGPL) | see that repo |

**Total patches from this repository: 0.** `patches/` is empty in both directions — scrcpy's
71 translation units compile as they ship, and SDL 3.2.14 builds for ARM32 as it ships. Under
Apache-2.0 §4(b), which requires a distributor to state whether the files were changed:
**they were not.** What changed is the build, not the source.

### The exact pins

**scrcpy** — `https://github.com/Genymobile/scrcpy.git`, tag `v4.1`
commit `2926c06c5dc3064ae6d8db706f1a98a37cfcf3f0`

**SDL** — `https://github.com/libsdl-org/SDL.git`, tag `release-3.2.14`
commit `8d604353a53853fa56d1bdce0363535605ca868f`
`release-3.2.14` is a *lightweight* tag, so that is the commit itself.

**scrcpy-server** — the upstream **release asset**, redistributed byte-identical:
`https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-server-v4.1`
sha256 `deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae`
It is not built here: building it needs a JDK and the Android SDK, and scrcpy refuses to run
when client and server versions differ.

## How the pins are verified

`scripts/fetch-deps.sh` compares each git checkout's `HEAD` to the commit SHA above and each
downloaded file to its sha256, and stops on any mismatch rather than building something other
than what is described here. Git components are cloned with `core.autocrlf=false`, so the tree
you get is byte-identical to the one these binaries were built from rather than merely
content-identical.

## What in this repository is not upstream's

The entire port, and it is four headers and two source files:

| file | what it is |
|---|---|
| `cross/msvc-posix-compat/{sys/types.h, sys/stat.h, unistd.h, getopt.h}` | shim headers. Each pulls the Windows SDK's own header with `#include_next` and adds only what the MSVC UCRT lacks — chiefly `ssize_t`, which scrcpy uses at 69 sites across 27 files |
| `cross/getopt_long.c` | `getopt` / `getopt_long` over Win32, written here — not derived from glibc (LGPL) or any BSD implementation |
| `cross/scrcpy-config.h` | the `config.h` scrcpy's Meson build would otherwise generate |
| `cross/*.cmake`, `cross/*.rsp`, `scripts/*.sh`, `config.sh` | build infrastructure |

None of it is a change to scrcpy or SDL. It carries this repository's licence and adds no
third-party licence obligation.

See [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for the licence obligations — including
the one that needs care, libusb's LGPL inside the bundled `adb.exe` — and [`LICENSE`](LICENSE)
for scrcpy's own licence text, reproduced verbatim with its copyright lines.

## Toolchain — used, not redistributed

**rt2** — **LLVM 23.1.1 plus a small set of patches** this target still needs upstream, built
as its own project and published at **<https://github.com/hamed7ir/llvm-rt1>**. Base: `llvmorg-23.1.1`, whose source tarball
sha256 `ebe9be46fe8756d58c5b198ffad0fa2a766257add81a4dc52179bfacc7888ee6` was verified before
that build. Licence: **Apache-2.0 WITH LLVM-exception**, and because it is a *modified* LLVM,
its own repository is where the modified source lives — not here.

The binaries these repos were built with are identified by sha256 in `config.sh`, not by version
string alone, because an unrelated LLVM 18.1.8 lives one character away on the original build
machine and would build everything silently and wrongly.

MSVC toolset 14.44.35207 and Windows SDK 10.0.19041.0: Microsoft, under their own terms.
**Nothing in this paragraph is redistributed here.**

## Reference binaries that are NOT here

Two 2013 third-party ARM32 prebuilts were used as instruments during the port — an old `adb`
and an old FFmpeg 2.1, both from `files.open-rt.party/Software/`. Their licence and provenance
are unknown, so they are not redistributed in this repository or in any release from it.
