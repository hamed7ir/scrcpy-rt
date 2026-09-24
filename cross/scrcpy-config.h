/*
 * scrcpy-rt :: config.h -- hand-written replacement for the file meson generates.
 *
 * Every entry below is the value meson's configure_file() would have produced for THIS build,
 * derived from app/meson.build lines 145-186 rather than from habit:
 *
 *   -Dcompile_server=false  -Dusb=false  -Dportable=true  --buildtype=release
 *   host = windows, compiler = clang-cl (MSVC ABI), CRT = UCRT static (/MT)
 *
 * meson emits `#define X 1` for a true boolean and leaves a false one undefined; the HAVE_*
 * entries come from `cc.has_function(f)` against THIS toolchain, not against mingw's.
 */
#ifndef CONFIG_H
#define CONFIG_H

/* app/meson.build:145-158 -- check_functions, resolved against MSVC's UCRT.
 *
 * HAVE_STRDUP: MSVC provides strdup (as _strdup, with the POSIX name re-exported by
 * oldnames.lib, which the link line carries). Defining it stops app/src/compat.c from
 * compiling its own definition and colliding with the CRT's at link time.
 *
 * The other five genuinely do not exist in the UCRT, so they stay undefined and
 * app/src/compat.c supplies them -- that file is already written for exactly this case.
 * Nothing has to be shimmed by us. */
#define HAVE_STRDUP 1
/* #undef HAVE_ASPRINTF     -- compat.c:asprintf */
/* #undef HAVE_VASPRINTF    -- compat.c:vasprintf */
/* #undef HAVE_NRAND48      -- compat.c:nrand48 */
/* #undef HAVE_JRAND48      -- compat.c:jrand48 */
/* #undef HAVE_REALLOCARRAY -- compat.c:reallocarray */

/* app/meson.build:160-161 -- explicitly false on windows in meson's own expression */
/* #undef HAVE_SOCK_CLOEXEC */

/* app/meson.build:164 */
#define SCRCPY_VERSION "4.1"

/* app/meson.build:167 -- unused when PORTABLE is set, but the source still references it */
#define PREFIX ""

/* app/meson.build:172 -- scrcpy-server sits next to scrcpy.exe */
#define PORTABLE 1

/* app/meson.build:175-176 -- the adb reverse tunnel's local port range */
#define DEFAULT_LOCAL_PORT_RANGE_FIRST 27183
#define DEFAULT_LOCAL_PORT_RANGE_LAST 27199

/* app/meson.build:179 */
/* #undef SERVER_DEBUGGER */

/* app/meson.build:182 -- linux only */
/* #undef HAVE_V4L2 */

/* app/meson.build:185 -- requires libusb, and -Dusb=false */
/* #undef HAVE_USB */

#endif /* CONFIG_H */
