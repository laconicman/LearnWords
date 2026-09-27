# On-device test plan

**Why this exists.** The unit suite (474 cases, simulator) cannot prove the physical layer:
whether speech is actually audible, whether the microphone opens and closes at the right
moments, whether the audio session survives interruptions. These are the checks that must
run on a real iPhone before a build is submitted. Each scenario lists steps, the expected
behaviour, and the change it would catch regressing — so a failure points at a PR, not a
mystery.

**Conventions.** Run on the release build (or a Debug build signed normally — never an
unsigned one; CloudKit traps without its entitlement). Check the orange mic indicator in the
status bar wherever a scenario touches the microphone; it is ground truth for "is recording".

---

## 1. Speech playback & lifecycle (PR #32, TD-64)

| # | Steps | Expected |
|---|-------|----------|
| 1.1 | Start a phonetics sitting; answer correctly | The question prompt finishes audibly; the answer reveal plays completely; the **next** prompt queues behind it without cutting anything off |
| 1.2 | Answer correctly on a word with a long pronunciation | Mic does not open while the prompt/reveal is still playing (watch the orange dot) |
| 1.3 | Tap Listen twice quickly | One playback, no double-voice overlap (0.8 s debounce) |
| 1.4 | Start speaking an answer; leave the exercise mid-utterance | All speech stops; no audio continues over the previous screen |
| 1.5 | Correct answer → immediately tap Back before the reveal finishes | Reveal stops, nothing is queued into the next screen |

## 2. Phonetics recognition (PR #33, attempt-gate branch)

| # | Steps | Expected |
|---|-------|----------|
| 2.1 | First launch of phonetics; tap record before ever granting speech permission | Permission sheet appears **on the tap** — not on screen appearance |
| 2.2 | Say a word the recogniser plausibly mis-ranks (e.g. say "fox" such that "box" is its best guess but "fox" an alternative) as the *first* attempt | Not credited — the first attempt wants the best reading |
| 2.3 | Same utterance as the *second* attempt on the same question | Credited (judged, not verbatim) |
| 2.4 | Answer correctly; check the word's statistics afterwards | The event recorded `correctJudged`; the logged response is what the recogniser thought it heard |
| 2.5 | Automatic mode on: answer, let the next question appear | Mic opens only after the prompt finishes speaking — no truncation |
| 2.6 | Automatic mode on: press Listen while the mic is waiting | Mic does not open while the answer plays (TTS must not be graded as learner speech) |
| 2.7 | Leave a phonetics exercise while the mic is open | Orange indicator goes out with the screen |

## 3. Listen / aided (PR #34)

| # | Steps | Expected |
|---|-------|----------|
| 3.1 | Tap Listen on a question, then answer correctly by voice | Answer counts but is graded **aided** — check the event shows `correctAided` weight (stats/ring reflect the weaker evidence) |
| 3.2 | Tap Listen twice inside ~1 s | The second tap plays nothing and does not *also* mark aided — grading unchanged vs a single listen |
| 3.3 | Dictation exercise: Listen → type the answer | Same aided grading applies to typed answers |

## 4. Typed answers / lemma matching (PR #36)

| # | Steps | Expected |
|---|-------|----------|
| 4.1 | Dictation on an English word with an irregular plural | "mice" answers "mouse" correctly |
| 4.2 | Russian word in an inflected form | Genitive/case forms of the answer word are accepted |
| 4.3 | A different lexeme ("wolf" for "fox") | Still marked wrong — lemmatisation must not merge unrelated words |

## 5. Settings & reminders (PR #35, TD-62 pending)

| # | Steps | Expected |
|---|-------|----------|
| 5.1 | Settings → Study → toggle "require production" | Switch state persists across relaunch; learned-word status of a borderline word changes accordingly |
| 5.2 | Change reminder time; kill the app; relaunch | Next reminder fires at the new time (verify in Settings →Notifications or by waiting for it) |
| 5.3 | Relaunch the app twice without touching anything | Second launch is not visibly slower (the unconditional-rebuild cost is TD-62's target — note the launch time now so the improvement is measurable later) |

## 6. Persistence & sync

| # | Steps | Expected |
|---|-------|----------|
| 6.1 | Exercise a few words; force-quit; relaunch | Session state and stats consistent; no lost events |
| 6.2 | Two devices on one iCloud account (or note for later) | Events written by this build appear on the other; **known limitation**: a device still on ≤1.2.2 silently ignores `correctAided` events (decodes to nil → ungraded, not wrong) |
| 6.3 | Airplane mode mid-sitting | Everything keeps working; sync resumes when connectivity returns |

## 7. Interruptions (the things simulators never do)

| # | Steps | Expected |
|---|-------|----------|
| 7.1 | Phone call or Siri during TTS playback | Call wins; on return the app state is intact |
| 7.2 | Mic open → lock the screen → unlock | Indicator goes out; the surface returns to a tappable state, not stuck "listening" |
| 7.3 | Unplug headphones / toggle Bluetooth mid-playback | Audio reroutes or stops cleanly, no crash |
| 7.4 | Background the app with the mic open, foreground it | Mic closed or cleanly recoverable; never a live mic over a backgrounded app |

## 8. Performance sanity

| # | Steps | Expected |
|---|-------|----------|
| 8.1 | Cold-launch with the real library | No visible stall (reminder rebuild + progress index — TD-62/TD-56 territory; record the time) |
| 8.2 | Long sitting (30+ questions) | No growing lag in question transitions — a leak in surface/speech teardown shows here |

---

**Pass criteria for 1.3.0 submission:** every scenario in §§1–4 plus 6.1, 7.1–7.4. §5–8 are
advisory unless a scenario fails — then it becomes a blocker by definition. Record results
against the tag (`1.3.0`) in the release notes.
