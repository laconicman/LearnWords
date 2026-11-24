# Release notes — 1.4.0

Draft App Store "What's New" text plus the validation record for this release. The What's New
blocks fit Apple's 4,000-character limit and are written to be pasted into App Store Connect
(`en-US`, `ru` and `es` — the three shipped localisations). 1.4.0 is not yet tagged or
submitted: the build number and the tag/live dates get filled in when the owner cuts the
release.

## What's New — en-US

Answers reveal more:

• When an exercise shows the answer, the meaning's other correct answers — its remaining synonyms — appear under it.
• New setting in Settings → Study: show the answer's transcription under it. Off by default.

Fixes:

• Word sets: a change that fails to save — adding, renaming or deleting a set — now reports the error and refreshes the list, instead of looking like the tap never happened.
• Meanings left behind by deleted word sets are now removed at launch.

## What's New — ru

Ответы раскрываются подробнее:

• Когда упражнение показывает ответ, под ним теперь видны остальные правильные ответы этого значения — оставшиеся синонимы.
• Новая настройка в «Настройках» → «Обучение»: показывать транскрипцию ответа под ним. По умолчанию выключена.

Исправления:

• Наборы слов: изменение, которое не удалось сохранить — добавление, переименование или удаление набора, — теперь сообщает об ошибке и обновляет список, а не оставляет нажатие без ответа.
• Значения, оставшиеся после удаления наборов, теперь удаляются при запуске.

## What's New — es

Las respuestas revelan más:

• Cuando un ejercicio muestra la respuesta, las demás respuestas correctas de ese significado — sus sinónimos restantes — aparecen debajo de ella.
• Nuevo ajuste en Ajustes → Estudio: mostrar la transcripción de la respuesta debajo de ella. Desactivado por defecto.

Correcciones:

• Conjuntos de palabras: un cambio que no se puede guardar — añadir, renombrar o eliminar un conjunto — ahora avisa del error y refresca la lista, en lugar de dejar el toque sin respuesta.
• Los significados que quedaron sin conjunto se eliminan al iniciar la app.

## Validation record

| Check | Result | Evidence |
|-------|--------|----------|
| Unit suite (simulator, iPhone 17 Pro, iOS 26.5) | 499 passed / 4 failed / 4 skipped (argument-level counts) — the four failures are the pre-existing Match3 lemmatization cases that reproduce on 1.3.0 | `/tmp/lw-140.xcresult`, run on `main` at b03b5bb |
| Compile warnings | One remaining: `SpeechManager.synthesizer` non-Sendable stored property — architectural, tracked (same as 1.3.0) | Debug build log |
| Release archive + App Store export | Pending — release mechanics stay with the owner | — |
| On-device pass | Pending — issue #54 carries the scenarios waived at the 1.3.0 submission; the TD-36 footnotes add one new thing worth an eyeball (Dynamic Type wrapping) | — |

## Known limitations carried into the release

- `correctAided` events written by 1.3.0 and later decode to nil on ≤1.2.2 — a second device on
  an older build silently un-grades them (not wrong, just ungraded). Safe forward, worth
  knowing if two devices share one iCloud account.
- TD-65: the review log does not record which recognizer reading matched or on which attempt —
  retry leniency is invisible to future analysis until that's added.
- TD-36: the reveal's footnotes appear in a synchronous set beside the answer's cross-dissolve
  rather than as part of it — they pop rather than fade, and on a correct answer they are only
  up for the 0.1 s advance. Reasoned, not verified on device; if it reads badly it is a polish
  pass (register § TD-36).
- TD-26: the launch sweep waits on `whenInitialSyncSettled`, which fires on the first import
  event or an 8 s timeout — not proof the first import finished. During a large first sync a
  meaning can arrive before the set holding it, and an empty local set list could read as a
  false orphan whose deletion would mirror back to CloudKit (register § TD-26).
