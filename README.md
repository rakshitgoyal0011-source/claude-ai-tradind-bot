# DriveQuiz

Voice-only, ETA-aware trivia for drivers.

- **Phase 1** — the loop end to end, static 20-question pack, manual minutes. Done.
- **Phase 2** — real destination and ETA from MapKit, pack sizing from ETA. Done.
- **Phase 3** — persistence, daily streak, don't-repeat logic. Not started.
- **Phase 4** — CarPlay behind the flag. Not started.

> **Repo name mismatch.** This landed in `claude-ai-tradind-bot` because it was
> the only empty repository attached to the session. Nothing here relates to
> trading. Move it to a `drivequiz` repo whenever you like; nothing depends on
> the name.

## What is here

```
DriveQuizKit/                    Swift package. Pure logic, no AVFoundation, no MapKit.
  Sources/DriveQuizKit/
    TextNormalizer.swift         Case, accents, punctuation, fillers, numbers
    Levenshtein.swift            Edit distance with an early length bail-out
    AnswerGrader.swift           Sliding-window fuzzy grading
    CommandMatcher.swift         repeat / skip / pause / resume / how many left / stop
    PackPlanner.swift            Fits questions to available seconds
    ETASnapshot.swift            Arrival estimate plus countdown maths
    Question.swift, Session.swift, SeededGenerator.swift
  Tests/DriveQuizKitTests/       XCTest suite for all of the above

DriveQuiz/                       App sources
  App/                           Entry point, feature flags
  UI/                            StartView (only interactive screen), SessionCardView
  Audio/                         AudioSessionController, Speaker, Listener, AudioState
  Game/                          GameEngine, SessionClock, CardState
  Trip/                          LocationProvider, ETAProvider, ETAClock, DestinationSearch
  Content/                       PackLoader + Packs/starter-20.json

tools/                           Python mirror of the pure logic, see Verification
```

## Assumptions I made

You said resume without answering the open design questions, so these are the
calls I made. Each is a one-line change if you disagree.

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
| Arriving mid-question | Finish the question. Never start one that will not fit |
| `difficulty` | Metadata only. Nothing adapts on it yet |
| Session name | The pack theme |
| "I don't know" | Treated as skip, not as a wrong answer |
| Pausing the game on an ETA drive | Does **not** pause the countdown. See below |
| ETA refresh | Every 120 seconds. MapKit throttles directions requests |

## Verification status

**Verified.** The pure logic runs against a 72-case corpus and all pass. No
Swift toolchain is reachable in the build container, so
`tools/grader_reference.py` is a hand-maintained Python port of the same rules
and `tools/run_corpus.py` executes the corpus against it:

```
cd tools && python3 run_corpus.py     # PASS: 72/72 cases
```

That covers grading, command matching, planner budget arithmetic, the
wrap-up gate, and the ETA countdown. It includes the two false-positive traps
the grader was written around: "the answer is a stop sign" must not quit the
game, and "dome" must not be accepted for "Rome".

The seeded shuffle is deliberately **not** mirrored, because Swift's
`shuffled(using:)` index derivation is an implementation detail. Every planner
case uses equal-length questions, so selection counts stay order independent.
Seed determinism is covered by XCTest only.

**Not verified.** Nothing has been compiled. There is no Swift toolchain and no
Xcode in the container, and `download.swift.org` is blocked by the proxy.
Expect to fix small compile errors on the first build. The XCTest suite mirrors
the Python corpus, so run it first. Nothing in `Trip/` has ever touched a real
GPS, a real route, or a real car.

## Getting it into Xcode

The `.xcodeproj` is not checked in, because a hand-written project file is more
likely to be corrupt than useful. Create it once:

1. New iOS App, SwiftUI, name it DriveQuiz, minimum deployment iOS 17.
2. Drag the `DriveQuiz/` folders in as groups.
3. Add `DriveQuizKit` as a local package dependency, then link it to the app target.
4. Add `Content/Packs/starter-20.json` to Copy Bundle Resources.
5. Add these Info.plist keys:

```
NSMicrophoneUsageDescription         DriveQuiz listens for your spoken answers.
NSSpeechRecognitionUsageDescription  DriveQuiz turns your spoken answers into text on your device.
NSLocationWhenInUseUsageDescription  DriveQuiz uses your location to size the game to your drive.
UIBackgroundModes                    audio
```

Set `FeatureFlags.destinationAndETAEnabled = false` to hide the destination
picker entirely, which also means the app never asks for location.

## Design decisions worth knowing

**One owner of the audio session.** `AudioSessionController` is the only thing
that touches `AVAudioSession`. This is what keeps a late recognizer callback
from opening the microphone after the game has ended.

**Speaking and listening never overlap.** `Speaker.speak` returns only after
the utterance finishes, and `hear` waits another 250 ms for the route to
settle. Without this the phone microphone transcribes our own voice coming back
out of the car stereo.

**On-device recognition.** `requiresOnDeviceRecognition` is set whenever the
locale model is available. Cars lose signal in tunnels, and server recognition
would fail exactly when the driver is mid-answer. The accuracy cost on proper
nouns is bought back by loading each question's accepted answers into
`contextualStrings`, the largest single accuracy win in the app.

**Bluetooth profile.** The session requests `.allowBluetoothA2DP` and
deliberately not `.allowBluetooth`. Asking for a Bluetooth microphone drops the
head unit into the hands-free profile, degrading everything including our own
voice. Input falls back to the built-in microphone. Needs testing in a real car.

**Pausing the game does not pause the drive.** `ManualClock.pause` stops its
countdown, because those minutes are a number the driver typed. `ETAClock.pause`
is deliberately a no-op: a driver who pauses for two minutes still arrives at
the same moment, so they get fewer questions rather than questions after the car
has stopped. Same reasoning applies to phone-call interruptions.

**The plan is a queue, not a promise.** ETA-backed sessions are planned with a
1.3 contingency, so traffic that stretches the drive does not leave dead air.
The live clock, not the plan, decides when to stop. This is also why the spoken
intro never quotes a question count on an ETA drive.

**Questions stop at 90 seconds out, not at the summary.** `shouldStartNextQuestion`
checks two things: the drive must still be outside the wrap-up threshold, and
the question must be short enough to leave room for the closing summary. The
planner budgets against the same threshold, so it never queues questions into
the last 90 seconds that would never be asked.

**Silence cutoff.** The listen window is 8 seconds, but 1.4 seconds of quiet
after the last partial result ends it early. A driver who answers in two seconds
should not wait out the full eight. This matters a lot for whether the game
feels alive.

## Known limitations

- **The pack is shorter than a commute.** Twenty questions is 546 seconds of
  content, so a drive of about 11 minutes exhausts it and the game wraps up
  early saying so. One pack is Phase 1 by design, but you will notice it on the
  first real drive.
- **A failed ETA refresh counts down from the last good estimate.** There is no
  spoken notice when that happens, only `ETAClock.lastRefreshFailed`.
- **Navigation prompts duck us with no notification.** There is no reliable API
  for detecting that another app is ducking you, so a nav prompt over a question
  is covered by "repeat" and nothing more.
- **Pause keeps the microphone live.** That is the cost of voice-only resume.
- **Interruption resume re-speaks the whole question** rather than resuming
  mid-sentence, which is the right call but costs a few seconds.
