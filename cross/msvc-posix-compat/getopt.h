/*
 * scrcpy-rt :: getopt.h shim for clang-cl + MSVC UCRT.
 *
 * BUILD INFRASTRUCTURE, NOT A SOURCE PATCH. Implementation in cross/getopt_long.c, which is
 * added to the compile list -- scrcpy's own sources are untouched.
 *
 * Used from exactly one place: app/src/cli.c -- #include <getopt.h> at :4, getopt_long() at
 * :2498. cli.c builds both the optstring (sc_getopt_adapter_create_optstring, :1268) and the
 * longopts array (:1301) itself from its own options[] table, so only the final delegation to
 * libc needs supplying.
 *
 * WHAT THE IMPLEMENTATION MUST SUPPORT, established by reading cli.c rather than by copying a
 * full GNU implementation:
 *   - short options, ':' for a required argument, '::' for an optional one (built at :1276-1288)
 *   - long options with no_argument / required_argument / optional_argument
 *   - --name, --name=value, and --name value
 *   - optarg, optind, opterr, optopt
 *   - optind = 0 as a RESET request (cli.c:2495 does exactly this "to start from the first
 *     argument in tests"). That is GNU behaviour; BSD getopt would treat 0 as an index and
 *     silently skip argv[0]'s slot. Handled explicitly.
 *   - unambiguous long-option PREFIX matching, so `--no-aud` still means `--no-audio`
 *
 * WHAT IT DOES NOT NEED, and why that is safe:
 *   - GNU argv PERMUTATION. scrcpy takes no positional arguments: cli.c:2954-2957 reads
 *     `int index = optind; if (index < argc) { LOGE("Unexpected additional argument: %s", ...);
 *     return false; }`. Stopping at the first non-option produces the same user-visible result.
 *   - getopt_long_only, and the leading '+'/'-'/':' optstring modifiers -- cli.c emits none.
 */
#ifndef SC_RT_GETOPT_H
#define SC_RT_GETOPT_H

#ifdef __cplusplus
extern "C" {
#endif

#define no_argument       0
#define required_argument 1
#define optional_argument 2

struct option {
    const char *name;
    int has_arg;
    int *flag;
    int val;
};

extern char *optarg;
extern int optind;
extern int opterr;
extern int optopt;

int getopt(int argc, char *const argv[], const char *optstring);
int getopt_long(int argc, char *const argv[], const char *optstring,
                const struct option *longopts, int *longindex);

#ifdef __cplusplus
}
#endif

#endif /* SC_RT_GETOPT_H */
