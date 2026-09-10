"""Checks every question pack against the rules the voice loop depends on.

Runs the real normalizer and command matcher from grader_reference, so a
question that would collide with a voice command, or whose answer is already
sitting in its own prompt, fails here rather than in the car.

Note on alternates: "Beatles" and "the Beatles" collapse onto the same tokens,
so listing both adds nothing to GRADING. They are kept deliberately because
acceptedAnswers is also what feeds the recognizer's contextualStrings, and
biasing it toward more surface forms is the largest accuracy lever the app has.
Redundant-for-grading is not redundant for recognition.
"""
import json
import pathlib
import sys

from grader_reference import normalize_tokens, command, max_edit_distance

PACK_DIR = pathlib.Path(__file__).resolve().parent.parent / "DriveQuiz" / "Content" / "Packs"
REQUIRED = ("id", "prompt", "canonicalAnswer", "alternates",
            "factOneLiner", "difficulty", "estimatedSeconds")
DIFFICULTIES = {"easy", "medium", "hard"}

errors, warnings = [], []


def err(pack, qid, msg):
    errors.append(f"{pack}/{qid}: {msg}")


def warn(pack, qid, msg):
    warnings.append(f"{pack}/{qid}: {msg}")


def contains_subsequence(haystack, needle):
    if not needle or len(needle) > len(haystack):
        return False
    return any(haystack[i:i + len(needle)] == needle
               for i in range(len(haystack) - len(needle) + 1))


packs = sorted(PACK_DIR.glob("*.json"))
if not packs:
    sys.exit("no packs found")

seen_qids, seen_pack_ids, seen_prompts = {}, {}, {}
answer_usage = {}
total_questions = total_seconds = 0

for path in packs:
    data = json.loads(path.read_text())
    pack_id = data.get("id", path.stem)

    if pack_id in seen_pack_ids:
        errors.append(f"{pack_id}: duplicate pack id, also in {seen_pack_ids[pack_id]}")
    seen_pack_ids[pack_id] = path.name

    if not data.get("theme"):
        errors.append(f"{pack_id}: missing theme")

    for q in data.get("questions", []):
        qid = q.get("id", "?")
        total_questions += 1

        missing = [k for k in REQUIRED if k not in q]
        if missing:
            err(pack_id, qid, f"missing fields {missing}")
            continue

        total_seconds += q["estimatedSeconds"]

        if qid in seen_qids:
            err(pack_id, qid, f"duplicate question id, also in {seen_qids[qid]}")
        seen_qids[qid] = pack_id

        prompt_norm = normalize_tokens(q["prompt"])
        prompt_key = " ".join(prompt_norm)
        if prompt_key in seen_prompts:
            err(pack_id, qid, f"duplicate prompt, also {seen_prompts[prompt_key]}")
        seen_prompts[prompt_key] = f"{pack_id}/{qid}"

        if not q["prompt"].endswith("?"):
            warn(pack_id, qid, "prompt does not end in a question mark")
        if not q["factOneLiner"].endswith("."):
            warn(pack_id, qid, "fact does not end in a full stop")
        if q["difficulty"] not in DIFFICULTIES:
            err(pack_id, qid, f"bad difficulty {q['difficulty']!r}")
        if not 20 <= q["estimatedSeconds"] <= 60:
            err(pack_id, qid, f"estimatedSeconds {q['estimatedSeconds']} outside 20-60")

        answers = [q["canonicalAnswer"]] + list(q["alternates"])
        normalized = []

        for answer in answers:
            tokens = normalize_tokens(answer)
            if not tokens:
                err(pack_id, qid, f"answer {answer!r} normalizes to nothing")
                continue
            joined = " ".join(tokens)
            normalized.append(joined)

            # An answer the grader would hear as a command hijacks the turn.
            hit = command(answer)
            if hit:
                err(pack_id, qid, f"answer {answer!r} matches the {hit} command")

            # A one-character answer is only dangerous when it is a letter.
            # Short answers get zero edit slack, so "8" needs an exact match
            # and is safe, while a stray "d" in a transcript is not.
            if len(joined) < 2 and not joined.isdigit():
                err(pack_id, qid, f"answer {answer!r} is a bare letter, too risky to grade")
            if len(tokens) > 6:
                warn(pack_id, qid, f"answer {answer!r} is {len(tokens)} words, hard to say")

            # An answer sitting inside its own prompt gives the game away.
            if contains_subsequence(prompt_norm, tokens):
                err(pack_id, qid, f"answer {answer!r} appears in its own prompt")

        for joined in set(normalized):
            answer_usage.setdefault(joined, []).append(f"{pack_id}/{qid}")

# The same answer for two different questions is legal but dulls variety.
# Numbers are exempt: "4" is the honest answer to plenty of questions.
for answer, users in sorted(answer_usage.items()):
    if len(users) > 1 and not answer.isdigit():
        warnings.append(f"answer {answer!r} is shared by {', '.join(users)}")

print(f"packs: {len(packs)}   questions: {total_questions}   "
      f"content: {total_seconds}s ({total_seconds / 60:.1f} min)")
print(f"errors: {len(errors)}   warnings: {len(warnings)}")
for e in errors:
    print("  ERROR  ", e)
for w in warnings:
    print("  warn   ", w)
sys.exit(1 if errors else 0)
