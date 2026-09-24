/*
 * scrcpy-rt :: unistd.h shim for clang-cl + MSVC UCRT.
 *
 * BUILD INFRASTRUCTURE, NOT A SOURCE PATCH.
 *
 * There is exactly ONE unguarded #include <unistd.h> in the Windows build:
 *     app/src/cli.c:9
 * The others are either inside #ifndef _WIN32 (util/net.c:15, util/term.c:12 -- note the
 * indented '# include') or in sys/unix/*.c, which meson does not compile on Windows
 * (app/meson.build:79-97 selects sys/win/*.c instead).
 *
 * cli.c wants it for the getopt declarations that glibc puts there. Everything it could
 * legitimately need is in <io.h> and <process.h> under MSVC, so this header is deliberately
 * thin: it does NOT try to be a POSIX emulation layer. If a future file needs more, add it
 * here and say so, rather than widening it speculatively.
 */
#ifndef SC_RT_UNISTD_H
#define SC_RT_UNISTD_H

#ifdef _MSC_VER

#include <io.h>         /* read, write, close, isatty, access, _dup, ... */
#include <process.h>    /* getpid (_getpid), _exit */
#include <stdlib.h>
#include <sys/types.h>  /* our shim above, for ssize_t */

#ifndef STDIN_FILENO
# define STDIN_FILENO  0
#endif
#ifndef STDOUT_FILENO
# define STDOUT_FILENO 1
#endif
#ifndef STDERR_FILENO
# define STDERR_FILENO 2
#endif

#else
# include_next <unistd.h>
#endif

#endif /* SC_RT_UNISTD_H */
