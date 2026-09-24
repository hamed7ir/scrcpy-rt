#!/bin/sh
# BATCH-SCRCPY-2 section 4.2/4.3: link the hand-rolled scrcpy client for ARM32.
set -u
export MSYS2_ARG_CONV_EXCL='*'
export TMP="${TMP:-${TEMP:-/tmp}}" TEMP="$TMP"

# ---- configuration -------------------------------------------------------------------------
# Every absolute path lives in config.sh at the repo root. The root is derived from THIS
# script's own location, so a clone builds wherever it is placed.
SC_SELF=$0
SC_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$SC_ROOT/config.sh"
sc_check_config || exit 1

VC=$VCTOOLS
SDK=$WINSDK
SDKVER=$WINSDKVER
ROOT=$SC_ROOT
APP=$ROOT/deps/scrcpy/app
FFM=$FFMPEG_RT/dist/shared
SDL=$ROOT/build/sdl3-arm32-prefix
OUT=$ROOT/build/scrcpy-arm32

V=$("$RT2/clang-cl.exe" --version | head -1)
case "$V" in *23.1.1-rt2*) echo "GATE OK: $V" ;; *) echo "GATE FAIL: $V"; exit 1 ;; esac

# ---- the resource, with an EXPLICIT target ------------------------------------------------
# llvm-windres/llvm-rc default their output COFF machine to the HOST and will silently emit an
# AMD64 .res into an ARM32 link (arm32-windows-toolchain trap #2). Say ARM outright.
"$RT2/llvm-rc.exe" /FO "$(cygpath -w "$OUT/scrcpy.res")" \
    "$(cygpath -w "$APP/scrcpy-windows.rc")" > "$OUT/rc.log" 2>&1 \
    || { echo "RC FAILED"; tail -5 "$OUT/rc.log"; exit 1; }
echo "resource: $(stat -c%s "$OUT/scrcpy.res") bytes"

LRSP="$OUT/link.rsp"
{
  echo '/SUBSYSTEM:CONSOLE'
  echo '/MACHINE:ARM'
  echo "/OUT:$(cygpath -w "$OUT/scrcpy.exe")"
  echo '/DEFAULTLIB:libcmt.lib /DEFAULTLIB:oldnames.lib'
  echo "/LIBPATH:\"$(cygpath -w "$VC/lib/arm")\""
  echo "/LIBPATH:\"$(cygpath -w "$SDK/Lib/$SDKVER/ucrt/arm")\""
  echo "/LIBPATH:\"$(cygpath -w "$SDK/Lib/$SDKVER/um/arm")\""
  for o in "$OUT"/obj/*.obj; do cygpath -w "$o"; done
  cygpath -w "$OUT/scrcpy.res"
  # SDL3, static
  cygpath -w "$SDL/lib/SDL3-static.lib"
  # ffmpeg-rt import libraries (the DLLs ship alongside scrcpy.exe).
  # app/meson.build:126-129 links exactly these four; NOT swscale, NOT avfilter, NOT avdevice.
  for l in avformat avcodec avutil swresample; do cygpath -w "$FFM/bin/$l.lib"; done
  # ws2_32 is app/meson.build:142. mingw32 (line 141) is deliberately absent: it supplies
  # mingw's CRT startup glue and has no meaning under /MT + UCRT.
  echo 'ws2_32.lib'
  # what a static SDL3 pulls in on Windows
  for l in user32 gdi32 winmm imm32 ole32 oleaut32 advapi32 shell32 setupapi version uuid kernel32; do
    echo "$l.lib"
  done
} > "$LRSP"

"$RT2/lld-link.exe" "@$(cygpath -w "$LRSP")" > "$OUT/link.log" 2>&1 \
  || { echo "LINK FAILED"; grep -m25 -iE "error|unresolved" "$OUT/link.log"; exit 1; }

echo "scrcpy.exe: $(stat -c%s "$OUT/scrcpy.exe") bytes"
