"""Grades realistic spoken answers against the questions actually shipped.

The corpus in run_corpus.py uses fixtures. This one loads the real pack JSON
and asks whether a driver saying the natural thing gets credit, which is the
question that decides whether the game is any fun.
"""
import json
import pathlib
import sys

from grader_reference import grade, command

PACK_DIR = pathlib.Path(__file__).resolve().parent.parent / "DriveQuiz" / "Content" / "Packs"

QUESTIONS = {}
for path in PACK_DIR.glob("*.json"):
    for q in json.loads(path.read_text())["questions"]:
        QUESTIONS[q["id"]] = q

# (question id, what the driver said, expected verdict)
CASES = [
    # Bare surnames, the most common way people answer a "who" question.
    ("s20",   "Armstrong",                     "correct"),
    ("s20",   "uh, Neil Armstrong",            "correct"),
    ("his08", "Churchill",                     "correct"),
    ("his08", "I think it's Winston Churchill", "correct"),
    ("his04", "Curie",                         "correct"),
    ("his04", "Madame Curie",                  "correct"),
    ("his10", "Fleming",                       "correct"),
    ("cul05", "Spielberg",                     "correct"),
    ("cul14", "John Williams",                 "correct"),

    # Articles the recogniser will or will not include.
    ("cul01", "Beatles",                       "correct"),
    ("cul01", "the Beatles",                   "correct"),
    ("geo07", "the Vatican",                   "correct"),
    ("geo07", "Vatican City",                  "correct"),
    ("geo06", "the Ural Mountains",            "correct"),
    ("geo02", "the Seine",                     "correct"),

    # Numbers, spoken and transcribed.
    ("sci01", "eight",                         "correct"),
    ("sci01", "8",                             "correct"),
    ("sci14", "about eight minutes",           "correct"),
    ("cul04", "the piano",                     "correct"),
    ("his01", "1912",                          "correct"),

    # Multi-word and partial answers.
    ("his20", "Hiroshima",                     "correct"),
    ("his20", "Hiroshima and Nagasaki",        "correct"),
    ("sci20", "white cells",                   "correct"),
    ("geo18", "the Mariana Trench",            "correct"),
    ("his15", "Queen Elizabeth",               "correct"),
    ("cul17", "disc jockey",                   "correct"),
    ("geo04", "South America",                 "correct"),

    # Wrong answers must stay wrong.
    ("s20",   "Buzz Aldrin",                   "incorrect"),
    ("his08", "Napoleon",                      "incorrect"),
    ("cul01", "the Rolling Stones",            "incorrect"),
    ("geo07", "Monaco",                        "incorrect"),
    ("sci01", "six",                           "incorrect"),
    ("his01", "1914",                          "incorrect"),
]

# Things a driver says that are commands, not answers. These must be caught
# before grading, or "I don't know" would be marked wrong.
COMMAND_CASES = [
    ("I don't know",        "skip"),
    ("no idea",             "skip"),
    ("say that again",      "repeatQuestion"),
    ("how much longer",     "howManyLeft"),
    ("hold on",             "pause"),
]

fails = []
checks = 0

for qid, said, expected in CASES:
    checks += 1
    q = QUESTIONS.get(qid)
    if q is None:
        fails.append(f"{qid}: no such question")
        continue
    answers = [q["canonicalAnswer"]] + list(q["alternates"])
    got = grade([said], answers)[0]
    if got != expected:
        fails.append(f"{qid} {said!r}: expected {expected}, got {got} "
                     f"(answers: {answers})")

for said, expected in COMMAND_CASES:
    checks += 1
    got = command(said)
    if got != expected:
        fails.append(f"command {said!r}: expected {expected}, got {got}")

print(f"{'FAIL' if fails else 'PASS'}: {checks - len(fails)}/{checks} content cases")
for f in fails:
    print("  -", f)
sys.exit(1 if fails else 0)
