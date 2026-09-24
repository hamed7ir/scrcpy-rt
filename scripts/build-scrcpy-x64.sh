#!/bin/sh
# An x64 TWIN of the scrcpy client, so the "Could not list ADB devices" failure can be
# reproduced and fixed on the dev box instead of on the Surface.
#
# NOT A SHIPPING TARGET. Same sources, same shims, same config header, same MSVC ABI --
# only the architecture differs. If the bug reproduces here it is in scrcpy's Windows
# pipe/spawn path under the MSVC ABI; if it does not, it is specific to ARM32 or to RT 8.1,
# and that is itself the finding.
#
# FFmpeg: linked against import libs generated from the OFFICIAL scrcpy-win64-v4.1 DLLs,
# which carry the same soversions as ffmpeg-rt (avcodec-62, avformat-62, avutil-60,
# swresample-6), so the ABI matches. ffmpeg-rt itself is ARM32-only.
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
FFINC=$FFMPEG_RT/dist/shared/include
FFLIB=$ROOT/build/ffmpeg-x64-implib
SDL=$ROOT/build/sdl3-x64-prefix
OUT=$ROOT/build/scrcpy-x64

V=$("$RT2/clang-cl.exe" --version | head -1)
case "$V" in *23.1.1-rt2*) echo "GATE OK: $V" ;; *) echo "GATE FAIL: $V"; exit 1 ;; esac

rm -rf "$OUT"; mkdir -p "$OUT/obj"
cp "$ROOT/cross/scrcpy-config.h" "$OUT/config.h"

RSP="$OUT/pin.rsp"
{
  echo '--target=x86_64-pc-windows-msvc'
  echo "-vctoolsdir \"$VC\""
  echo "-winsdkdir \"$SDK\""
  echo "-winsdkversion $SDKVER"
  echo '/MT'
  # app/meson.build:7 sets b_ndebug=if-release, so NO shipping scrcpy has assertions live.
  # Omitting these two cost a device package: an assert() in sc_cond_timedwait
  # (util/thread.c:166) aborted the process on a benign Windows timer-granularity race
  # that upstream never sees. /O2 is the other half of --buildtype=release.
  echo '/O2 /DNDEBUG'
  echo '-ferror-limit=0'
  echo '/D_CRT_SECURE_NO_WARNINGS /D_CRT_NONSTDC_NO_WARNINGS'
  echo '/D_GNU_SOURCE /D_POSIX_C_SOURCE=200809L /D_XOPEN_SOURCE=700'
  echo '/D_WIN32_WINNT=0x0600 /DWINVER=0x0600'
  echo "-I\"$(cygpath -m "$ROOT/cross/msvc-posix-compat")\""
  echo "-I\"$(cygpath -m "$OUT")\""
  echo "-I\"$(cygpath -m "$APP/src")\""
  echo "-I\"$(cygpath -m "$FFINC")\""
  echo "-I\"$(cygpath -m "$SDL/include")\""
} > "$RSP"

SRCS=$(sed -n '/^src = \[/,/^]/p' "$APP/meson.build" | grep -o "'src/[^']*\.c'" | tr -d "'")
WINSRCS="src/util/command.c src/sys/win/file.c src/sys/win/process.c"
EXPECTED=$(printf '%s\n' $SRCS $WINSRCS | wc -l)

PASS=0; FAIL=0; ATTEMPTED=0
for s in $SRCS $WINSRCS; do
  ATTEMPTED=$((ATTEMPTED+1))
  o=$(echo "$s" | tr '/' '_' | sed 's/\.c$/.obj/')
  if "$RT2/clang-cl.exe" "@$(cygpath -w "$RSP")" /c "$(cygpath -w "$APP/$s")" \
       "/Fo$(cygpath -w "$OUT/obj/$o")" > "$OUT/obj/${o%.obj}.log" 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "  FAILED: $s"; grep -m3 error "$OUT/obj/${o%.obj}.log"
  fi
done
ATTEMPTED=$((ATTEMPTED+1))
if "$RT2/clang-cl.exe" "@$(cygpath -w "$RSP")" /c "$(cygpath -w "$ROOT/cross/getopt_long.c")" \
     "/Fo$(cygpath -w "$OUT/obj/cross_getopt_long.obj")" > "$OUT/obj/getopt_long.log" 2>&1; then
  PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAILED: cross/getopt_long.c"; fi

echo "compiled $PASS / attempted $ATTEMPTED (expected $((EXPECTED+1))), failed $FAIL"
[ "$ATTEMPTED" -eq "$((EXPECTED+1))" ] || { echo "attempted != expected"; exit 2; }
[ "$FAIL" -eq 0 ] || exit 1

"$RT2/llvm-rc.exe" /FO "$(cygpath -w "$OUT/scrcpy.res")" \
    "$(cygpath -w "$APP/scrcpy-windows.rc")" > "$OUT/rc.log" 2>&1 || { echo "RC FAILED"; exit 1; }

LRSP="$OUT/link.rsp"
{
  echo '/SUBSYSTEM:CONSOLE'
  echo '/MACHINE:X64'
  echo "/OUT:$(cygpath -w "$OUT/scrcpy.exe")"
  echo '/DEFAULTLIB:libcmt.lib /DEFAULTLIB:oldnames.lib'
  echo "/LIBPATH:\"$(cygpath -w "$VC/lib/x64")\""
  echo "/LIBPATH:\"$(cygpath -w "$SDK/Lib/$SDKVER/ucrt/x64")\""
  echo "/LIBPATH:\"$(cygpath -w "$SDK/Lib/$SDKVER/um/x64")\""
  for o in "$OUT"/obj/*.obj; do cygpath -w "$o"; done
  cygpath -w "$OUT/scrcpy.res"
  cygpath -w "$SDL/lib/SDL3-static.lib"
  for l in avformat avcodec avutil swresample; do cygpath -w "$FFLIB/$l.lib"; done
  echo 'ws2_32.lib'
  for l in user32 gdi32 winmm imm32 ole32 oleaut32 advapi32 shell32 setupapi version uuid kernel32; do
    echo "$l.lib"
  done
} > "$LRSP"

"$RT2/lld-link.exe" "@$(cygpath -w "$LRSP")" > "$OUT/link.log" 2>&1 \
  || { echo "LINK FAILED"; grep -m20 -iE "error|unresolved" "$OUT/link.log"; exit 1; }
echo "scrcpy.exe (x64): $(stat -c%s "$OUT/scrcpy.exe") bytes"

# put the runtime next to it so it can actually be executed here
for d in avcodec-62 avformat-62 avutil-60 swresample-6; do
  cp "$SCRCPY_WIN64_RELEASE/$d.dll" "$OUT/"
done
cp "$SCRCPY_WIN64_RELEASE/scrcpy-server" "$OUT/" 2>/dev/null
echo "runtime staged in $OUT"
