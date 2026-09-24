# CMake toolchain file -- Windows ARM32 (ARMNT / Thumb-2) via rt2's clang-cl.
#
# BATCH-SCRCPY-2 Phase A. Derived from the DEVICE-PROVEN lite-xl toolchain file
# (D:/repo/lite-xl-rt/cross/rt1-arm32-toolchain.cmake, which built SDL3 3.2.14 for
# ARM32: 348 objects and 84 test programs, all COFF machine 0x01C4). Two values
# are deliberately changed; everything else is kept, including the comments,
# because each one records a failure that has already been paid for.
#
# CHANGE 1 -- rt2, not rt1.2.
#   lite-xl used D:/repo/llvm-rt/build-rt12/bin = LLVM 18.1.8. SCRCPY-1 section 1
#   requires rt2 (23.1.1): rt1's clang-cl REJECTS __try for thumbv7, upstream's
#   Windows ARM32 SEH landed in LLVM 21, and SDL uses __try/__except for the
#   MS_VC_EXCEPTION thread-naming trick.
#   ⚠ THE ONE-CHARACTER TRAP (SCRCPY-1 ADDENDUM 1):
#       D:/repo/llvm-rt/build/bin       = rt1   (18.1.8)   NOT rt2
#       D:/repo/llvm-rt/build-rt12/bin  = rt1.2 (18.1.8)   NOT rt2
#       D:/repo/llvm-rt/stage2/bin      = rt2   (23.1.1)   <-- this one
#   Both decoys exist and build everything silently with the wrong compiler.
#
# CHANGE 2 -- MSVC 14.44.35207, not 14.16.27023.
#   SCRCPY-1 section 0.4 names 14.16 at D:/Program Files/Vscom/. This build uses
#   14.44.35207 at D:/Program Files/vs22buildtools/ because ffmpeg-rt was built
#   with it (ffmpeg-rt/cross/windres-arm32.sh:11) and scrcpy LINKS AGAINST
#   ffmpeg-rt. /failifmismatch records the toolset in every object; mixing 14.16
#   and 14.44 across that link is the exact failure SCRCPY-2 section 4.3 warns
#   about. Both toolsets still support ARM32, so this costs nothing.
#   14.51 (VS 2026) does NOT: vadefs.h line 15 reads
#       #error Support for 32-bit ARM has been permanently removed.
#   and clang-cl auto-selects the newest toolset on the box without these pins.
#   The pin is mandatory, not hygiene.
#
# ---------------------------------------------------------------------------
# EVERY architecture-determining value below is set explicitly. None is inferred.
#
# The response file is part of the COMPILER COMMAND, not of the flags.
#   CMake runs the compiler for its own ABI detection BEFORE it has processed
#   CMAKE_C_FLAGS, so a --target= passed as a flag is absent from exactly the
#   invocation that decides the architecture. Baking it into CMAKE_C_COMPILER
#   via @rsp makes it unconditional.
#   '@' rather than a bare --target= token is deliberate: a bare '-'-prefixed
#   token in a compiler launcher trips argparse-style consumers downstream (it
#   is what broke windows.compile_resources under Meson, where rc.exe was handed
#   --target=armv7-pc-windows-msvc and died RC1106). '@' is not a prefix char.
#
# 'armv7-...' rather than 'thumbv7-...' is deliberate and is NOT a downgrade to
# A32: that triple defines __thumb__/__thumb2__ and emits COFF machine 0x01C4
# (ARMNT, Thumb-2), measured. 'thumbv7' produces the same 0x01C4 but
# canonicalises to machine='thumbv7', which lld-link rejects.

set(CMAKE_SYSTEM_NAME       Windows)
set(CMAKE_SYSTEM_PROCESSOR  ARM)
set(CMAKE_SYSTEM_VERSION    6.2)        # RT 8.0 is the oldest target OS

# ⚠ PATHS COME FROM THE ENVIRONMENT, set by config.sh at the repo root.
# CMake cannot source a shell file, so it reads the same variables config.sh exports. The
# defaults below are the device-verified values and are used only when nothing is exported,
# which keeps this file usable standalone and keeps config.sh the single source of truth.
set(RT_LLVM "D:/repo/llvm-rt/stage2/bin")
if(DEFINED ENV{RT2})
  set(RT_LLVM "$ENV{RT2}")
endif()
set(RT_VC "D:/Program Files/vs22buildtools/VC/Tools/MSVC/14.44.35207")
if(DEFINED ENV{VCTOOLS})
  set(RT_VC "$ENV{VCTOOLS}")
endif()
set(RT_SDK "D:/Windows Kits/10")
if(DEFINED ENV{WINSDK})
  set(RT_SDK "$ENV{WINSDK}")
endif()
set(RT_SDKVER "10.0.19041.0")
if(DEFINED ENV{WINSDKVER})
  set(RT_SDKVER "$ENV{WINSDKVER}")
endif()
# the response file sits next to this toolchain file, whatever the repo is called or where
# it lives -- CMAKE_CURRENT_LIST_DIR is the directory of THIS file.
set(RT_RSP "${CMAKE_CURRENT_LIST_DIR}/target-arm32.rsp")

set(CMAKE_C_COMPILER   "${RT_LLVM}/clang-cl.exe" "@${RT_RSP}")
set(CMAKE_CXX_COMPILER "${RT_LLVM}/clang-cl.exe" "@${RT_RSP}")
set(CMAKE_LINKER       "${RT_LLVM}/lld-link.exe")
set(CMAKE_AR           "${RT_VC}/bin/Hostx64/x64/lib.exe")
set(CMAKE_RC_COMPILER  "${RT_SDK}/bin/${RT_SDKVER}/x64/rc.exe")

# ⚠ PIN THE MANIFEST TOOL TOO. rt2 ships NO llvm-mt.exe (measured: stage2/bin has
# llvm-rc but no llvm-mt, no llvm-strings). Left alone, CMake finds
# C:/Program Files/LLVM/bin/llvm-mt.exe -- an unrelated LLVM 18-era install that
# nothing in this project pins or verifies. The Windows SDK's own mt.exe is a
# host x64 tool, already inside the pinned SDK, and is the right answer.
set(CMAKE_MT           "${RT_SDK}/bin/${RT_SDKVER}/x64/mt.exe")

set(RT_PIN "/vctoolsdir \"${RT_VC}\" /winsdkdir \"${RT_SDK}\" /winsdkversion ${RT_SDKVER}")
set(CMAKE_C_FLAGS_INIT   "${RT_PIN}")
set(CMAKE_CXX_FLAGS_INIT "${RT_PIN}")

# /MACHINE:ARM stated outright rather than inferred. CMake derives /MACHINE from
# the "Target:" line of `clang-cl --version`, which reads x86_64 here -- it would
# emit /MACHINE:x64 on an ARM32 build. Read it back out of build.ninja; do not
# trust this line.
#
# ⚠ AND THE LIBRARY PATHS, EXPLICITLY.
#   -vctoolsdir/-winsdkdir are COMPILER flags. clang-cl translates them into
#   /libpath: only when clang-cl is also the linker DRIVER. CMake invokes
#   CMAKE_LINKER (lld-link.exe) directly through `cmake -E vs_link_exe`, so those
#   flags never reach the link and the very first try-compile dies with
#       lld-link: error: could not open 'kernel32.lib'
#       lld-link: error: could not open 'libcmt.lib'
#   which reads like a missing SDK and is really a missing search path. Naming
#   them here makes the link independent of the LIB environment variable, which
#   is what silently carried the earlier lite-xl build.
set(RT_LIBS "/LIBPATH:\"${RT_VC}/lib/arm\" /LIBPATH:\"${RT_SDK}/Lib/${RT_SDKVER}/ucrt/arm\" /LIBPATH:\"${RT_SDK}/Lib/${RT_SDKVER}/um/arm\"")
foreach(t EXE SHARED MODULE)
  set(CMAKE_${t}_LINKER_FLAGS_INIT "/MACHINE:ARM ${RT_LIBS}")
endforeach()
set(CMAKE_STATIC_LINKER_FLAGS_INIT "/MACHINE:ARM")

# CMake must not go looking on the build machine for host-architecture artefacts.
# Without these it will happily find an x64 library and report success.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)     # host tools (lib.exe, rc.exe) are x64 by design
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# CMAKE_MSVC_RUNTIME_LIBRARY controls WHICH CRT is compiled against; SDL_STATIC
# controls HOW SDL IS LINKED. Unrelated knobs with similar names. CMake's default
# is the DYNAMIC CRT, and Windows RT has no debug CRT at all. Read /DEFAULTLIB
# back out of the built objects; do not trust this line either.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")
set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)           # CMAKE_MSVC_RUNTIME_LIBRARY honoured only under NEW

# ARM32 has no SSE/AVX. SDL's ARM SIMD paths stay off: the SDL_CPU_ARM32 FIXME is
# in the MSVC assembler-enablement block, and SDL_ASSEMBLY=OFF side-steps it
# without stubbing anything (recorded in SDL-rt commit 09574d931, which changes
# ZERO files under src/ or include/ -- SDL 3.2.14 needs no source patch here).
set(SDL_ASSEMBLY OFF CACHE BOOL "" FORCE)
set(SDL_AVX      OFF CACHE BOOL "" FORCE)
set(SDL_AVX2     OFF CACHE BOOL "" FORCE)
set(SDL_AVX512F  OFF CACHE BOOL "" FORCE)
set(SDL_SSE      OFF CACHE BOOL "" FORCE)
set(SDL_SSE2     OFF CACHE BOOL "" FORCE)
set(SDL_SSE3     OFF CACHE BOOL "" FORCE)
set(SDL_SSE4_1   OFF CACHE BOOL "" FORCE)
set(SDL_SSE4_2   OFF CACHE BOOL "" FORCE)
set(SDL_ALTIVEC  OFF CACHE BOOL "" FORCE)
set(SDL_ARMNEON  OFF CACHE BOOL "" FORCE)
set(SDL_ARMSIMD  OFF CACHE BOOL "" FORCE)
