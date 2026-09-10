#!/usr/bin/env sh
# Everything that can actually be executed in this repo.
#
# There is no Swift toolchain here and swift.org is blocked by the egress
# policy, so the XCTest suite cannot run. These two checks cover the pure
# logic and the content, and the Swift tests mirror them.
set -e
cd "$(dirname "$0")"
echo "--- grading, commands, planner, ETA, streaks ---"
python3 run_corpus.py
echo
echo "--- question packs ---"
python3 validate_packs.py
echo
echo "--- real answers against shipped questions ---"
python3 run_content_cases.py
