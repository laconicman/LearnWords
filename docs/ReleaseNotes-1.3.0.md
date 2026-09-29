# Release notes — 1.3.0 (build 10)

App Store "What's New" text plus the validation record for this release. The What's New
blocks fit Apple's 4,000-character limit and are written to be pasted into App Store Connect
(`en-US`, `ru` and `es` — the three shipped localisations). 1.3.0 (build 10) was tagged on
2026-09-27 and is live on the App Store as of 2026-09-29.

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

## What's New — es

La práctica de pronunciación es más justa y más tranquila:

• El micrófono espera ahora un silencio real en lugar de una pausa fija: las indicaciones terminan de hablar antes de que se abra la grabación, y la siguiente pregunta espera a que se revele la respuesta en lugar de cortarla.
• El primer intento hablado se sigue juzgando por la mejor lectura del reconocedor, pero los reintentos también aceptan sus alternativas cercanas, así que un casi acierto que una conversación real admitiría cuenta.
• «Escuchar» pronuncia la respuesta que buscabas — y la marca honestamente como asistida, para que pese lo que corresponde en tu progreso.

Escritura y repaso:

• Las respuestas escritas se comparan por su forma de diccionario: «mice» vale por «mouse», «went» por «go», «кошки» por «кошка».
• Nuevo en Ajustes: contar una palabra como aprendida solo tras producirla, no solo reconocerla.
• Doble toque sobre una palabra de la lista para consultarla; una pulsación larga muestra sus estadísticas.

Importación:

• Un archivo Anki — incluso exportado por el propio LearnWords — se reimporta correctamente, y los archivos de texto cuyos encabezados o separadores confundían la detección de formato vuelven a restaurarse.
• La consulta de palabras funciona también en la pantalla de confirmación de significados.

## Validation record

| Check | Result | Evidence |
|-------|--------|----------|
| Unit suite (simulator, iPhone 17 Pro, iOS 26.5) | 424 passed / 0 failed / 4 skipped | `/tmp/lw-final4.xcresult`, run on the release branch including the speech-test stabilization |
| Release archive + App Store export | Signed `.ipa` produced, distribution profile, `get-task-allow=false`, version 1.3.0 (10) | `xcodebuild archive` + `xcodebuild -exportArchive` |
| Compile warnings | Deprecation warnings resolved (`MobileCoreServices`, `kUTTypeText`, old picker init). One remaining: `SpeechManager.synthesizer` non-Sendable stored property — architectural, tracked | Clean Release build log |
| On-device pass | **Partial.** Informal owner pass on 2026-09-27 — "definitely better, worth publishing". Confirmed at scenario level: speech playback flow, dictation & microphone, Listen/aided (DeviceTestPlan §§1–4). **Not exercised:** import picker (§9.1 — the only proof of the new picker init), persistence/CloudKit (§6.1), interruptions/backgrounding (§7.1–7.4), reminders (§5). The formal submission gate is therefore met for §§1–4 and consciously waived for the rest — an owner call, not a completed checklist. | Owner report |

## Known limitations carried into the release

- `correctAided` events written by 1.3.0 decode to nil on ≤1.2.2 — a second device on an older
  build silently un-grades them (not wrong, just ungraded). Safe forward, worth knowing if two
  devices share one iCloud account.
- TD-65: the review log does not record which recognizer reading matched or on which attempt —
  retry leniency is invisible to future analysis until that's added.
- TD-66: a failed "new set" tap reports nothing to the user.
