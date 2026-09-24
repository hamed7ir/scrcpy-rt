#!/bin/sh
# scrcpy-rt :: fetch the upstream sources this repo builds against.
#
# Nothing upstream is committed here. This script reconstructs deps/ from pinned, public
# refs, so the build is reproducible without redistributing anybody else's tree.
#
# BOTH upstreams take ZERO source patches from this project:
#   scrcpy  4.1        71/71 translation units compile under clang-cl with four shim headers
#                      on the include path (cross/msvc-posix-compat/) and nothing else
#   SDL     3.2.14     builds for ARM32 as-is against Windows SDK 10.0.19041.0
#
# That is why patches/ is empty and why this script is the whole of the dependency story FOR THE
# SHIPPING BUILD. One non-shipping path is outside it: scripts/build-scrcpy-x64.sh builds an x64
# debugging twin and links it against import libraries generated from the OFFICIAL
# scrcpy-win64-v4.1 DLLs, which nothing here fetches or pins. That twin is never released.
set -u

SC_SELF=$0
SC_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$SC_ROOT/config.sh"

# --- pinned refs ---------------------------------------------------------------------------
SCRCPY_URL=https://github.com/Genymobile/scrcpy.git
SCRCPY_TAG=v4.1
SCRCPY_SHA=2926c06c5dc3064ae6d8db706f1a98a37cfcf3f0

SDL_URL=https://github.com/libsdl-org/SDL.git
SDL_TAG=release-3.2.14
# release-3.2.14 is a LIGHTWEIGHT tag, so this is the commit itself and `rev-parse HEAD` in a
# clone equals it directly. (AOSP's platform-tools tags are ANNOTATED, where it does not --
# see adb-rt/scripts/fetch-deps.sh for that trap.)
SDL_SHA=8d604353a53853fa56d1bdce0363535605ca868f

# The prebuilt server jar is a RELEASE ASSET, not built here: building it needs a JDK and the
# Android SDK, and scrcpy refuses to run when the client and server versions differ.
SERVER_URL=https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-server-v4.1
SERVER_SHA256=deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae

mkdir -p "$SC_ROOT/deps"

fetch_git() {   # fetch_git <url> <ref> <dest> [expected-sha]
  _url=$1; _ref=$2; _dest=$3; _sha=${4:-}
  if [ -d "$_dest" ]; then
    echo "have: $_dest"
  else
    echo "clone: $_url @ $_ref"
    # ⚠ Windows paths for git. MSYS2_ARG_CONV_EXCL is set by some callers, and a /d/... path
    # then reaches native git verbatim, which reports "repository does not exist" -- a path
    # fault wearing a missing-repo costume.
    # -c core.autocrlf=false: on Windows git's default rewrites every checked-out file to
    # CRLF. The sources still compile, but the tree is then not byte-identical to what was
    # built here, and any hash comparison against upstream stops meaning anything.
    git clone -q --depth 1 -c core.autocrlf=false -c core.eol=lf         --branch "$_ref" "$_url" "$(cygpath -w "$_dest" 2>/dev/null || echo "$_dest")" || return 1
  fi
  _got=$(git -C "$(cygpath -w "$_dest" 2>/dev/null || echo "$_dest")" rev-parse HEAD 2>/dev/null)
  echo "  HEAD: $_got"
  if [ -n "$_sha" ] && [ "$_got" != "$_sha" ]; then
    echo "  ⚠ EXPECTED $_sha"
    echo "  The pin did not match. Do not build from this tree until you know why."
    return 1
  fi
  return 0
}

echo "=== scrcpy $SCRCPY_TAG ==="
fetch_git "$SCRCPY_URL" "$SCRCPY_TAG" "$SCRCPY_SRC" "$SCRCPY_SHA" || exit 1

echo "=== SDL $SDL_TAG ==="
fetch_git "$SDL_URL" "$SDL_TAG" "$SDL_SRC" "$SDL_SHA" || exit 1
echo "  version: $(grep -m1 'project(SDL3' "$SDL_SRC/CMakeLists.txt" 2>/dev/null)"

echo "=== scrcpy-server (release asset) ==="
SRV=$SC_ROOT/deps/scrcpy-server
if [ -f "$SRV" ]; then
  echo "have: $SRV"
else
  echo "download: $SERVER_URL"
  # ⚠ curl gets a WINDOWS path: a /d/... -o argument under MSYS2_ARG_CONV_EXCL fails with
  # "curl: (23)". Measured in this project, twice.
  curl -fsSL "$SERVER_URL" -o "$(cygpath -w "$SRV" 2>/dev/null || echo "$SRV")" || exit 1
fi
GOT=$(sha256sum "$SRV" | cut -d' ' -f1)
echo "  sha256: $GOT"
if [ "$GOT" != "$SERVER_SHA256" ]; then
  echo "  ⚠ EXPECTED $SERVER_SHA256"
  echo "  scrcpy refuses to run when client and server versions differ. Stop here."
  exit 1
fi
echo "  matches the pin."

echo
echo "deps ready. Next:  sh scripts/build-sdl3.sh"
