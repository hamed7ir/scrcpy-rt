#!/bin/sh
# BATCH-SCRCPY-2 section 2.3: build sdlcanary for ARM32 (ships) and x64 (runs here first).
#
# The x64 twin exists because BATCH-ADB-6 shipped an instrument whose new code had never
# executed and it cost a device trip. The canary is the gate for this entire batch; an
# untested gate is worse than no gate.
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

V=$("$RT2/clang-cl.exe" --version | head -1)
case "$V" in *23.1.1-rt2*) echo "GATE OK: $V" ;; *) echo "GATE FAIL: $V"; exit 1 ;; esac

build() {  # build <tag> <triple> <machine> <libsubdir>
  tag="$1"; triple="$2"; mach="$3"; libdir="$4"
  PFX=$ROOT/build/sdl3-$tag-prefix
  OUT=$ROOT/build/canary-$tag
  [ -f "$PFX/lib/SDL3-static.lib" ] || { echo "   $tag: SDL3 not built -- run build-sdl3.sh"; return 1; }
  rm -rf "$OUT"; mkdir -p "$OUT"

  RSP="$OUT/pin.rsp"
  {
    echo "--target=$triple"
    echo "-vctoolsdir \"$VC\""
    echo "-winsdkdir \"$SDK\""
    echo "-winsdkversion $SDKVER"
    echo '/MT'                      # Windows RT has no debug CRT, and /MT removes the
                                    # UCRT-redistributable question on an 8.1-era OS.
    echo '/DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS'
    echo "-I\"$(cygpath -m "$PFX")/include\""
  } > "$RSP"

  "$RT2/clang-cl.exe" "@$(cygpath -w "$RSP")" /c "$(cygpath -w "$ROOT/tools/sdlcanary.c")" \
      "/Fo$(cygpath -w "$OUT/sdlcanary.obj")" > "$OUT/cc.log" 2>&1 \
      || { echo "   $tag COMPILE FAILED"; grep -m8 -i 'error' "$OUT/cc.log"; return 1; }

  LRSP="$OUT/link.rsp"
  {
    echo '/SUBSYSTEM:CONSOLE'
    echo "/MACHINE:$mach"
    echo "/OUT:$(cygpath -w "$OUT/sdlcanary.exe")"
    echo '/DEFAULTLIB:libcmt.lib /DEFAULTLIB:oldnames.lib'
    echo "/LIBPATH:\"$(cygpath -w "$VC/lib/$libdir")\""
    echo "/LIBPATH:\"$(cygpath -w "$SDK/Lib/$SDKVER/ucrt/$libdir")\""
    echo "/LIBPATH:\"$(cygpath -w "$SDK/Lib/$SDKVER/um/$libdir")\""
    cygpath -w "$OUT/sdlcanary.obj"
    cygpath -w "$PFX/lib/SDL3-static.lib"
    # what a static SDL3 on Windows needs. version.lib is for SDL's own version query;
    # imm32/setupapi/winmm are pulled by the Windows video/audio backends.
    for l in user32 gdi32 winmm imm32 ole32 oleaut32 advapi32 shell32 setupapi version uuid kernel32; do
      echo "$l.lib"
    done
  } > "$LRSP"

  "$RT2/lld-link.exe" "@$(cygpath -w "$LRSP")" > "$OUT/link.log" 2>&1 \
      || { echo "   $tag LINK FAILED"; grep -m10 -i 'error' "$OUT/link.log"; return 1; }
  echo "   $tag sdlcanary.exe: $(stat -c%s "$OUT/sdlcanary.exe") bytes"
}

echo "=== x64 (runs on this box -- the instrument's own test) ==="
build x64   x86_64-pc-windows-msvc X64 x64   || exit 1
echo "=== arm32 (ships) ==="
build arm32 armv7-pc-windows-msvc  ARM arm   || exit 1
