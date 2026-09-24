/*
 * scrcpy-rt :: sys/types.h shim for clang-cl + MSVC UCRT.
 *
 * BUILD INFRASTRUCTURE, NOT A SOURCE PATCH. This sits on the include path ahead of the Windows
 * SDK's own sys/types.h, pulls that one in with #include_next, and adds the one thing it lacks.
 *
 * WHY: scrcpy uses ssize_t at 69 sites across 27 files, and gets it from an unconditional
 * #include <sys/types.h> (app/src/util/net.h:9, util/str.h:9, util/strbuf.h:8, device_msg.h:8,
 * util/net_intr.h:9, adb/adb.c:7, adb/adb_parser.c:6, hid/hid_gamepad.c:6, server.c:8, ...).
 * That works under mingw, whose sys/types.h defines ssize_t. It does NOT work here: the Windows
 * SDK's ucrt/sys/types.h is 51 lines with 6 typedefs and ssize_t is not among them (measured,
 * 10.0.19041.0). This is the single largest MSVC-ABI gap in the client, and the original recon
 * missed it.
 *
 * ssize_t is the signed counterpart of size_t. SSIZE_T from <basetsd.h> is exactly that on both
 * 32- and 64-bit Windows, so we take Microsoft's own definition rather than inventing one.
 */
#ifndef SC_RT_SYS_TYPES_H
#define SC_RT_SYS_TYPES_H

#include_next <sys/types.h>

#ifdef _MSC_VER
# include <basetsd.h>
# ifndef _SSIZE_T_DEFINED
#  define _SSIZE_T_DEFINED
typedef SSIZE_T ssize_t;
# endif
#endif

#endif /* SC_RT_SYS_TYPES_H */
