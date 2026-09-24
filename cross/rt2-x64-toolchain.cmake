# CMake toolchain file -- x86_64 Windows via rt2's clang-cl.
#
# This exists ONLY to build an x64 twin of the SDL3 canary so the canary's own
# logic can be RUN on the dev box before it is carried to the Surface RT. It is
# not a shipping target.
#
# Why it exists at all: BATCH-ADB-6 shipped an instrument whose new code had
# never executed, and it cost a device trip. The canary is the gate for the whole
# of BATCH-SCRCPY-2; shipping it untested would repeat that at a worse place.
#
# ⚠ CMAKE_MSVC_RUNTIME_LIBRARY IS SET HERE ON PURPOSE. adb-rt's equivalent x64
# toolchain file was the one place the /MT unification never reached, and the
# mismatch only surfaced later through /failifmismatch. The x64 twin must be
# built the same way as the ARM32 one or it is not a twin.

set(CMAKE_SYSTEM_NAME       Windows)
set(CMAKE_SYSTEM_PROCESSOR  AMD64)

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
set(RT_RSP "${CMAKE_CURRENT_LIST_DIR}/target-x64.rsp")

set(CMAKE_C_COMPILER   "${RT_LLVM}/clang-cl.exe" "@${RT_RSP}")
set(CMAKE_CXX_COMPILER "${RT_LLVM}/clang-cl.exe" "@${RT_RSP}")
set(CMAKE_LINKER       "${RT_LLVM}/lld-link.exe")
set(CMAKE_AR           "${RT_VC}/bin/Hostx64/x64/lib.exe")
set(CMAKE_RC_COMPILER  "${RT_SDK}/bin/${RT_SDKVER}/x64/rc.exe")
set(CMAKE_MT           "${RT_SDK}/bin/${RT_SDKVER}/x64/mt.exe")

set(RT_PIN "/vctoolsdir \"${RT_VC}\" /winsdkdir \"${RT_SDK}\" /winsdkversion ${RT_SDKVER}")
set(CMAKE_C_FLAGS_INIT   "${RT_PIN}")
set(CMAKE_CXX_FLAGS_INIT "${RT_PIN}")

# See the ARM32 file: CMake links via lld-link directly, so the compiler's
# -vctoolsdir/-winsdkdir never become /libpath: and every import lib goes missing.
set(RT_LIBS "/LIBPATH:\"${RT_VC}/lib/x64\" /LIBPATH:\"${RT_SDK}/Lib/${RT_SDKVER}/ucrt/x64\" /LIBPATH:\"${RT_SDK}/Lib/${RT_SDKVER}/um/x64\"")
foreach(t EXE SHARED MODULE)
  set(CMAKE_${t}_LINKER_FLAGS_INIT "/MACHINE:X64 ${RT_LIBS}")
endforeach()
set(CMAKE_STATIC_LINKER_FLAGS_INIT "/MACHINE:X64")

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")
set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)

set(SDL_ASSEMBLY OFF CACHE BOOL "" FORCE)   # keep the twin's config identical to ARM32's
set(SDL_AVX      OFF CACHE BOOL "" FORCE)
set(SDL_AVX2     OFF CACHE BOOL "" FORCE)
set(SDL_AVX512F  OFF CACHE BOOL "" FORCE)
set(SDL_SSE      OFF CACHE BOOL "" FORCE)
set(SDL_SSE2     OFF CACHE BOOL "" FORCE)
set(SDL_SSE3     OFF CACHE BOOL "" FORCE)
set(SDL_SSE4_1   OFF CACHE BOOL "" FORCE)
set(SDL_SSE4_2   OFF CACHE BOOL "" FORCE)
