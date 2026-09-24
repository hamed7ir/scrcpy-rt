#!/bin/sh
# BATCH-SCRCPY-2 Phase A (section 2.2): build SDL3 3.2.14 FRESH for ARM32, and an x64 twin.
#
# The x64 twin is not a shipping target. It exists so the canary's own logic can be RUN on
# the dev box before it is carried to the Surface RT (see scripts/build-canary.sh).
#
# DELTA FROM THE DEVICE-PROVEN lite-xl BUILD (SDL-rt/rt-arm32/configure-invocation.txt).
# The lite-xl config was READ, not assumed -- its generated SDL_build_config.h says:
#     SDL_VIDEO_RENDER_D3D 1     SDL_VIDEO_RENDER_D3D11 1     SDL_VIDEO_RENDER_D3D12 1
#     SDL_VIDEO_RENDER_OGL 1     SDL_VIDEO_RENDER_OGL_ES2 1
#     SDL_AUDIO_DRIVER_WASAPI    -- NOT defined; only _DUMMY
# so SCRCPY-2 section 2.2's expectation ("its generated config almost certainly has the
# renderers off") is WRONG: the renderers were already on. It is AUDIO that was off.
#
#   SDL_AUDIO       OFF -> ON     the actual gap; brings SDL_AUDIO_DRIVER_WASAPI
#   SDL_OPENGL      ON  -> OFF    opengl32.dll does not exist on Windows RT at all
#   SDL_OPENGLES    ON  -> OFF    same, and it removes scrcpy's app/src/opengl.c branch
#   SDL_RENDER_D3D12 ON -> OFF    D3D12 cannot exist on an 8.1-era OS; leaving it in only
#                                 adds a driver ahead of D3D11 in render_drivers[] that can
#                                 fail at runtime and cost a fallback
#   SDL_TESTS       ON  -> OFF    we ship our own canary
#
# Everything else is kept AS THE PROVEN BUILD HAD IT. Renderer order in SDL_render.c's
# render_drivers[] is D3D11, D3D12, D3D(9), ... so with D3D12 out, SDL_CreateRenderer(NULL)
# tries D3D11 then D3D9. The canary measures which actually comes up; nothing here assumes it.
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

ROOT=$SC_ROOT
SRC=$SDL_SRC

# --- HARD GATE: rt2 or stop. A non-matching version is conclusive proof of the wrong compiler.
V=$("$RT2/clang-cl.exe" --version | head -1)
case "$V" in *23.1.1-rt2*) echo "GATE OK: $V" ;; *) echo "GATE FAIL: $V"; exit 1 ;; esac

# --- source: SDL 3.2.14, fetched by scripts/fetch-deps.sh. SDL needs ZERO source changes for
# ARM32 -- upstream release-3.2.14 builds as-is against SDK 10.0.19041.0. Upstream dropped its
# Windows ARM32 CI only because SDK 10.0.26100+ removed the ARM32 import libraries; pinning the
# older SDK is sufficient and no patch is required.
if [ ! -d "$SRC" ]; then
  echo "SDL source not found at: $SRC"
  echo "Run:  sh scripts/fetch-deps.sh"
  exit 1
fi
echo "SDL source : $SRC  ($(git -C "$(cygpath -w "$SRC")" rev-parse --short HEAD))"
echo "SDL version: $(grep -m1 'project(SDL3' "$SRC/CMakeLists.txt")"

build_arch() {  # build_arch <tag> <toolchain>
  tag="$1"; tc="$2"
  BLD=$ROOT/build/sdl3-$tag
  PFX=$ROOT/build/sdl3-$tag-prefix
  rm -rf "$BLD" "$PFX"
  "$CMAKE" -S "$(cygpath -w "$SRC")" -B "$(cygpath -w "$BLD")" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$NINJA" \
    -DCMAKE_TOOLCHAIN_FILE="$tc" \
    -DCMAKE_INSTALL_PREFIX="$(cygpath -w "$PFX")" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
    -DSDL_INSTALL=ON -DSDL_INSTALL_DOCS=OFF \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON \
    -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    -DSDL_AUDIO=ON \
    -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF \
    -DSDL_RENDER_D3D=ON -DSDL_RENDER_D3D11=ON -DSDL_RENDER_D3D12=OFF \
    -DSDL_VULKAN=OFF -DSDL_GPU=OFF \
    -DSDL_CAMERA=OFF -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_HIDAPI=OFF \
    -DSDL_DIALOG=OFF -DSDL_POWER=OFF -DSDL_SENSOR=OFF -DSDL_RPATH=OFF \
    -DSDL_VENDOR_INFO=scrcpy-rt \
    > "$BLD.cfg.log" 2>&1 || { echo "   $tag CONFIGURE FAILED"; tail -20 "$BLD.cfg.log"; return 1; }

  # G-B1: read /MACHINE back out of the generated build, do not trust the toolchain file
  want=$([ "$tag" = arm32 ] && echo "/MACHINE:ARM" || echo "/MACHINE:X64")
  if grep -q -- "$want" "$BLD/build.ninja"; then echo "   $tag link flags: $want present in build.ninja"
  else echo "   $tag GATE FAIL: $want absent from build.ninja"; return 1; fi

  "$CMAKE" --build "$(cygpath -w "$BLD")" --target install \
    > "$BLD.build.log" 2>&1 || { echo "   $tag BUILD FAILED"; grep -m8 -i 'error' "$BLD.build.log"; return 1; }
  echo "   $tag SDL3-static.lib: $(stat -c%s "$PFX/lib/SDL3-static.lib") bytes"
}

echo "=== arm32 (the shipping target) ==="
build_arch arm32 "$(cygpath -m "$SC_ROOT")"/cross/rt2-arm32-toolchain.cmake || exit 1
echo "=== x64 (the canary twin, runs here) ==="
build_arch x64   "$(cygpath -m "$SC_ROOT")"/cross/rt2-x64-toolchain.cmake   || exit 1
