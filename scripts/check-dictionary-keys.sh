#!/bin/bash
# Fails on a Swift dictionary literal that repeats a key.
#
# Swift does not reject this at compile time. It traps at runtime — "Dictionary
# literal contains duplicate keys" — and the state payload is rebuilt on every
# message from the panel, so a repeated key there is a crash the moment the
# interface says hello, before anything is on screen. That shipped once: a key
# was added three lines below the identical one already there.
#
# Keys are tracked per nesting depth, and a depth is wiped on entry. Nested
# literals — a `.map` that builds one dictionary per item inside another — are
# the normal shape here, and they are not duplicates of each other.
set -euo pipefail
cd "$(dirname "$0")/.."

if git ls-files 'Sources/*.swift' 'Sources/**/*.swift' | xargs awk '
  FNR == 1 { depth = 0; delete seen }

  {
    line = $0
    # A literal opened and closed on one line stands alone: check it by itself.
    if (match(line, /\[[^][]*\]/)) {
      inner = substr(line, RSTART, RLENGTH)
      delete once
      rest = inner
      while (match(rest, /"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:/)) {
        key = substr(rest, RSTART, RLENGTH)
        if (key in once) { printf "%s:%d  repeats %s\n", FILENAME, FNR, key; bad = 1 }
        once[key] = 1
        rest = substr(rest, RSTART + RLENGTH)
      }
      next
    }

    if (line ~ /\[[[:space:]]*$/) {
      depth++
      for (k in seen) if (index(k, depth SUBSEP) == 1) delete seen[k]
      next
    }
    if (line ~ /^[[:space:]]*\]/) { if (depth > 0) depth--; next }

    if (depth > 0 && match(line, /"[A-Za-z_][A-Za-z0-9_]*"[[:space:]]*:/)) {
      key = depth SUBSEP substr(line, RSTART, RLENGTH)
      if (key in seen) {
        printf "%s:%d  repeats %s, first at line %d\n", FILENAME, FNR, substr(line, RSTART, RLENGTH), seen[key]
        bad = 1
      } else {
        seen[key] = FNR
      }
    }
  }

  END { exit bad ? 1 : 0 }
'; then
  echo "dictionary keys ok — no literal repeats a key"
else
  echo "::error::a dictionary literal repeats a key, which traps at runtime"
  exit 1
fi
