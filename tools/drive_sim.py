#!/usr/bin/env python3
"""Plays a whole drive at the terminal, using the real rules and real content.

This is not the iOS app and cannot be. It is the game loop from GameEngine.swift
re-expressed over the Python mirror, with the same spoken copy, the same
planner, the same grader and the same command matcher. Typing stands in for
speech and the clock is simulated.

What it is good for: hearing the shape and pacing of a drive, and catching copy
that reads fine in a source file and lands badly out loud.

    python tools/drive_sim.py                 # play it yourself
    python tools/drive_sim.py --script demo   # canned driver, no input needed
    python tools/drive_sim.py --minutes 12

Keep it in step with GameEngine.swift by hand, like the rest of tools/.
"""
import argparse
import json
import pathlib
import random
import sys

from grader_reference import (grade, command, order_by_freshness,
                              INTRO_SECONDS, CLOSING_SECONDS, WRAP_UP_THRESHOLD,
                              should_start_next)

PACK_DIR = pathlib.Path(__file__).resolve().parent.parent / "DriveQuiz" / "Content" / "Packs"

BREATH_BEFORE_QUESTION = 2.0

IN_GAME_COMMANDS = {"repeatQuestion", "skip", "pause", "howManyLeft", "stop"}
PAUSED_COMMANDS = {"resume", "stop"}


def load_packs():
    packs = []
    for path in sorted(PACK_DIR.glob("*.json")):
        packs.append(json.loads(path.read_text()))
    if not packs:
        sys.exit("no packs found")
    return packs


def plan(packs, available_seconds, contingency=1.0, seed=0, history=None):
    """Mirrors PackPlanner.plan."""
    theme = packs[0]["theme"] if len(packs) == 1 else "Mixed"
    base_budget = available_seconds - INTRO_SECONDS - WRAP_UP_THRESHOLD
    budget = base_budget * max(1.0, contingency)
    if base_budget <= 0:
        return theme, [], False

    pool = [q for p in packs for q in p["questions"]]
    rng = random.Random(seed)
    rng.shuffle(pool)

    by_id = {q["id"]: q for q in pool}
    ordered_ids = order_by_freshness([q["id"] for q in pool], history or {},
                                     14 * 86400, 0)
    pool = [by_id[i] for i in ordered_ids]

    chosen, used = [], 0.0
    for q in pool:
        if used + q["estimatedSeconds"] <= budget:
            chosen.append(q)
            used += q["estimatedSeconds"]
    ran_out = len(chosen) == len(pool) and (base_budget - min(used, base_budget)) > 45
    return theme, chosen, ran_out


class Drive:
    """The loop from GameEngine.swift, with the same spoken copy."""

    def __init__(self, theme, questions, ran_out, total_seconds, driver,
                 daily_streak=0, quiet=False):
        self.quiet = quiet
        self.outcomes = []
        self.theme = theme
        self.questions = questions
        self.ran_out = ran_out
        self.total = total_seconds
        self.elapsed = 0.0
        self.driver = driver
        self.daily_streak = daily_streak
        self.asked = self.correct = self.streak = self.best_streak = 0
        self.stopped = False
        self.transcript = []

    # --- output ---------------------------------------------------------

    def say(self, text):
        if not self.quiet:
            stamp = f"{int(self.elapsed) // 60:02d}:{int(self.elapsed) % 60:02d}"
            print(f"  {stamp}  DriveQuiz: {text}")
        self.transcript.append((self.elapsed, "app", text))

    def heard(self, text):
        if not self.quiet:
            stamp = f"{int(self.elapsed) // 60:02d}:{int(self.elapsed) % 60:02d}"
            shown = text if text.strip() else "(silence)"
            print(f"  {stamp}     driver: {shown}")
        self.transcript.append((self.elapsed, "driver", text))

    @property
    def remaining(self):
        return max(0.0, self.total - self.elapsed)

    # --- copy, mirrored from GameEngine ---------------------------------

    def intro_text(self):
        minutes = round(self.total / 60)
        line = f"{self.theme}. {minutes} minutes on the clock."
        projected = self.daily_streak + 1 if self.daily_streak else 1
        if projected >= 2:
            line += f" Day {projected} in a row."
        return line + " Say repeat, skip, pause, or stop at any time. Here is the first one."

    def correct_text(self):
        return {3: "Correct. That is three in a row.",
                5: "Correct. Five straight.",
                10: "Correct. Ten in a row, that is a run."}.get(
            self.streak, random.choice(["Correct.", "That is right.", "Got it."]))

    def remaining_text(self):
        left = max(0, len(self.questions) - self.asked)
        minutes = round(self.remaining / 60)
        m = "About a minute" if minutes <= 1 else f"About {minutes} minutes"
        if left > 5:
            return f"{m} to go."
        q = "one question left" if left == 1 else f"{left} questions left"
        return f"{m} to go, {q}."

    def summary_text(self, interrupted=False):
        if self.asked == 0:
            return "We ran out of road. See you tomorrow."
        opener = "Stopping there." if interrupted else "That is the drive."
        parts = [f"{opener} You got {self.correct} out of {self.asked}."]
        if self.best_streak >= 3:
            parts.append(f"Your best run was {self.best_streak} in a row.")
        if self.ran_out:
            parts.append("We used every question in the pack.")
        if self.daily_streak + 1 >= 2:
            parts.append(f"That is {self.daily_streak + 1} days in a row.")
        parts.append("See you tomorrow.")
        return " ".join(parts)

    # --- loop -----------------------------------------------------------

    def run(self):
        self.say(self.intro_text())
        self.elapsed += INTRO_SECONDS

        for question in self.questions:
            if self.stopped:
                break
            if not should_start_next(self.remaining, question["estimatedSeconds"]):
                break
            self.ask(question)

        if not self.stopped:
            self.say(self.summary_text())

    def ask(self, question):
        answers = [question["canonicalAnswer"]] + list(question["alternates"])
        nudged = False
        needs_prompt = True
        attempts = 0

        while attempts < 8:
            attempts += 1
            if self.stopped:
                return

            if needs_prompt:
                # Mirrors breathBeforeQuestion: the game takes a breath before
                # each new question instead of running everything together.
                self.elapsed += BREATH_BEFORE_QUESTION
                self.say(question["prompt"])
            needs_prompt = True

            said = self.driver(question, self)
            self.heard(said)
            self.elapsed += question["estimatedSeconds"]

            cmd = command(said, IN_GAME_COMMANDS)
            if cmd == "repeatQuestion":
                continue
            if cmd == "skip":
                self.asked += 1
                self.streak = 0
                self.outcomes.append((question["id"], "skipped")); self.say(f"Skipping. The answer was {question['canonicalAnswer']}.")
                return
            if cmd == "howManyLeft":
                self.say(self.remaining_text())
                continue
            if cmd == "pause":
                self.say("Paused. Say resume when you are ready.")
                self.say("Back to it.")
                continue
            if cmd == "stop":
                self.stopped = True
                self.say(self.summary_text(interrupted=True))
                return

            verdict = grade([said], answers)[0]

            if verdict == "noSpeech" and not nudged:
                nudged = True
                needs_prompt = False
                self.say("Still there? Take a guess, or say skip.")
                continue
            if verdict == "noSpeech":
                self.asked += 1
                self.streak = 0
                self.outcomes.append((question["id"], "unanswered")); self.say(f"Let us move on. The answer was {question['canonicalAnswer']}.")
                return
            if verdict == "correct":
                self.asked += 1
                self.correct += 1
                self.streak += 1
                self.best_streak = max(self.best_streak, self.streak)
                self.outcomes.append((question["id"], "correct")); self.say(self.correct_text())
                self.say(question["factOneLiner"])
                return
            self.asked += 1
            self.streak = 0
            self.outcomes.append((question["id"], "wrong")); self.say(f"Not quite. It was {question['canonicalAnswer']}.")
            self.say(question["factOneLiner"])
            return

        self.asked += 1
        self.streak = 0
        self.outcomes.append((question["id"], "unanswered")); self.say(f"Let us move on. The answer was {question['canonicalAnswer']}.")


# --- drivers -------------------------------------------------------------

def interactive_driver(question, drive):
    try:
        return input("            you: ")
    except EOFError:
        return ""


def scripted_driver(script):
    """Replays a canned driver, then falls silent."""
    queue = list(script)

    def driver(question, drive):
        if queue:
            entry = queue.pop(0)
            if entry == "@correct":
                return question["canonicalAnswer"]
            if entry == "@wrong":
                return "Cleopatra"
            return entry
        return question["canonicalAnswer"]

    return driver


DEMO = [
    "@correct",
    "uh, can you repeat that?",
    "@correct",
    "@wrong",
    "@correct",
    "how much longer",
    "@correct",
    "",                              # silence, should nudge
    "@correct",
    "I don't know",                  # a clean skip
    "@correct",
    "I don't know, maybe Cleopatra", # a guess, not a skip
    "@correct",
    "@correct",
    "@correct",
    "that's enough, it's Rome",      # must NOT quit the game
]


CHECKS = """Structural invariants a real drive must hold."""


def run_checks():
    """Plays the canned drive silently and asserts what must always be true."""
    failures = []

    def ok(cond, label):
        if not cond:
            failures.append(label)

    packs = load_packs()
    theme, questions, ran_out = plan(packs, 20 * 60, seed=7)
    drive = Drive(theme, questions, ran_out, 20 * 60,
                  scripted_driver(DEMO), daily_streak=3, quiet=True)
    drive.run()

    spoken = [t for _, who, t in drive.transcript if who == "app"]

    ok(bool(spoken), "the drive said something")
    ok(spoken[-1].startswith("That is the drive"), "the drive ends with a summary")

    # Every question that was started must have produced a spoken outcome.
    # A question that resolves in silence is the bug this guards.
    started = [q["id"] for q in questions][:len(drive.outcomes)]
    ok(len(drive.outcomes) == drive.asked,
       f"every asked question has an outcome ({len(drive.outcomes)} vs {drive.asked})")
    ok([qid for qid, _ in drive.outcomes] == started,
       "outcomes are in question order with none skipped over")

    # Score arithmetic must reconcile with the outcomes.
    counted = sum(1 for _, kind in drive.outcomes if kind == "correct")
    ok(counted == drive.correct, f"correct count reconciles ({counted} vs {drive.correct})")
    ok(drive.correct <= drive.asked, "score cannot exceed questions asked")
    ok(drive.best_streak <= drive.correct, "best streak cannot exceed correct answers")

    # No question may be asked twice in one drive.
    ids = [qid for qid, _ in drive.outcomes]
    ok(len(ids) == len(set(ids)), "no question repeats within a drive")

    # The drive must stop before the destination, never overrun it.
    ok(drive.elapsed <= 20 * 60, f"clock stayed inside the drive ({drive.elapsed:.0f}s)")

    # Regression: an answer containing a command phrase must not end the game.
    ok(not drive.stopped, "'that's enough, it's Rome' did not quit the drive")

    print(f"{'FAIL' if failures else 'PASS'}: "
          f"{9 - len(failures)}/9 drive invariants "
          f"({drive.correct}/{drive.asked} over {int(drive.elapsed)}s)")
    for f in failures:
        print("  -", f)
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--minutes", type=int, default=20)
    parser.add_argument("--script", choices=["demo"], help="run without input")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--pack", help="pack id, default is all of them")
    parser.add_argument("--check", action="store_true",
                        help="assert the invariants instead of printing a drive")
    args = parser.parse_args()

    if args.check:
        sys.exit(run_checks())

    random.seed(args.seed)
    packs = load_packs()
    if args.pack:
        packs = [p for p in packs if p["id"] == args.pack] or packs

    theme, questions, ran_out = plan(packs, args.minutes * 60, seed=args.seed)
    if not questions:
        sys.exit("that drive is too short for a round")

    driver = scripted_driver(DEMO) if args.script else interactive_driver
    print(f"\n  === {args.minutes} minute drive, {len(questions)} questions queued "
          f"({theme}) ===\n")

    drive = Drive(theme, questions, ran_out, args.minutes * 60, driver, daily_streak=3)
    drive.run()

    print(f"\n  === score {drive.correct}/{drive.asked}, "
          f"best run {drive.best_streak}, "
          f"clock {int(drive.elapsed) // 60}m{int(drive.elapsed) % 60:02d}s "
          f"of {args.minutes}m ===\n")


if __name__ == "__main__":
    main()
