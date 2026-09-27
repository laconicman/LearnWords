# Release notes — 1.3.0 (build 10)

Draft App Store "What's New" text plus the validation record for this release. The What's New
blocks fit Apple's 4,000-character limit and are written to be pasted into App Store Connect
(`en-US` and `ru`).

## What's New — en-US

Pronunciation practice is fairer and calmer:

• The microphone now waits for real silence instead of a fixed pause — prompts finish speaking before recording opens, and the next question queues behind the answer reveal instead of cutting it off.
• Your first spoken attempt is still judged against the recognizer's best reading — but retries also credit its close alternatives, so a near-miss that real conversation would accept counts.
• The Listen button speaks the answer and marks the attempt as aided, so it weighs appropriately in your progress.

Typing and review:

• Typed answers match inflected forms — "went" counts for "go", and Russian case forms count for the dictionary word.
• New setting: a word counts as learned only after you produce it, not just recognize it.
• Double-tap a word in the list to look it up; a long press shows its statistics.

Import:

• LearnWords' own Anki exports import back correctly, and plain-text files whose headers or separators confused format detection restore again.
• Word lookup now works on the confirm-meanings screen too.

Plus a corrected Russian label for the "In memory (days)" slider.

## What's New — ru

Произношение стало честнее и спокойнее:

• Микрофон ждёт настоящей тишины, а не фиксированной паузы — вопрос договаривает до конца, а следующий встаёт в очередь за ответом, не обрывая его.
• Первая попытка по-прежнему сравнивается с лучшим вариантом распознавателя — но повторные попытки учитывают и близкие альтернативы, так что почти верный ответ, понятный в живой речи, засчитывается.
• Кнопка «Слушать» озвучивает ответ и помечает попытку как «с подсказкой» — она учитывается в прогрессе соответственно.

Ввод и повторение:

• Напечатанные ответы учитывают формы слова — «went» засчитывается за «go», а падежные формы — за словарное слово.
• Новая настройка: слово считается выученным только после того, как вы воспроизвели его сами, а не просто узнали.
• Двойное касание по слову в списке открывает словарь; долгое нажатие — статистику.

Импорт:

• Экспорт в Anki корректно импортируется обратно; текстовые файлы, чьи заголовки или разделители сбивали определение формата, восстанавливаются.
• Поиск слова работает и на экране подтверждения значений.

Плюс исправленная подпись слайдера «В памяти (дней)».

## Validation record

| Check | Result | Evidence |
|-------|--------|----------|
| Unit suite (simulator, iPhone 17 Pro, iOS 26.5) | 424 passed / 0 failed / 4 skipped | `/tmp/lw-final4.xcresult`, run on the release branch including the speech-test stabilization |
| Release archive + App Store export | Signed `.ipa` produced, distribution profile, `get-task-allow=false`, version 1.3.0 (10) | `xcodebuild archive` + `xcodebuild -exportArchive` |
| Compile warnings | Deprecation warnings resolved (`MobileCoreServices`, `kUTTypeText`, old picker init). One remaining: `SpeechManager.synthesizer` non-Sendable stored property — architectural, tracked | Clean Release build log |
| On-device pass | **Partial.** Informal pass by the owner on 2026-09-27 — "definitely better, worth publishing" — but the scripted scenarios in `docs/DeviceTestPlan.md` §§1–4, 6.1, 7.1–7.4, 9.1 were not all walked through. That list remains the formal record of what full device validation means for this tag. | Owner report |

## Known limitations carried into the release

- `correctAided` events written by 1.3.0 decode to nil on ≤1.2.2 — a second device on an older
  build silently un-grades them (not wrong, just ungraded). Safe forward, worth knowing if two
  devices share one iCloud account.
- TD-65: the review log does not record which recognizer reading matched or on which attempt —
  retry leniency is invisible to future analysis until that's added.
- TD-66: a failed "new set" tap reports nothing to the user.
