import sys
from grader_reference import grade, command

fails = []
checks = 0
def ok(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)

NAP = ["Napoleon", "Napoleon Bonaparte", "Bonaparte"]
ROME = ["Rome"]
PLANETS = ["8", "eight"]
BEY = ["Beyonce", "Beyoncé"]
WW2 = ["1945"]

def verdict(said, answers, tol=None):
    return grade([said] if isinstance(said, str) else said, answers, tol)[0]

# --- grading: should be correct
for said in ["Uh, is it Napoleon?", "Napoleon", "um I think it's Napoleon",
             "the answer is Napoleon Bonaparte", "well, maybe Bonaparte",
             "NAPOLEON!", "napoleon bonaparte i think", "napolean"]:
    ok(verdict(said, NAP) == "correct", f"expected correct: {said!r}")

for said in ["Rome", "uh, is it Rome?"]:
    ok(verdict(said, ROME) == "correct", f"expected correct: {said!r}")
for said in ["eight", "I think it's eight", "8"]:
    ok(verdict(said, PLANETS) == "correct", f"expected correct: {said!r}")
for said in ["Beyoncé", "beyonce!"]:
    ok(verdict(said, BEY) == "correct", f"expected correct: {said!r}")
ok(verdict("I want to say 1945", WW2) == "correct", "expected correct: 1945 lead-in")

# --- grading: should be incorrect
for said, ans, label in [("Churchill", NAP, "Churchill"),
                         ("I have no clue, Caesar maybe", NAP, "Caesar"),
                         ("dome", ROME, "dome"), ("Rope", ROME, "Rope"),
                         ("nine", PLANETS, "nine"), ("1944", WW2, "1944")]:
    ok(verdict(said, ans) == "incorrect", f"expected incorrect: {label!r}")

# --- recognizer alternatives and empties
ok(grade(["nap-oh-lee-on", "Napoleon"], NAP) == ("correct", "Napoleon"), "alternatives list")
ok(grade([], NAP)[0] == "noSpeech", "empty candidates")
ok(grade(["", "   "], NAP)[0] == "noSpeech", "blank candidates")

# --- commands that must fire
for said, want in [("repeat", "repeatQuestion"), ("skip", "skip"), ("pause", "pause"),
                   ("how many left", "howManyLeft"), ("stop", "stop"),
                   ("uh, can you repeat that?", "repeatQuestion"),
                   ("say that again", "repeatQuestion"), ("skip this one", "skip"),
                   ("I don't know", "skip"), ("how much longer", "howManyLeft"),
                   ("hold on", "pause"), ("that's enough", "stop"),
                   ("one more time", "repeatQuestion"), ("keep going", "resume")]:
    got = command(said)
    ok(got == want, f"command {said!r}: want {want}, got {got}")

# --- utterances that must NOT be commands
for said in ["the answer is a stop sign", "I think it's a mountain pass",
             "Napoleon", "the Nile", "", "   ", "Passchendaele"]:
    got = command(said)
    ok(got is None, f"expected no command for {said!r}, got {got}")

# --- allow-list gating while paused
paused = {"resume", "stop"}
ok(command("keep going", paused) == "resume", "paused: resume")
ok(command("stop", paused) == "stop", "paused: stop")
ok(command("skip", paused) is None, "paused: skip must be ignored")

from grader_reference import (plan, should_start_next, eta_remaining,
                              eta_should_wrap_up, eta_replacing)

# --- PackPlanner budget arithmetic
q30 = [30.0] * 40
ok(plan(q30, 600)[0] == 16, "600s drive fits 16 x 30s questions")
ok(plan(q30, 600, 1.3)[0] == 21, "600s with 1.3 contingency queues 21")
ok(plan(q30, 600, 0.5)[0] == 16, "contingency below 1.0 is ignored")
ok(plan([30.0] * 20, 180)[0] == 2, "3 minute drive fits 2 questions")
ok(plan([30.0] * 20, 30)[0] == 0, "30 second drive fits none")
ok(plan([30.0] * 20, 30)[2] is False, "too-short drive is not 'ran out'")
ok(plan([30.0], 3600)[2] is True, "one question against an hour ran out")
ok(plan([30.0] * 10, 3600, 1.3)[2] is True, "ran out measured against real drive")
ok(plan(q30, 600)[2] is False, "plenty of questions left is not 'ran out'")

# --- never start a question that cannot finish before the summary
ok(should_start_next(120, 30) is True, "2 minutes left starts a 30s question")
ok(should_start_next(90, 30) is True, "exactly at the wrap-up threshold still asks")
ok(should_start_next(89, 30) is False, "inside the threshold stops asking")
ok(should_start_next(60, 30) is False, "60s left is inside the threshold")
ok(should_start_next(100, 80) is False, "long question would cut off the summary")
ok(should_start_next(110, 80) is True, "110s leaves room for an 80s question")

# --- ETA snapshot behaviour
ok(eta_remaining(600, 0) == 600, "eta at rest")
ok(eta_remaining(600, 120) == 480, "eta counts down")
ok(eta_remaining(60, 300) == 0, "eta never goes negative")
ok(eta_remaining(-50, 0) == 0, "negative eta clamps to zero")
ok(eta_should_wrap_up(600, 0) is False, "ten minutes out is not wrap-up")
ok(eta_should_wrap_up(600, 511) is True, "89 seconds out is wrap-up")
ok(eta_replacing(600, 0) == 600, "failed refresh keeps the good estimate")
ok(eta_replacing(600, 900) == 900, "traffic refresh replaces the estimate")

print(f"{'FAIL' if fails else 'PASS'}: {checks - len(fails)}/{checks} cases")
for f in fails:
    print("  -", f)
sys.exit(1 if fails else 0)
