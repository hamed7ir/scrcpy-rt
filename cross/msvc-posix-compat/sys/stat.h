/*
 * scrcpy-rt :: sys/stat.h shim for clang-cl + MSVC UCRT.
 *
 * BUILD INFRASTRUCTURE, NOT A SOURCE PATCH.
 *
 * The UCRT ships sys/stat.h and the struct, but not POSIX's S_IS*() classification macros --
 * it has only the _S_IFMT / _S_IFREG / _S_IFDIR constants. mingw adds the macros, which is why
 * scrcpy has never needed this.
 *
 * One site in the Windows build:
 *     app/src/sys/win/file.c:41   S_ISREG(...)
 * It was the ONLY compile failure across all 71 translation units.
 *
 * The underscore-prefixed constants are used deliberately: the unprefixed S_IFMT / S_IFREG are
 * only visible under _CRT_NONSTDC_NO_WARNINGS, and this header must not depend on a define
 * someone may later remove from the response file.
 */
#ifndef SC_RT_SYS_STAT_H
#define SC_RT_SYS_STAT_H

#include_next <sys/stat.h>

#ifdef _MSC_VER

# ifndef S_ISREG
#  define S_ISREG(m)  (((m) & _S_IFMT) == _S_IFREG)
# endif
# ifndef S_ISDIR
#  define S_ISDIR(m)  (((m) & _S_IFMT) == _S_IFDIR)
# endif
# ifndef S_ISCHR
#  define S_ISCHR(m)  (((m) & _S_IFMT) == _S_IFCHR)
# endif
# ifndef S_ISFIFO
#  define S_ISFIFO(m) (((m) & _S_IFMT) == _S_IFIFO)
# endif

#endif /* _MSC_VER */

#endif /* SC_RT_SYS_STAT_H */
