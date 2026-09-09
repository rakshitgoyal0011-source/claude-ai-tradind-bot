"""Line-for-line port of DriveQuizKit's normalizer, grader and command matcher.

No Swift toolchain is reachable in this container, so this mirror exists to
execute the grading rules against the same corpus the XCTest suite uses.
It validates the ALGORITHM, not the Swift compilation.
Keep it in sync by hand when the Swift changes.
"""
import unicodedata

FILLERS = {"uh","uhh","um","umm","erm","er","ah","ahh","aah","hmm","hm","mm","mmm",
           "like","well","so","okay","ok","yeah","yep","eh","oh"}
ARTICLES = {"a","an","the"}

LEAD_INS = [
    ["i","think","the","answer","is"], ["i","think","it","is"], ["i","think","its"],
    ["i","am","going","to","say"], ["im","going","to","say"], ["i","would","say"],
    ["i","wanna","say"], ["i","want","to","say"], ["let","me","think"],
    ["my","guess","is"], ["the","answer","is"], ["answer","is"], ["i","think"],
    ["i","guess"], ["id","say"], ["is","it"], ["was","it"], ["it","is"], ["its"],
    ["that","is"], ["thats"], ["maybe"], ["probably"], ["definitely"], ["obviously"],
]

NUMBERS = {"zero":"0","one":"1","two":"2","three":"3","four":"4","five":"5","six":"6",
           "seven":"7","eight":"8","nine":"9","ten":"10","eleven":"11","twelve":"12",
           "thirteen":"13","fourteen":"14","fifteen":"15","sixteen":"16","seventeen":"17",
           "eighteen":"18","nineteen":"19","twenty":"20","thirty":"30","forty":"40",
           "fifty":"50","sixty":"60","seventy":"70","eighty":"80","ninety":"90"}


def tokenize(raw):
    folded = unicodedata.normalize("NFKD", raw.lower())
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    folded = folded.replace("’", "").replace("'", "")
    cleaned = "".join(c if c.isalnum() else " " for c in folded)
    return cleaned.split()


def command_tokens(raw):
    base = tokenize(raw)
    if not base:
        return []
    filtered = [t for t in base if t not in FILLERS]
    return filtered or base


def strip_lead_ins(tokens):
    current = list(tokens)
    changed = True
    while changed and current:
        changed = False
        for phrase in LEAD_INS:
            if len(phrase) < len(current) and current[:len(phrase)] == phrase:
                current = current[len(phrase):]
                changed = True
                break
    return current


def normalize_tokens(raw):
    base = [NUMBERS.get(t, t) for t in tokenize(raw)]
    if not base:
        return []
    tokens = [t for t in base if t not in FILLERS] or base
    de_led = strip_lead_ins(tokens)
    tokens = de_led or tokens
    de_art = [t for t in tokens if t not in ARTICLES]
    return de_art or tokens


def levenshtein(a, b):
    if not a: return len(b)
    if not b: return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[len(b)]


def within(tol, a, b):
    if a == b: return True
    if tol <= 0: return False
    if abs(len(a) - len(b)) > tol: return False
    return levenshtein(a, b) <= tol


def max_edit_distance(ans):
    n = len(ans)
    if n <= 4: return 0
    if n <= 7: return 1
    if n <= 11: return 2
    return 3


def window_match(transcript, accepted, tol):
    accepted_text = " ".join(accepted)
    width = len(accepted)
    if len(transcript) < width:
        return within(tol, " ".join(transcript), accepted_text)
    for start in range(len(transcript) - width + 1):
        if within(tol, " ".join(transcript[start:start + width]), accepted_text):
            return True
    return False


def grade(candidates, accepted_answers, tolerance_override=None):
    usable = [t for t in (normalize_tokens(c) for c in candidates) if t]
    if not usable:
        return ("noSpeech", None)
    for accepted in accepted_answers:
        acc = normalize_tokens(accepted)
        if not acc:
            continue
        tol = tolerance_override if tolerance_override is not None \
            else max_edit_distance(" ".join(acc))
        for cand in usable:
            if window_match(cand, acc, tol):
                return ("correct", accepted)
    return ("incorrect", None)


PHRASES = [
    ("howManyLeft", [["how","many","questions","left"],["how","many","are","left"],
                     ["how","many","more"],["how","many","left"],["how","much","longer"],
                     ["how","much","time"],["how","long","left"],["how","far","along"]]),
    ("repeatQuestion", [["can","you","repeat"],["say","that","again"],["say","again"],
                        ["one","more","time"],["what","was","that"],["come","again"],
                        ["repeat","that"],["repeat"]]),
    ("resume", [["keep","going"],["start","again"],["carry","on"],["go","on"],
                ["im","back"],["unpause"],["resume"],["continue"]]),
    ("skip", [["next","question"],["i","dont","know"],["no","idea"],["skip","this"],
              ["skip","it"],["dunno"],["skip"],["pass"],["next"]]),
    ("pause", [["pause","the","game"],["hold","on"],["hang","on"],["pause"]]),
    ("stop", [["stop","the","game"],["thats","enough"],["im","done"],["end","game"],
              ["stop"],["quit"],["exit"]]),
]


def phrase_matches(tokens, phrase):
    if len(phrase) > len(tokens):
        return False
    if tokens[:len(phrase)] == phrase:
        return True
    if len(phrase) < 2:
        return False
    return any(tokens[i:i + len(phrase)] == phrase
               for i in range(len(tokens) - len(phrase) + 1))


def command(raw, allowed=None):
    tokens = command_tokens(raw)
    if not tokens:
        return None
    for name, variants in PHRASES:
        if allowed is not None and name not in allowed:
            continue
        for phrase in variants:
            if phrase_matches(tokens, phrase):
                return name
    return None
