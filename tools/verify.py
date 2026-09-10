#!/usr/bin/env python3
"""Runs every check that does not need Swift. Works on Windows, macOS, Linux.

    python tools/verify.py

verify.sh does the same thing for shells; this exists so a Windows machine
without Git Bash can still run the checks.
"""
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent

STEPS = [
    ("grading, commands, planner, ETA, streaks, watchdog", "run_corpus.py"),
    ("question packs", "validate_packs.py"),
    ("real answers against shipped questions", "run_content_cases.py"),
]


def main() -> int:
    failures = []
    for title, script in STEPS:
        print(f"--- {title} ---", flush=True)
        result = subprocess.run([sys.executable, str(HERE / script)], cwd=HERE)
        if result.returncode != 0:
            failures.append(script)
        print(flush=True)

    if failures:
        print(f"FAILED: {', '.join(failures)}")
        return 1
    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
