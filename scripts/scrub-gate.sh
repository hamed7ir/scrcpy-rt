#!/bin/sh
# BATCH-PUBLISH-1 section 1.2 -- THE SCRUB GATE.
#
# Sweeps the set of files git WOULD track (not the working tree) in each repo for personal and
# device identifiers, and prints a denominator: scanned / found / remaining.
#
# ⚠ IT RUNS A POSITIVE CONTROL FIRST. A sweep that finds nothing because it is broken looks
# exactly like a clean tree, and that failure mode has bitten this project four times. If the
# control does not fire, the zero below means nothing and the gate exits 2.
#
# Usage:  sh scripts/scrub-gate.sh [repo-dir ...]     (default: the three publication repos)
set -u

# Default: this repo and its two siblings, located relative to THIS script -- not hardcoded,
# so the gate runs from any checkout. Pass repo directories as arguments to override.
_HERE=$(cd "$(dirname "$0")/.." && pwd)
_SIBS=$(cd "$_HERE/.." && pwd)
REPOS=${*:-"$_SIBS/ffmpeg-rt $_SIBS/adb-rt $_HERE"}

# Personal or device identifiers, read from a file that is NEVER committed -- the list itself
# names a real phone, a real IP and a real key fingerprint, so publishing it would defeat the
# point of the sweep. Create .scrub-discriminators at the repo root, one string per line:
#
#     myusername
#     MYHOSTNAME
#     0123456789ABCDEF          <- a device serial
#     192.168.0.42              <- a LAN address
#
# ⚠ Earlier revisions of this script embedded the list, and then matched itself 11 times.
#
# ⚠ NEVER SCRUB AN UPSTREAM COPYRIGHT LINE. patches/ carries verbatim upstream hunks, and
# those hunks contain their authors' names and addresses as `Copyright (c) YYYY Name <email>`.
# Those lines are a LICENCE OBLIGATION, not a leak: removing one to make this gate report zero
# would trade a privacy non-problem for a real licensing one. If a discriminator ever collides
# with an upstream copyright line, fix the discriminator, not the patch.
DISCRIM_FILE=${DISCRIM_FILE:-$(dirname "$0")/../.scrub-discriminators}
if [ ! -f "$DISCRIM_FILE" ]; then
  echo "no discriminator list at $DISCRIM_FILE"
  echo "Nothing was checked. That is NOT a pass -- see the comment above."
  exit 2
fi
# HOW MATCHING WORKS, AND WHY IT IS NOT grep -F.
#
# Discriminators are literal strings, and some are Windows path forms containing backslashes.
# Three approaches were tried:
#
#   grep -F        ! MEASURED BROKEN: on GNU grep 3.0 under MSYS2, -i combined with -F aborts
#                    with SIGABRT (exit 134) and matches nothing. Either flag alone is fine.
#                    The POSITIVE CONTROL caught this -- 'rt2 matched 0 of 31 files' -- which
#                    is precisely what that control exists for.
#   escaping to BRE  fragile: the escaper itself has to survive sh, sed and the heredoc that
#                    writes it, and got mangled twice while being written.
#   normalising    <- what this does. Both the haystack and the needle have backslashes
#                    turned into forward slashes before they meet, so NO backslash ever
#                    reaches the regex engine and nothing can be silently mis-parsed.
#
# Consequence worth knowing: a '.' in a discriminator (an IP address) is still a regex dot, so
# it can over-match by one character. That direction is safe -- it can raise a false alarm,
# never miss a real hit -- and a false alarm is cheap to dismiss by eye.
norm() { tr '\\' '/'; }
TMPD=${TMPDIR:-/tmp}/scrubgate.$$
mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT INT TERM
norm_s() { printf '%s' "$1" | tr '\\' '/'; }
DISCRIM=$(grep -v '^[[:space:]]*$' "$DISCRIM_FILE" | grep -v '^#')

# Present in every repo -- if this does not match, the sweep itself is broken.
CONTROL='rt2'
CTL_RE=$(norm_s "$CONTROL")

TOTAL_HITS=0
for R in $REPOS; do
  name=$(basename "$R")
  cd "$R" 2>/dev/null || { echo "$name: NOT FOUND"; continue; }

  # The set that would actually be committed.
  #
  # TWO SOURCES, AND THE ORDER MATTERS. `git add -A --dry-run` answers "what is NOT yet
  # staged", so once the repo HAS been staged it answers NOTHING -- and a sweep over zero
  # files reports zero hits, which is indistinguishable from a clean tree. That happened
  # here; the positive control below is what caught it. The index is the real answer
  # whenever it is populated, and section 5.7 asks for exactly the staged set.
  SRC=index
  FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
  if [ -z "$FILES" ]; then
    SRC='git add -A --dry-run'
    FILES=$(git add -A --dry-run 2>/dev/null | sed -E "s/^add '//; s/'$//")
  fi
  N=$(printf '%s\n' "$FILES" | grep -c . )

  echo "=== $name ==="
  echo "  file set from         : $SRC"
  echo "  files to be committed : $N"

  # --- one normalised copy and ONE grep per file -------------------------------------------
  # Every discriminator goes into a pattern file and grep -f applies them all in a single pass.
  # The earlier version ran one tr + one grep PER DISCRIMINATOR per file -- 26 processes a file
  # instead of 2 -- which made a 149-file sweep take many minutes for no benefit.
  # ! norm_s uses printf '%s' with NO trailing newline. Without the echo below every pattern
  #   lands on ONE line and grep -f matches nothing -- the sweep passes while seeing nothing.
  #   The negative control caught exactly that.
  printf '%s
' "$DISCRIM" | while IFS= read -r d; do
    [ -n "$d" ] || continue
    norm_s "$d"; echo
  done > "$TMPD/pats"

  CN=0; SCANNED=0; HITS=0
  for f in $FILES; do
    [ -f "$f" ] || continue
    norm < "$f" > "$TMPD/n" 2>/dev/null
    grep -qi -- "$CTL_RE" "$TMPD/n" 2>/dev/null && CN=$((CN+1))
    SCANNED=$((SCANNED+1))
    if grep -qi -f "$TMPD/pats" "$TMPD/n" 2>/dev/null; then
      HITS=$((HITS+1))
      grep -ni -f "$TMPD/pats" "$TMPD/n" 2>/dev/null | sed "s|^|    HIT $f:|"
    fi
  done

  if [ "$CN" -eq 0 ]; then
    echo "  POSITIVE CONTROL FAILED: '$CONTROL' matched 0 of $N files."
    echo "  The sweep is broken. Nothing below is evidence."
    exit 2
  fi
  echo "  positive control      : '$CONTROL' found in $CN file(s) -- the sweep fires"
  echo "  scanned               : $SCANNED"
  echo "  discriminator hits    : $HITS"
  [ "$SCANNED" -eq "$N" ] || echo "  ! scanned != tracked count -- the sweep is not evidence"
  H=$HITS

  TOTAL_HITS=$((TOTAL_HITS + H))
  echo
done

echo "TOTAL REMAINING HITS ACROSS ALL REPOS: $TOTAL_HITS"
[ "$TOTAL_HITS" -eq 0 ] || { echo "GATE FAILED -- do not publish until these are 0."; exit 1; }
echo "GATE PASSED."
