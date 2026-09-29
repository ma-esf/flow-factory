#!/usr/bin/env bash
#
# Prints the header of a flow-ship-ticket stage:
#
#   $ bash ~/.flow-factory/stage.sh 3 "Adding sub to lib.sh."
#   🚢🚢🚢 3/7 Build
#   Adding sub to lib.sh.
#
# The skill runs this rather than writing the header as text. Runs carry out
# a command they are told to run, but dropped about half the headers they
# were told to write, most often right before a skill call.

set -u

names=(Reground Isolate Build Verification Commit PR "Close out")
n=${1:-}
case "$n" in
    [1-7]) ;;
    *) echo "stage.sh: the stage is a number from 1 to 7, not '$n'" >&2; exit 2 ;;
esac

ships=""
for ((i = 0; i < n; i++)); do ships+="🚢"; done
printf '%s %s/7 %s\n' "$ships" "$n" "${names[n - 1]}"
if [ -n "${2:-}" ]; then printf '%s\n' "$2"; fi
