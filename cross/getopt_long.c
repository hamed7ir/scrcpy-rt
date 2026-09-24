/*
 * scrcpy-rt :: getopt / getopt_long for clang-cl + MSVC UCRT.
 *
 * BUILD INFRASTRUCTURE. Compiled into scrcpy.exe alongside scrcpy's own sources; no scrcpy
 * source file is modified. See cross/msvc-posix-compat/getopt.h for the requirements this
 * satisfies and the two GNU behaviours it deliberately omits (argv permutation, getopt_long_only)
 * together with the cli.c line numbers proving they are unreachable in scrcpy.
 *
 * Written for this project. Not derived from glibc (LGPL) or from any BSD implementation.
 */

#include <stdio.h>
#include <string.h>

#include "msvc-posix-compat/getopt.h"

char *optarg = NULL;
int optind = 1;
int opterr = 1;
int optopt = 0;

/* index of the next character to examine inside argv[optind], 0 = start of a new element */
static int sc_optpos = 0;

static void
sc_reset(void)
{
    optind = 1;
    sc_optpos = 0;
}

static void
sc_err(const char *fmt, const char *a, int c)
{
    if (!opterr) {
        return;
    }
    if (a) {
        fprintf(stderr, fmt, a);
    } else {
        fprintf(stderr, fmt, c);
    }
    fputc('\n', stderr);
}

/*
 * Match `name` (length n) against longopts. Exact match wins outright; otherwise a unique
 * prefix match is accepted, matching GNU. Returns the index, -1 for no match, -2 for ambiguous.
 */
static int
sc_match_long(const struct option *longopts, const char *name, size_t n)
{
    int exact = -1, partial = -1, npartial = 0;
    int i;

    if (!longopts) {
        return -1;
    }
    for (i = 0; longopts[i].name; ++i) {
        if (strncmp(longopts[i].name, name, n) != 0) {
            continue;
        }
        if (strlen(longopts[i].name) == n) {
            exact = i;
            break;
        }
        partial = i;
        ++npartial;
    }
    if (exact >= 0) {
        return exact;
    }
    if (npartial == 1) {
        return partial;
    }
    if (npartial > 1) {
        return -2;
    }
    return -1;
}

static int
sc_getopt_impl(int argc, char *const argv[], const char *optstring,
               const struct option *longopts, int *longindex)
{
    const char *spec;
    char *arg;

    /* cli.c:2495 sets optind = 0 to restart. GNU treats that as "reinitialise"; without this
     * the scan would begin at argv[0] and silently lose the first real argument. */
    if (optind == 0) {
        sc_reset();
    }

    optarg = NULL;

    if (optind >= argc) {
        return -1;
    }

    arg = argv[optind];

    /* not in the middle of a short-option cluster: decide what this element is */
    if (sc_optpos == 0) {
        if (arg[0] != '-' || arg[1] == '\0') {
            return -1;              /* a non-option; scrcpy rejects leftovers itself */
        }
        if (arg[1] == '-' && arg[2] == '\0') {
            ++optind;               /* bare "--" ends the options */
            return -1;
        }
        if (arg[1] == '-') {
            /* ---- long option ---- */
            const char *name = arg + 2;
            const char *eq = strchr(name, '=');
            size_t n = eq ? (size_t)(eq - name) : strlen(name);
            int idx = sc_match_long(longopts, name, n);

            if (idx == -2) {
                sc_err("option '--%s' is ambiguous", name, 0);
                ++optind;
                optopt = 0;
                return '?';
            }
            if (idx < 0) {
                sc_err("unrecognized option '--%s'", name, 0);
                ++optind;
                optopt = 0;
                return '?';
            }

            ++optind;
            if (longopts[idx].has_arg == required_argument) {
                if (eq) {
                    optarg = (char *)eq + 1;
                } else if (optind < argc) {
                    optarg = argv[optind++];
                } else {
                    sc_err("option '--%s' requires an argument", longopts[idx].name, 0);
                    optopt = longopts[idx].val;
                    return '?';
                }
            } else if (longopts[idx].has_arg == optional_argument) {
                /* only the --name=value form supplies an optional argument */
                optarg = eq ? (char *)eq + 1 : NULL;
            } else {                /* no_argument */
                if (eq) {
                    sc_err("option '--%s' doesn't allow an argument", longopts[idx].name, 0);
                    optopt = longopts[idx].val;
                    return '?';
                }
            }

            if (longindex) {
                *longindex = idx;
            }
            if (longopts[idx].flag) {
                *longopts[idx].flag = longopts[idx].val;
                return 0;
            }
            return longopts[idx].val;
        }
        sc_optpos = 1;              /* short-option cluster starts after the '-' */
    }

    /* ---- short option ---- */
    {
        char c = argv[optind][sc_optpos++];

        if (argv[optind][sc_optpos] == '\0') {
            ++optind;
            sc_optpos = 0;
        }

        spec = strchr(optstring, c);
        if (!spec || c == ':') {
            optopt = (unsigned char)c;
            sc_err("invalid option -- '%c'", NULL, (unsigned char)c);
            return '?';
        }

        if (spec[1] == ':') {
            if (spec[2] == ':') {
                /* optional argument: only if attached, e.g. -xVALUE */
                if (sc_optpos != 0) {
                    optarg = argv[optind] + sc_optpos;
                    ++optind;
                    sc_optpos = 0;
                } else {
                    optarg = NULL;
                }
            } else {
                /* required argument: attached, or the next element */
                if (sc_optpos != 0) {
                    optarg = argv[optind] + sc_optpos;
                    ++optind;
                    sc_optpos = 0;
                } else if (optind < argc) {
                    optarg = argv[optind++];
                } else {
                    optopt = (unsigned char)c;
                    sc_err("option requires an argument -- '%c'", NULL, (unsigned char)c);
                    return '?';
                }
            }
        }
        return (unsigned char)c;
    }
}

int
getopt_long(int argc, char *const argv[], const char *optstring,
            const struct option *longopts, int *longindex)
{
    return sc_getopt_impl(argc, argv, optstring, longopts, longindex);
}

int
getopt(int argc, char *const argv[], const char *optstring)
{
    return sc_getopt_impl(argc, argv, optstring, NULL, NULL);
}
