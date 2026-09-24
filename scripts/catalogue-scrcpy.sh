#!/bin/sh
# BATCH-SCRCPY-2 section 4.2: the hand-rolled build, first pass -- COMPILE EVERYTHING AND
# CATALOGUE. Do not fix errors one at a time and lose the inventory.
#
# Every source is compiled INDEPENDENTLY with -ferror-limit=0 and the script keeps going, so one
# run yields the complete blocker list instead of the first blocker. This is the adb-rt method;
# there it took the count from 0 clean to 31 clean in one pass.
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

rm -rf "$OUT"; mkdir -p "$OUT/obj"
cp "$ROOT/cross/scrcpy-config.h" "$OUT/config.h"

RSP="$OUT/pin.rsp"
{
  echo '--target=armv7-pc-windows-msvc'
  echo "-vctoolsdir \"$VC\""
  echo "-winsdkdir \"$SDK\""
  echo "-winsdkversion $SDKVER"
  echo '/MT'                       # Windows RT has no debug CRT; /MT removes the UCRT
                                   # redistributable question on an 8.1-era OS
  # app/meson.build:7 sets b_ndebug=if-release, so NO shipping scrcpy has assertions live.
  # Omitting these two cost a device package: an assert() in sc_cond_timedwait
  # (util/thread.c:166) aborted the process on a benign Windows timer-granularity race
  # that upstream never sees. /O2 is the other half of --buildtype=release.
  echo '/O2 /DNDEBUG'
  echo '-ferror-limit=0'           # catalogue, do not stop at 20
  echo '/D_CRT_SECURE_NO_WARNINGS /D_CRT_NONSTDC_NO_WARNINGS'
  # app/meson.build:70-88 -- reproduced faithfully. The three POSIX feature-test macros are
  # inert under the UCRT (its sys/types.h has no #if on them, read to confirm) but they are
  # what meson passes, so they are what we pass.
  echo '/D_GNU_SOURCE /D_POSIX_C_SOURCE=200809L /D_XOPEN_SOURCE=700'
  echo '/D_WIN32_WINNT=0x0600 /DWINVER=0x0600'
  # ⚠ ORDER MATTERS. The shim directory must precede the SDK so that our sys/types.h is found
  # first and its #include_next reaches the SDK's. Reverse these and ssize_t vanishes again.
  echo "-I\"$(cygpath -m "$ROOT/cross/msvc-posix-compat")\""
  echo "-I\"$(cygpath -m "$OUT")\""            # config.h
  echo "-I\"$(cygpath -m "$APP/src")\""        # meson: include_directories('src')
  echo "-I\"$(cygpath -m "$FFM/include")\""
  echo "-I\"$(cygpath -m "$SDL/include")\""
} > "$RSP"

# ---- the source list, read out of app/meson.build rather than retyped ----------------------
#  base src[] + the windows branch (app/meson.build:79-90). v4l2 and usb are off, so
#  src/v4l2_sink.c and src/usb/*.c are excluded -- as meson would.
SRCS=$(sed -n '/^src = \[/,/^]/p' "$APP/meson.build" | grep -o "'src/[^']*\.c'" | tr -d "'")
WINSRCS="src/util/command.c src/sys/win/file.c src/sys/win/process.c"
EXPECTED=$(printf '%s\n' $SRCS $WINSRCS | wc -l)

echo "scrcpy sources from meson.build : $(printf '%s\n' $SRCS | wc -l) base + 3 windows = $EXPECTED"
echo "plus cross/getopt_long.c        : 1"
echo

PASS=0; FAIL=0; ATTEMPTED=0
: > "$OUT/failures.txt"
for s in $SRCS $WINSRCS; do
  ATTEMPTED=$((ATTEMPTED+1))
  o=$(echo "$s" | tr '/' '_' | sed 's/\.c$/.obj/')
  log="$OUT/obj/${o%.obj}.log"
  if "$RT2/clang-cl.exe" "@$(cygpath -w "$RSP")" /c "$(cygpath -w "$APP/$s")" \
       "/Fo$(cygpath -w "$OUT/obj/$o")" > "$log" 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "=== $s ===" >> "$OUT/failures.txt"
    grep -m6 -E "error" "$log" >> "$OUT/failures.txt"
    echo >> "$OUT/failures.txt"
  fi
done

# our own shim TU
ATTEMPTED=$((ATTEMPTED+1))
if "$RT2/clang-cl.exe" "@$(cygpath -w "$RSP")" /c "$(cygpath -w "$ROOT/cross/getopt_long.c")" \
     "/Fo$(cygpath -w "$OUT/obj/cross_getopt_long.obj")" > "$OUT/obj/getopt_long.log" 2>&1; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  echo "=== cross/getopt_long.c ===" >> "$OUT/failures.txt"
  grep -m6 -E "error" "$OUT/obj/getopt_long.log" >> "$OUT/failures.txt"
fi

echo "--- denominator ---"
echo "  expected  : $((EXPECTED+1))"
echo "  attempted : $ATTEMPTED"
echo "  compiled  : $PASS"
echo "  failed    : $FAIL"
[ "$ATTEMPTED" -eq "$((EXPECTED+1))" ] || { echo "  !! attempted != expected -- the sweep is not evidence"; exit 2; }
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "--- distinct error texts, most common first ---"
  grep -hoE "error[: ].*" "$OUT"/obj/*.log 2>/dev/null \
    | sed 's/.*error[: ]*//' | sed "s/'[^']*'/'X'/g" | sort | uniq -c | sort -rn | head -20
  echo
  echo "full list: $OUT/failures.txt"
fi
