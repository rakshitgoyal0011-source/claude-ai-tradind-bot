# DriveQuiz — working notes

Voice-only trivia sized to a drive. iOS 17+, SwiftUI, Swift 5.9.

## Build and verify

```sh
./scripts/bootstrap.sh          # project.yml -> DriveQuiz.xcodeproj (needs xcodegen)
cd DriveQuizKit && swift test   # the logic tests, fastest signal
./tools/verify.sh               # runs on any machine, no Swift needed
```

`tools/` holds a Python mirror of the pure logic. It exists because the
container this was written in has no Swift toolchain, and it is kept in sync
by hand. **If you change `DriveQuizKit`, change the mirror too**, or
`verify.sh` is quietly testing the old rules.

## The four constraints that define the product

These are not preferences. A change that breaks one is wrong even if it
compiles and tests pass.

1. **Voice in, voice out.** After Start, the driver never looks at or touches
   the screen.
2. **No question may need a screen.** That rules out images, reading, spelling,
   ordinals, and chemical symbols. It also rules out showing the prompt on
   CarPlay, which would make the dash a way to answer.
3. **The card is static.** Session name, score, stop. Nothing that rewards a
   glance.
4. **Length comes from the drive, not a question count.**

## Invariants worth protecting

- **One owner of `AVAudioSession`.** `AudioSessionController` and nothing else.
- **Speaking and listening never overlap.** `Speaker.speak` returns only when
  the utterance is done, and `hear` waits another 250 ms. Without this the
  microphone transcribes our own voice out of the car speakers.
- **Every spoken line goes through `GameEngine.speak`.** It stamps the time
  for the watchdog. Calling `audio.say` directly blinds the watchdog.
- **Answers and commands normalize differently.** `commandTokens` must not
  strip lead-ins, or "the answer is a stop sign" quits the game.
- **Commands must lead the utterance**, with a trailing-word budget by risk:
  zero for stop and skip, two for the rest. This is what stops a command
  swallowing the answer after it.
- **Pausing the game does not pause an ETA drive.** You still arrive at the
  same time, so you get fewer questions, not questions after you park.
- **Nothing may fail silently.** See below.

## Silence is this app's crash

Three review passes found ten defects and every one presented the same way: no
crash, no error, just a car that stopped talking. A driver who cannot look at
the screen cannot tell a thinking pause from a dead app.

`SilenceWatchdog` is the backstop. If nothing has been spoken for 30 seconds
it tries to unstick the loop; at 60 it ends the drive and says so on the card.
Pause and audio interruptions are exempt, because that silence is asked for or
audible.

When you add a failure path, ask what the driver hears. "Nothing" is never the
answer.

## State of things

- Phases 1 to 4 are written. CarPlay is behind `FeatureFlags.carPlayEnabled`
  and the entitlement Apple has not granted.
- **Nothing has ever been compiled or run.** Expect real work on the first
  build, and treat the trip and CarPlay layers as completely unexercised.
- Content is 5 packs, 100 questions, about 46 minutes. Facts are not
  independently checked.
