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

from grader_reference import (streak_record, streak_projected, streak_at_risk,
                              freshness_rank, order_by_freshness, prune, DAY)

# --- daily streak transitions
# 2023-11-14 09:00:00 UTC. Anchored mid-morning so an eight hour
# offset stays inside the same calendar day.
D1 = 1_699_952_400.0
FRESH = (0, 0, None)

s1 = streak_record(FRESH, D1)
ok(s1[:2] == (1, 1), "first play starts at one")

s2 = streak_record(s1, D1 + DAY)
s3 = streak_record(s2, D1 + 2 * DAY)
ok(s3[:2] == (3, 3), "three consecutive days build to three")

ok(streak_record(s1, D1 + 8 * 3600)[:2] == (1, 1), "second drive same day is a no-op")

s4 = streak_record(s3, D1 + 4 * DAY)
ok(s4[:2] == (1, 3), "missed day resets current but keeps best")

back = streak_record(streak_record(FRESH, D1 + 3 * DAY), D1)
ok(back[:2] == (1, 1), "clock moving backwards does not corrupt the streak")
ok(back[2] == streak_record(FRESH, D1 + 3 * DAY)[2], "backwards clock keeps last played")

# --- projection and risk
ok(streak_projected(FRESH, D1) == 1, "projection with no history is one")
ok(streak_projected(s1, D1) == 1, "playing again today does not advance")
ok(streak_projected(s1, D1 + DAY) == 2, "tomorrow advances to two")
ok(streak_projected(s1, D1 + 5 * DAY) == 1, "a gap projects back to one")
ok(streak_at_risk(s1, D1) is False, "same day is not at risk")
ok(streak_at_risk(s1, D1 + DAY) is True, "one day later is at risk")
ok(streak_at_risk(s1, D1 + 3 * DAY) is False, "already broken is not at risk")

# --- question freshness
COOLDOWN = 14 * DAY
seen = {"recent": D1 - 2 * DAY, "stale": D1 - 30 * DAY}
ok(freshness_rank(seen, "unseen", D1, COOLDOWN) == 0, "unseen ranks first")
ok(freshness_rank(seen, "stale", D1, COOLDOWN) == 1, "past cooldown ranks second")
ok(freshness_rank(seen, "recent", D1, COOLDOWN) == 2, "recently asked ranks last")

hist = {"q0": D1 - 1 * DAY, "q1": D1 - 1 * DAY, "q2": D1 - 1 * DAY}
order = order_by_freshness(["q0", "q1", "q2", "q3", "q4", "q5"], hist, COOLDOWN, D1)
ok(set(order[:3]) == {"q3", "q4", "q5"}, "unseen questions come first")

hist2 = {"q0": D1 - 1 * DAY, "q1": D1 - 40 * DAY, "q2": D1 - 20 * DAY}
ok(order_by_freshness(["q0", "q1", "q2"], hist2, COOLDOWN, D1) == ["q1", "q2", "q0"],
   "previously asked come back oldest first")

ok(order_by_freshness(["q0", "q1", "q2"], {}, COOLDOWN, D1) == ["q0", "q1", "q2"],
   "no history leaves the incoming shuffle alone")

pruned = prune({"old": D1 - 200 * DAY, "new": D1 - 1 * DAY}, 120 * DAY, D1)
ok("old" not in pruned and "new" in pruned, "prune drops only old entries")

# --- trailing budget: a command must not swallow the answer after it
for said, want in [
    # stop ends the drive, so it must be said and nothing else.
    ("I'm done thinking, it's Napoleon", None),
    ("that's enough, it's Rome", None),
    ("stop", "stop"),
    ("stop the game", "stop"),
    ("that's enough", "stop"),
    # skip would throw away the guess that follows it.
    ("I don't know, maybe Napoleon", None),
    ("I don't know", "skip"),
    ("skip this one", "skip"),
    ("no idea", "skip"),
    # recoverable commands get more slack, but not unlimited.
    ("hold on", "pause"),
    ("hold on a second", "pause"),
    ("hold on, is it Rome", None),
    ("can you repeat that", "repeatQuestion"),
    ("how many questions left", "howManyLeft"),
]:
    got = command(said)
    ok(got == want, f"trailing budget {said!r}: want {want}, got {got}")

# The guess rescued from a skip must actually be graded.
ok(grade(["I don't know, maybe Napoleon"], NAP)[0] == "correct",
   "a guess after 'I don't know' is graded, not skipped")

print(f"{'FAIL' if fails else 'PASS'}: {checks - len(fails)}/{checks} cases")
for f in fails:
    print("  -", f)
sys.exit(1 if fails else 0)
