# DriveQuiz

Voice-only, ETA-aware trivia for drivers.

- **Phase 1** — the loop end to end, static 20-question pack, manual minutes. Done.
- **Phase 2** — real destination and ETA from MapKit, pack sizing from ETA. Done.
- **Phase 3** — persistence, daily streak, don't-repeat logic. Done.
- **Phase 4** — CarPlay behind the flag. Done, and untestable until the
  entitlement lands.

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
    DailyStreak.swift            Calendar-day streak arithmetic
    QuestionHistory.swift        What this driver has already been asked
    PlayerProgress.swift         Everything remembered between drives
    Question.swift, Session.swift, SeededGenerator.swift
  Tests/DriveQuizKitTests/       XCTest suite for all of the above

DriveQuiz/                       App sources
  App/                           Entry point, feature flags
  UI/                            StartView (only interactive screen), SessionCardView
  Audio/                         AudioSessionController, Speaker, Listener, AudioState
  Game/                          GameEngine, SessionClock, CardState
  Trip/                          LocationProvider, ETAProvider, ETAClock, DestinationSearch
  Storage/                       FileProgressStore, JSON in Application Support
  CarPlay/                       GameCoordinator, NowPlayingController, CarPlaySceneDelegate
  Content/                       PackLoader + five packs, 100 questions

tools/
  verify.sh                      Runs everything that can actually execute here
  grader_reference.py            Python mirror of the pure logic
  run_corpus.py                  92-case corpus against the mirror
  validate_packs.py              Content checks against the real normalizer
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
| Daily streak | Calendar days, not 24-hour periods. Two drives in a day count once |
| Question cooldown | 14 days before a question can come back |
| History retention | 120 days, then pruned so the file cannot grow forever |
| Corrupt progress file | Renamed aside, game starts fresh rather than refusing to run |
| CarPlay screen contents | Session name, score, day count. Never the question |
| Transport controls | Next is skip, previous is repeat, play/pause is resume/pause |
| CarPlay disconnect | The game keeps running on the phone, only the screen goes |
| Theme choice | A picker on the setup screen. Mixed draws from all five packs |
| One unreadable pack | Skipped, the drive still starts on the others |

## Verification status

**Verified.** Run everything that can execute here with one command:

```
./tools/verify.sh
```

That is a 92-case logic corpus and a content check over all 100 questions,
both currently clean. No Swift toolchain is reachable in the build container,
so `tools/grader_reference.py` is a hand-maintained Python port of the same
rules and the corpus runs against it.

`validate_packs.py` runs the real normalizer and command matcher over every
question, so content that would break the voice loop fails here rather than in
the car: an answer the grader would hear as a command, an answer sitting inside
its own prompt, a duplicate id, a bare-letter answer that fuzzy matching cannot
be trusted with. It caught two real problems on the first run, a `D` alternate
for "vitamin D" and a `Leonardo` alternate for DiCaprio that collided with da
Vinci in the starter pack. It also produced sixteen false alarms from a rule of
mine that flagged every short answer; numeric answers like `8` are safe because
answers of four characters or fewer get zero edit slack and need an exact
match, so the rule now flags only bare letters.

That covers grading, command matching, planner budget arithmetic, the wrap-up
gate, the ETA countdown, daily streak transitions and question freshness
ordering. It includes the two false-positive traps the grader was written
around: "the answer is a stop sign" must not quit the game, and "dome" must
not be accepted for "Rome".

Running it caught a wrong test expectation of mine: the streak tests were
anchored at 22:13 UTC, so "eight hours later" crossed midnight and the
same-day case was not testing what it claimed. The anchor is now mid-morning.

Day arithmetic in the mirror uses whole 86400-second steps, which matches the
Swift only for a fixed-offset calendar. The Swift goes through `Calendar`, so
daylight saving behaviour is covered by XCTest alone.

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
4. Add every file in `Content/Packs/` to Copy Bundle Resources. `PackLoader.bundledPackNames` lists them, so a pack that is not copied is skipped at launch rather than crashing.
5. Add these Info.plist keys:

```
NSMicrophoneUsageDescription         DriveQuiz listens for your spoken answers.
NSSpeechRecognitionUsageDescription  DriveQuiz turns your spoken answers into text on your device.
NSLocationWhenInUseUsageDescription  DriveQuiz uses your location to size the game to your drive.
UIBackgroundModes                    audio
```

Set `FeatureFlags.destinationAndETAEnabled = false` to hide the destination
picker entirely, which also means the app never asks for location.

## Turning CarPlay on

Nothing in `CarPlay/` runs today. Two separate things gate it, and both must
be true:

1. **`FeatureFlags.carPlayEnabled`**, currently `false`. It keeps Now Playing
   and the remote commands dormant, so the phone build behaves exactly as it
   did in Phase 3.
2. **The `com.apple.developer.carplay-audio` entitlement**, which Apple has
   not approved yet. Without it the scene is never created, whatever the flag
   says.

When the entitlement lands, flip the flag and add the scene manifest to
Info.plist so UIKit knows which class to instantiate:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
  <key>UIApplicationSupportsMultipleScenes</key><true/>
  <key>UISceneConfigurations</key>
  <dict>
    <key>CPTemplateApplicationSceneSessionRoleApplication</key>
    <array>
      <dict>
        <key>UISceneClassName</key>
        <string>CPTemplateApplicationScene</string>
        <key>UISceneConfigurationName</key>
        <string>DriveQuiz-CarPlay</string>
        <key>UISceneDelegateClassName</key>
        <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
      </dict>
    </array>
  </dict>
</dict>
```

And in the entitlements file:

```xml
<key>com.apple.developer.carplay-audio</key><true/>
```

Declaring `UIApplicationSupportsMultipleScenes` changes how SwiftUI creates the
phone window too. Test the plain phone build immediately after adding this,
before worrying about the car.

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

**Alternates that look redundant are not.** "Beatles" and "the Beatles"
collapse onto the same tokens, so listing both adds nothing to grading. They
are kept because `acceptedAnswers` is also what feeds the recognizer's
`contextualStrings`, and biasing it toward more surface forms is the largest
accuracy lever the app has. Redundant for grading is not redundant for
recognition.

**The car screen never shows the question.** Constraint two says no question
may be answerable from a screen, and a prompt on the dash is exactly that. Now
Playing gets the session name, the score and the day count, which is the same
thing the phone card shows. The template is `CPNowPlayingTemplate` and nothing
else, because a browsable list of packs would be another screen to read.

**One command path.** A CarPlay button and a spoken word take the same route
through the game. Remote controls set an external command and end the current
listen window early, so a button press does not wait out the eight seconds.
The external command is consumed whether or not it was legal in the current
state, so it can never fire twice.

**Progress failures never block a drive.** A corrupt or version-incompatible
`progress.json` is renamed aside and the game starts from fresh progress.
Losing a streak is bad; refusing to start because a file will not parse is
worse, and the driver is already moving. Writes are atomic, so a crash
mid-save cannot leave a truncated file.

**Freshness beats variety.** The planner shuffles first, then stable-orders by
freshness: never-asked questions in shuffled order, then anything past its
14-day cooldown oldest first, then recently asked ones. Repeats only happen
once the unseen pool is empty.

**Silence cutoff.** The listen window is 8 seconds, but 1.4 seconds of quiet
after the last partial result ends it early. A driver who answers in two seconds
should not wait out the full eight. This matters a lot for whether the game
feels alive.

## Known limitations

- **Content is now 46 minutes, so a long drive can still run dry.** Five packs
  and 100 questions cover roughly three or four commutes before the 14-day
  cooldown starts handing back repeats. That is enough for the ordering to
  matter, which it was not at 20 questions, but a daily driver will still
  outrun it inside a fortnight. Picking a single theme shrinks the pool to
  about nine minutes, so a themed long drive runs out sooner.
- **The question facts have not been fact-checked by anyone but me.** The
  validator checks structure and voice-safety, not truth.
- **The streak is announced before it is earned.** The intro says "day 5 in a
  row" based on a projection, but the drive is only recorded once at least one
  question has been asked. Starting and immediately stopping does not count.
- **A failed ETA refresh counts down from the last good estimate.** There is no
  spoken notice when that happens, only `ETAClock.lastRefreshFailed`.
- **Navigation prompts duck us with no notification.** There is no reliable API
  for detecting that another app is ducking you, so a nav prompt over a question
  is covered by "repeat" and nothing more.
- **Pause keeps the microphone live.** That is the cost of voice-only resume.
- **Interruption resume re-speaks the whole question** rather than resuming
  mid-sentence, which is the right call but costs a few seconds.
- **Nothing in the CarPlay layer has ever run.** It cannot, until the
  entitlement is approved. It is written to the documented API and reviewed,
  and that is all that can be claimed. Treat the whole folder as unverified.
- **`GameCoordinator` is a singleton.** CarPlay scenes are built by UIKit
  outside the SwiftUI view tree, so the two need a meeting point. It holds a
  weak engine reference and no logic, but it is still a global.
- **Phase 4 added no pure logic**, so the corpus count is unchanged at 92. The
  command mapping and the Now Playing bridge live in the app target, which has
  no test target.
