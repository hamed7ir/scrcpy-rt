# scrcpy-rt :: the ONE place absolute paths are configured.
#
# Every script under scripts/ sources this file. Nothing else in the repo hardcodes a
# location. The repo root is derived from the script's own path, never assumed, so a clone
# works wherever it is put.
#
# To build on your machine you normally only need to set the first four. Either edit the
# defaults here, or export them in your shell and leave this file alone -- every value uses
# the `: "${VAR:=default}"` form, so an environment variable always wins.
#
#     export RT2=/c/toolchains/llvm-rt/stage2/bin
#     sh scripts/catalogue-scrcpy.sh
#
# The defaults are the values this project was actually built and device-verified with, so
# they double as documentation of a known-good configuration.

# ---- repo root, derived. Do not hardcode this. -------------------------------------------
# Callers set SC_SELF to their own directory before sourcing; if they did not, fall back to
# this file's location.
if [ -z "${SC_ROOT:-}" ]; then
  SC_ROOT=$(cd "$(dirname "${SC_SELF:-$0}")/.." 2>/dev/null && pwd)
  [ -f "$SC_ROOT/config.sh" ] || SC_ROOT=$(cd "$(dirname "$0")" && pwd)
fi
export SC_ROOT

# ---- 1. the compiler -- rt2, LLVM 23.1.1-rt2 ----------------------------------------------
# ⚠ Must report 23.1.1-rt2. LLVM 18.x is a DIFFERENT toolchain that also lives on this
# machine; every script gates on the version string for that reason.
#
# The version string is the cheap check; these sha256 digests are the identifier, recorded
# from the build that produced every binary this project has shipped:
#   clang-cl.exe  ac6be213400d2449c53110b46bdae83b0fa41ea666ab27666ec46bc05c66465d
#   lld-link.exe  5f0903cab3d018f0d6b34e3b14ccb55292d5f6896d94c68abe6fe1c44b32e040
#   llvm-rc.exe   aa46ee08dfc41ecfba6925ccd55ef01b7c14a15713be98bfdd2f8f97ac6f59f0
: "${RT2:=D:/repo/llvm-rt/stage2/bin}"

# ---- 2. the MSVC toolset ------------------------------------------------------------------
# ⚠ 14.51 (VS 2026) hard-#errors on ARM32: vadefs.h:15 reads "Support for 32-bit ARM has been
# permanently removed." clang-cl auto-selects the NEWEST toolset unless pinned, so this is
# mandatory, not a preference. 14.16 also works; 14.44 is what ffmpeg-rt used, and scrcpy
# links against ffmpeg-rt, so they must match across /failifmismatch.
: "${VCTOOLS:=D:/Program Files/vs22buildtools/VC/Tools/MSVC/14.44.35207}"

# ---- 3. the Windows SDK -------------------------------------------------------------------
# ⚠ 10.0.19041.0 is the LAST SDK shipping ARM32 um/ucrt import libraries. 10.0.26100 and
# later removed them, which is also why upstream SDL dropped its Windows ARM32 CI.
: "${WINSDK:=D:/Windows Kits/10}"
: "${WINSDKVER:=10.0.19041.0}"

# ---- 4. host build tools ------------------------------------------------------------------
# Native Windows cmake/ninja invoked from an MSYS2 shell. Do NOT substitute MSYS2's own cmake:
# it thinks in POSIX paths and the compiler is a native Windows .exe.
: "${CMAKE:=D:/Program Files/vs22buildtools/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe}"
: "${NINJA:=D:/Program Files/vs22buildtools/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe}"

# ---- 5. sibling projects ------------------------------------------------------------------
# ffmpeg-rt supplies the four av* DLLs and their headers. Defaults to a sibling checkout.
: "${FFMPEG_RT:=$(cd "$SC_ROOT/../ffmpeg-rt" 2>/dev/null && pwd || echo "$SC_ROOT/../ffmpeg-rt")}"

# ---- 6. vendored sources (fetched, not committed -- see scripts/fetch-deps.sh) -------------
: "${SCRCPY_SRC:=$SC_ROOT/deps/scrcpy}"
: "${SDL_SRC:=$SC_ROOT/deps/SDL-3.2.14}"

# ---- derived. Nothing below needs editing. -------------------------------------------------
: "${BUILD:=$SC_ROOT/build}"
: "${DIST:=$SC_ROOT/dist}"
export RT2 VCTOOLS WINSDK WINSDKVER CMAKE NINJA FFMPEG_RT SCRCPY_SRC SDL_SRC BUILD DIST

# ⚠ Create the build directory HERE, once, rather than in each script. A fresh clone has no
# build/, and build-sdl3.sh writes its configure log BESIDE the build tree ("$BLD.cfg.log")
# before cmake creates anything -- so on any path but the original it died with
# "No such file or directory" and reported CONFIGURE FAILED, hiding the real cause.
# Found by actually building from a second location; it is invisible from the first.
mkdir -p "$BUILD" 2>/dev/null || true

# ---- the gate ------------------------------------------------------------------------------
# Called by every script before it does anything. Fails loudly and specifically, because a
# missing SDK and a wrong-architecture build look identical three steps later.
sc_check_config() {
  _bad=0
  for _v in RT2 VCTOOLS WINSDK CMAKE NINJA; do
    eval "_p=\$$_v"
    case "$_v" in
      CMAKE|NINJA) [ -f "$_p" ] || { echo "config: $_v not found: $_p"; _bad=1; } ;;
      *)           [ -d "$_p" ] || { echo "config: $_v not found: $_p"; _bad=1; } ;;
    esac
  done
  [ -d "$WINSDK/Lib/$WINSDKVER/um/arm" ] || {
    echo "config: no ARM32 import libraries at $WINSDK/Lib/$WINSDKVER/um/arm"
    echo "        SDK 10.0.19041.0 is the last one that ships them."
    _bad=1; }
  if [ "$_bad" -eq 0 ]; then
    _v=$("$RT2/clang-cl.exe" --version 2>/dev/null | head -1)
    case "$_v" in
      *23.1.1-rt2*) echo "config OK: $_v" ;;
      "")  echo "config: clang-cl.exe not runnable at \$RT2 ($RT2)"; _bad=1 ;;
      *)   echo "config: WRONG COMPILER -- $_v"; echo "        expected 23.1.1-rt2. LLVM 18.x will build silently and wrongly."; _bad=1 ;;
    esac
  fi
  [ "$_bad" -eq 0 ] || { echo; echo "Edit config.sh, or export the variables. See README."; return 1; }
  return 0
}
