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

print(f"{'FAIL' if fails else 'PASS'}: {checks - len(fails)}/{checks} cases")
for f in fails:
    print("  -", f)
sys.exit(1 if fails else 0)
