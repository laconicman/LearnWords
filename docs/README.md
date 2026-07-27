# LearnWords — project direction docs

These are the authoritative direction docs for LearnWords. They are plain Markdown
under `docs/` (kept out of the app's synchronized folders, so they never affect the
build). They can be promoted to a rendered DocC catalog later — see the `repo-init`
convention — once there's a green build to verify the catalog against.

- [Design](Design.md) — architecture direction and decision records (authoritative over code comments when they disagree).
- [Roadmap](Roadmap.md) — priority-ordered milestones (Now / Next / Later).
- [TechDebt](TechDebt.md) — numbered register (`TD-n`) with Cost / Discharge, plus the full feature-first reorg mapping.

Architecture follows the `uikit-app-structure` skill (Manferdini's four-layer MVC:
Model · Controller · Root · View). Design principles applied throughout: separation
of concerns, single source of truth, low coupling / high cohesion, dependency
inversion, KISS, YAGNI (`software-development-principles`).
- [Handoff](Handoff.md) — state of play after forks A/B/C: what is proven, what is not, and what the next fork should take.
- [Enrichment](Enrichment.md) — TD-22 design: mapping kaikki/Wiktionary onto the lexicon, how the data reaches the device, and the licence obligations.
