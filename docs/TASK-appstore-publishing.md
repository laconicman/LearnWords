# TASK — the publisher's path: App Store automation and AI assistance

Written 2026-09-14, the day the 1.2.2 release needed only a "What's New" block and it was already
clear that this is the smallest thing App Store Connect will ever ask for. `docs/` is
authoritative, and this brief follows the working agreement in `CLAUDE.md`: which half of a claim
is **verified** and which is **reasoned** is said every time, and Apple's behaviour is looked up,
not recalled.

**Scope is general, pilot is LearnWords.** The goal is a reusable way of easing the path from a
green build to a live App Store page, for any of the owner's apps. LearnWords is the first
consumer because it is the app with a release waiting. The tooling this produces does not belong
in this repository; where it lives is decision 2 below.

## Why this is worth a task

The surface is large, demanding, and uneven:

* **Metadata.** Listing text per locale: name, subtitle, description, keywords, promotional text,
  What's New, URLs.
* **Media.** Screenshots and previews per locale and display size.
* **Questionnaires.** App Privacy, Accessibility Nutrition Labels, the age rating, export
  compliance, content rights.
* **Commercial.** Pricing and availability.
* **Review.** App Review contact and sign-in details, release options, and TestFlight notes.

An update touches a handful of these. A new app touches all of them. Each has its own editable
states and its own reviewer. Some are in the API and some, as far as has been checked, are not.

It has already cost this project. Uploading 1.2.2 (9) failed with `90068` on `MinimumOSVersion`
(Design § *the floor is iOS 15*). An earlier archive had extension versions drifting from the app's
(TD-24). The review rules require a privacy manifest in every bundle. Every one of these is a
check a machine could have run before a person pressed Upload.

## What exists

### Apple

* **No AI for developers' metadata.** A research pass on 2026-09-14 found nothing that drafts,
  suggests or translates listing text. It read the WWDC26 App Store guide, App Store Connect API
  release notes 4.0–4.4.1 and the App Store Connect release notes to 2026-09-10. Apple's
  generative features face customers (App Store tags, review summaries) or the app's own strings
  (Xcode agents translating String Catalogs). *Verified for the pages read; "nowhere else" is
  reasoned.*
* **API coverage, verified against Apple's "App Metadata" index and API reference on 2026-09-14.**
  Each of these has a resource:
  * app info and version localizations (`appStoreVersionLocalizations` carries `whatsNew`)
  * screenshot and preview sets, through the asset upload flow
  * categories and age ratings
  * accessibility declarations
  * EULAs
  * app encryption declarations
  * app price schedules
  * custom product pages and app events
  * review submission items, review attachments and beta app review submissions
  * in-app purchases and subscriptions
* **Not in that index: App Privacy (data collection) details.** It is expected to be web-only, but
  that is **not yet confirmed**. Also unchecked:
  * EU trader status
  * agreements, tax and banking
  * creating the app record itself
  * content rights
  * phased release and sign-in details for App Review
* **What's New constraints**, from the research pass reading Apple's help pages: at most 4,000
  characters. It doesn't exist on an app's first version and is required on later ones. It is
  editable only in some version states: Prepare for Submission and Rejected are, In Review and
  Pending Developer Release are not. Locale codes include `en-US`, `ru`, `es-ES` and `es-MX`.
* **Credentials.** An API key is three parts: a Key ID, an Issuer ID, and a `.p8` file that can be
  downloaded only once. It signs JWTs of at most 20 minutes. Team keys come from Account Holder or
  Admin, and submitting needs App Manager or above. Apple's API overview frames use as automation
  "within your team's internal workflow". Nothing here has been read about automating the
  **web** UI (decision 4).

### Other people's work

Nothing below has been evaluated yet; that is Phase 0's tool trial. Every behaviour described is
**vendor-reported**: taken from the project's own README or docs, as read by the research pass on
2026-09-14, or from the vendored `axiom-shipping` skill. None of it has been run or verified.

* **fastlane.** `deliver` handles metadata as files, `snapshot` and `frameit` handle screenshots,
  and `precheck` lints metadata. `fastlane/metadata/<locale>/release_notes.txt` is the de facto
  file layout. The `translate_gpt_release_notes` plugin fills the other locales through an LLM.
* **`asc` CLI** (`rorkai/App-Store-Connect-CLI`). It does metadata sync, keeps credentials in the
  Keychain, and has **telemetry on by default**. A community skill pack includes
  `asc-whats-new-writer`, which runs git log → draft → translate → approval → push.
* **MCP servers.** Each is maintained by a single person:
  * `zelentsov-dev/asc-mcp`, which the vendored `axiom-shipping` skill already documents: 25
    workers, about 208 tools, pinned there at 1.4.0; current status unchecked.
  * `mgcrea/mcp-appstore-connect`: read-only unless writes are enabled explicitly.
  * `akoskomuves/appstoreconnect-mcp`
  * `beydemirfurkan/appstore-release`
  * `JoshuaRileyDev/app-store-connect-mcp-server`: most-starred, but no commit since 2025-09.
* **Paid services.** Helm Pro adds AI translation and text improvement. AppTweak, AppFollow and
  Appfigures offer AI for keywords, not for release notes.
* **Knowledge already installed.** `axiom-shipping`, vendored under MIT, carries submission
  checklists, rejection triage and App Store Connect references. `axiom-accessibility` covers the
  audit that Accessibility Nutrition Labels should be answered from.

### The owner's own work, and what each is a template for

* **`laconicman/deepwiki-mcp`.** A Swift MCP server and a skill, shipped as a Claude plugin and as
  `.mcpb`. It speaks an undocumented backend captured from the web app, and needs no browser at run
  time. It is the template for any surface the API doesn't cover, and it carries that approach's
  known costs: contract drift and guest etiquette.
* **`laconicman/laconic-review`.** A Swift CLI and a skill, with a report-format contract, `lint`
  and idempotent `publish`, and evals. It is the template for "metadata as reviewed files, linted,
  then published".
* **This repository's discipline.** PRs, Devin Review, docs as authority. It is the template for
  letting listing text go through review like code.

## Decisions for the owner

1. **Adopt, build or hybrid.** *Recommended, reasoned:* a hybrid.
   * **Adopt** an execution layer for everything the API covers: fastlane, `asc`, or one MCP server.
   * **Build** our own plugin as the *assistant* layer: metadata as files, drafting from the
     history, questionnaires answered from evidence in the code, preflight, and a verifier.
   * **Build a web adapter only** for surfaces the API does not cover, and only after decision 4.
2. **Where the plugin lives.** A new `laconicman/<name>` repository, with LearnWords as its pilot.
   This brief moves there when that repository exists.
3. **Source of truth for listing text.** One option is repository files, with App Store Connect as a
   deployment target: pull, diff, apply. The other is App Store Connect as truth, with the repo
   holding only drafts. *Reasoned:* files win for review and history. The fastlane layout is worth
   adopting even without fastlane, because other tools read it (`mgcrea` round-trips it).
4. **Web-only surfaces: checklist, assisted browser, or session replay.** First read what the Apple
   Developer Program License Agreement and App Store Connect terms say about automated access to the
   web UI. *Not yet read.* Replay is the highest leverage and the most fragile, and it would carry an
   Apple ID session. That is the owner's to decide with the terms in hand, not the assistant's.
5. **Credential custody.** *Recommended:*
   * the key stays in the owner's Keychain, or at a path the assistant references but never prints
   * every write shows a dry-run diff first and needs explicit approval
   * submitting and releasing stay human
   * telemetry is off in any adopted tool

## Principles

* **The assistant drafts; the owner publishes.** Reading App Store Connect can be delegated. Writing
  is a reviewed diff the owner approves, and submission is never automated end to end.
* **Evidence, not recall.** Every questionnaire answer cites what it comes from:
  * the privacy manifests in every bundle (`PrivacyInfo.xcprivacy`, `WordWidget/…`,
    `ImportAsDictAction/…`)
  * the entitlements
  * `ITSAppUsesNonExemptEncryption = false` in `LearnWords/Info.plist`
  * the features that ship

  Anything code cannot answer, such as a content question for the age rating, is marked as a
  question for the owner, never guessed.
* **Idempotent and diffable.** Pull the live state, diff against the repo, apply only the difference.
  A second run changes nothing.
* **No promises the app cannot keep.** Release notes may only claim what has been verified, and
  only as far as it was verified. Sync is the example. Handoff records a word set and a word
  syncing both ways between two devices, plus one real merge. It also leaves deferred seeding on a
  second device and live refresh of incoming changes unverified, and nothing has been checked
  against the Production schema deployed on 2026-09-14. The Roadmap still lists two-device
  verification as open. The first draft of 1.2.2's notes left sync out for that reason.
* **Low volume.** Respect API rate limits, and for any undocumented endpoint follow the etiquette
  `deepwiki-mcp` already follows.

## Phase 0 — inventory and a decision (no code)

1. **The surface matrix.** One row per field or section, for an **update** and for a **new app**.
   Each row gives:
   * its API resource, or *web-only*
   * the version states in which it can be edited
   * whether it is per locale or per display
   * its limits
   * the role that can change it
   * the evidence in the repo that answers it, if any

   Every row links the Apple page it was verified on. Unverified rows say so.
2. **Screenshot requirements.** Which display sizes are currently required, and which are accepted
   as substitutes. Look this up; it changes.
3. **Tool trial, read-only, on LearnWords.** At most three candidates: fastlane, `asc`, and one MCP
   server. Pull the current listing with each and compare:
   * coverage against the matrix
   * maintenance
   * how the credential is held
   * dry-run and diff support
   * telemetry
   * licence

   Also check whether Apple publishes an OpenAPI specification for the App Store Connect API. If it
   does, the `apple-swift-openapi-generator` skill makes a small Swift client cheap, which bears on
   adopt versus build.
4. **The terms.** A short note on what the agreement says about automating the web UI, with quotes
   limited to what the decision needs.
5. **A decision record** in the new repository, or in this one's Design if it doesn't exist yet,
   covering decisions 1–5.

**Definition of done:** the owner has chosen adopt, build or hybrid, the plugin's home, the source
of truth and the web-surface policy, from a matrix whose rows cite their sources.

## Phase 1 — What's New as code

The need of the day, done so it never has to be done by hand again.

* **Metadata files** in the layout decision 3 picks. 1.2.2's notes in English and Russian are seeded
  from the draft written on 2026-09-14. Spanish depends on whether the listing has it.
* **A release tag convention.** The repository has no release tags, which is why that draft had to
  infer "since 1.2.1" from `docs/Design.md`. Tag each uploaded build (`v1.2.2-9` or similar) so the
  next draft's range is a fact.
* **A drafting skill.** It reads the history since the last tag and keeps only user-visible `feat`,
  `fix` and `perf` changes. It writes in the app's own UI terms (the string catalogues are the
  glossary: «выучено · в работе · не начато», "Successful days needed"). It never claims an
  unverified feature. Output goes through a PR like any doc.
* **A linter,** in the `laconic-review lint` sense. It checks limits, locale completeness, leftover
  placeholders and bullet formatting, and flags claims naming features the register marks unverified.
* **Publishing:** the owner pastes the text, or runs the adopted tool with their own key.

**Definition of done:** 1.2.2's What's New lives in the repo for every listing locale and passes the
linter, and a read-only pull shows App Store Connect holds the same text.

## Phase 2 — listing text and screenshots

* Pull the whole listing into files, then maintain it by pull, diff and apply.
* **Screenshots from UI tests,** not from hand-driving a simulator. The walkthrough on 2026-09-14
  showed how brittle that is: computer control of the simulator needed full-screen takeover for a
  long press. XCUITest plus `simctl` per locale and display size is the reproducible route. Framing
  is optional.
* Upload through the API's screenshot sets, after a human has looked at every image once.

**Definition of done:** one command regenerates a release's screenshots for every required size and
locale, and they upload only after approval.

## Phase 3 — questionnaires, answered from evidence

* **Export compliance:** encryption declarations and `ITSAppUsesNonExemptEncryption`.
* **Age rating:** mostly content questions for the owner, with the few that code can answer
  pre-filled.
* **Accessibility Nutrition Labels:** answered from an `axiom-accessibility` audit of the app, not
  from intent.
* **App Privacy:** answered from the privacy manifests, the frameworks linked (TD-46's `otool` list),
  and what may leave the device. CloudKit's private database does. Whether speech recognition runs
  on the device or on Apple's servers is to be established, not assumed.

Each produces an answer sheet: every answer with its evidence, and open questions separated out. The
tool applies what the API covers. The owner enters the rest.

**Definition of done:** for LearnWords, every questionnaire has a reviewed answer sheet. Re-running
the sheets after a code change flags every answer that the change affects.

## Phase 4 — preflight and submission

* **Preflight, before anything is uploaded.** It checks this project's own failures:
  * every bundle's `MinimumOSVersion` against Apple's current floor
  * version and build numbers identical across bundles (TD-24)
  * a privacy manifest in every bundle
  * the build number not already used
  * entitlements matching the App ID's capabilities

  Then everything `precheck`-like the matrix turns up.
* **The pipeline:** archive, export, upload, create the version, attach the build, fill App Review
  details, and prepare TestFlight's What to Test. The owner presses submit.

**Definition of done:** a dry run of a full update, from archive to "ready to submit", with every
write gated and a preflight that would have caught `90068`.

## Phase 5 — surfaces the API does not cover

Only if Phase 0's matrix and terms note say it is worth it. Per surface, pick one:

* **A guided checklist** with deep links into App Store Connect. Always possible.
* **Assisted browsing,** human in the loop.
* **A session-replay adapter** on the `deepwiki-mcp` pattern.

**Definition of done:** each web-only surface has a chosen route, recorded with its reason.

## What this does not do

* Submit, release or answer App Review without the owner.
* Handle an Apple ID password, a 2FA code, or the text of an API key.
* Keyword stuffing, or any ASO tactic App Review would call manipulation.
* Grow LearnWords-specific code paths in the plugin. App specifics are configuration.

## Open questions to settle early

* Which locales does the LearnWords listing have today?
* Which version does the App Store serve today? 1.2.1 is inferred, not verified.
* Will 1.2.2 go up as (9) again, or as a new build number?

## Running this in a fresh session

One line is enough: *"Do Phase 0 of `docs/TASK-appstore-publishing.md`"*. Phase 0 needs no
credentials beyond a read-only look, and if the owner provides a key path for the trial, it is
passed to tools by path and never printed or copied into the repository. Research belongs in
subagents: the matrix and the tool trial are independent and can run in parallel. The decision
record comes back to the owner before any Phase 1 code.
