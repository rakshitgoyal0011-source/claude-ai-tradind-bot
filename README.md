# DriveQuiz — Phase 1

Voice-only, ETA-aware trivia for drivers. Phase 1 is the loop end to end with
a static 20-question pack and a manual "I have N minutes" input.

> **Repo name mismatch.** This landed in `claude-ai-tradind-bot` because it was
> the only empty repository attached to the session. Nothing here relates to
> trading. Move it to a `drivequiz` repo whenever you like; nothing depends on
> the name.

## What is here

```
DriveQuizKit/                    Swift package. Pure logic, no AVFoundation.
  Sources/DriveQuizKit/
    TextNormalizer.swift         Case, accents, punctuation, fillers, numbers
    Levenshtein.swift            Edit distance with an early length bail-out
    AnswerGrader.swift           Sliding-window fuzzy grading
    CommandMatcher.swift         repeat / skip / pause / how many left / stop
    PackPlanner.swift            Fits questions to available seconds
    Question.swift, Session.swift, SeededGenerator.swift
  Tests/DriveQuizKitTests/       XCTest suite for all of the above

DriveQuiz/                       App sources
  App/                           Entry point, feature flags
  UI/                            StartView (only interactive screen), SessionCardView
  Audio/                         AudioSessionController, Speaker, Listener, AudioState
  Game/                          GameEngine, SessionClock, CardState
  Content/                       PackLoader + Packs/starter-20.json

tools/                           Python mirror of the grading rules, see Verification
```

## Assumptions I made

You said resume without answering the open questions, so these are the calls I
made. Each is a one-line change if you disagree.

| Question | Assumption |
|---|---|
| Pack sizing | Draw questions across packs to fill a time budget, not whole-pack selection |
| `estimatedSeconds` | Whole turn: prompt, listen window, verdict, fact, and gaps |
| Silence | One nudge, then reveal the answer and move on. Counts as asked, not correct |
| Wrong answer | Speak the correct answer, then the fact |
| Score | Correct count. Streak is tracked and announced but does not multiply |
| `streak` on Session | In-drive streak. The daily streak is Phase 3 and gets its own field |
| "How many left" | Answers both questions and minutes in one breath |
| Pause and resume | Voice only. Microphone stays live through the pause for resume and stop |
| Barge-in | Not in Phase 1. Speaking and listening never overlap |
| Arriving mid-question | Finish the question. Never start one that will not fit before the summary |
| `difficulty` | Metadata only. Nothing adapts on it yet |
| Session name | The pack theme |
| "I don't know" | Treated as skip, not as a wrong answer |

## Verification status

**Verified.** The grading and command rules were executed against a 49-case
corpus and all pass. Because no Swift toolchain is reachable in the build
container, `tools/grader_reference.py` is a hand-maintained Python port of the
same rules, and `tools/run_corpus.py` runs the corpus through it:

```
cd tools && python3 run_corpus.py     # PASS: 49/49 cases
```

That validates the algorithm, including the two false-positive traps it was
written to catch: "the answer is a stop sign" must not quit the game, and
"dome" must not be accepted for "Rome".

**Not verified.** Nothing here has been compiled. There is no Swift toolchain
and no Xcode in the container, and `download.swift.org` is blocked by the
proxy. Expect to fix small compile errors on first build. The XCTest suite
mirrors the Python corpus, so run it first.

## Getting it into Xcode

The `.xcodeproj` is not checked in, because a hand-written project file is
more likely to be corrupt than useful. Create it once:

1. New iOS App, SwiftUI, name it DriveQuiz, minimum deployment iOS 17.
2. Drag the `DriveQuiz/` folders in as groups.
3. Add `DriveQuizKit` as a local package dependency, then link it to the app target.
4. Add `Content/Packs/starter-20.json` to Copy Bundle Resources.
5. Add these Info.plist keys:

```
NSMicrophoneUsageDescription        DriveQuiz listens for your spoken answers.
NSSpeechRecognitionUsageDescription DriveQuiz turns your spoken answers into text on your device.
UIBackgroundModes                   audio
```

## Design decisions worth knowing

**One owner of the audio session.** `AudioSessionController` is the only thing
that touches `AVAudioSession`. The game engine goes through it. This is what
keeps a late recognizer callback from opening the microphone after the game
has ended.

**Speaking and listening never overlap.** `Speaker.speak` returns only after
the utterance finishes, and `hear` waits another 250 ms for the route to
settle. Without this the phone microphone transcribes our own voice coming
back out of the car stereo.

**On-device recognition.** `requiresOnDeviceRecognition` is set whenever the
locale model is available. Cars lose signal in tunnels, and server recognition
would fail exactly when the driver is mid-answer. The accuracy cost on proper
nouns is bought back by loading each question's accepted answers into
`contextualStrings`, which is the largest single accuracy win in the app.

**Bluetooth profile.** The session requests `.allowBluetoothA2DP` and
deliberately not `.allowBluetooth`. Asking for a Bluetooth microphone drops
the head unit into the hands-free profile, which degrades everything including
our own voice. Input falls back to the built-in microphone. This needs testing
in a real car.

**Silence cutoff.** The listen window is 8 seconds, but a 1.4 second pause
after the last partial result ends it early. A driver who answers in two
seconds should not wait out the full eight. This matters a lot for whether the
game feels alive.

## Known limitations

- **The pack is shorter than a commute.** Twenty questions is about 9.7 minutes
  of content. A 20-minute drive exhausts it at roughly the halfway point, and
  the game wraps up early saying so. Phase 1 ships one pack by design, but you
  will notice this the first time you play it.
- **Navigation prompts duck us with no notification.** There is no reliable API
  for detecting that another app is ducking you, so a nav prompt over a
  question is covered by "repeat" and nothing more.
- **Pause keeps the microphone live.** That is the cost of voice-only resume.
- **Interruption resume re-speaks the whole question** rather than resuming
  mid-sentence, which is the right call but does cost a few seconds.
