# scrcpy-rt

> **Upstream: [scrcpy](https://github.com/Genymobile/scrcpy) by Genymobile, tag `v4.1`. Patches applied here: 0.**
> Build infrastructure only; no upstream source is included. `scripts/fetch-deps.sh` verifies
> every pin. See [`UPSTREAM.md`](UPSTREAM.md).

scrcpy 4.1 for 32-bit ARM Windows (`armv7-pc-windows-msvc`). It mirrors and controls an Android
phone from **Windows RT 8.1**, **over USB and over Wi-Fi**.

Tested on a Surface RT (Tegra 3) with three phones from three vendors: **Volla Phone Quintus**,
**Google Pixel 9 Pro XL** and **BlackBerry Priv**. Video, audio, mouse, keyboard, clipboard and
virtual display work.

## Run

```
scrcpy --new-display=1366x768 --render-driver=direct3d --video-codec=h264 --max-fps=30 --video-bit-rate=2M
```

**`--render-driver=direct3d` is required.** Without it the window is black.

- USB: `RUN-SCRCPY.cmd`
- Wi-Fi: `RUN-SCRCPY-WIFI.cmd`, then type the IP:PORT from the phone's Wireless debugging screen.

## Release contents

`scrcpy.exe`, four `ffmpeg-rt` DLLs, `adb.exe` from `adb-rt`, `scrcpy-server` and the
launchers. SDL3 is linked statically.

## Limitations

- No window icon.
- The virtual display goes black when the phone locks. `--stay-awake` prevents it.
- On Wi-Fi the port must be typed; there is no automatic discovery.
- No hardware decoding.
- `--record` supports mp4 and matroska only.

## Build

Set these in [`config.sh`](config.sh) or export them. The same names work in all three `-rt` repos.

| variable | value |
|---|---|
| `RT2` | LLVM 23.1.1-rt2 `bin` directory |
| `VCTOOLS` | MSVC 14.44.35207 (14.51 dropped ARM32) |
| `WINSDK`, `WINSDKVER` | Windows SDK 10.0.19041.0 (the last with ARM32 libraries) |
| `CMAKE`, `NINJA` | native Windows builds, not MSYS2's |

From an MSYS2 shell:

```sh
sh scripts/fetch-deps.sh
sh scripts/build-sdl3.sh
sh scripts/catalogue-scrcpy.sh
sh scripts/link-scrcpy.sh
```

`cross/rt2-windows-arm.txt` is a Meson cross file with fixed paths; the build scripts do not use
it. Absolute build paths are embedded in the binaries.

## Licence

**Copyright (c) 2026 hamed7ir** for the files this repository adds, under Apache-2.0 —
[`LICENSE`](LICENSE).

scrcpy is Apache-2.0 and is not modified. SDL3 is zlib, linked statically. The FFmpeg DLLs are
LGPL-2.1-or-later, linked dynamically. The bundled `adb.exe` links libusb (LGPL-2.1-or-later)
statically. See [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

Two 2013 third-party ARM32 binaries from `files.open-rt.party` were used as test instruments
during the port. They are not redistributed.

## Related

- [`UPSTREAM.md`](UPSTREAM.md) — components, pins, licences, patch counts
- `ffmpeg-rt` and `adb-rt` — required
- [rt2](https://github.com/hamed7ir/llvm-rt1) — the toolchain
