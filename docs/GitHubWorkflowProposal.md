# Git / GitHub workflow — proposal

**Status:** proposal, not a decision record. Written for consolidation with the equivalent
reports from other repositories.

## Context this proposal is shaped by

LearnWords today: single maintainer plus agent sessions; squash merges onto `main`;
conventional-style titles (`fix(scope): …`, `feat(scope): …`) that are already changelog-grade;
`docs/` as the authority (numbered `TD-n` register, decision records, roadmap); every PR gated
by a free DeepWiki pass then a paid Devin Review whose threads must be answered before merge.

Current GitHub surface: one tag (`1.2.2`), **no `.github/` directory** — no CI, no PR
template, no CODEOWNERS — no Releases, no milestones, default labels only. `MARKETING_VERSION`
leads the release (`1.3.0` was bumped ahead of its content; the tag is created at submission).

## Proposals, cheapest first

### 1. Tag what ships — formalize the existing habit

- Annotated tag `vX.Y.Z` (or keep bare `X.Y.Z` — pick one convention, document it here) on the
  exact commit submitted to App Store Connect, pushed at submission, never moved.
- Cost: zero. Value: `git log 1.2.2..main` already answered "what's unreleased" in one command;
  a tag per submission makes that query permanent and bisectable.
- `backup/*` tags exist (e.g. `backup/pre-branch-surgery-chore`); keep them, they're cheap
  insurance, but agree they are pruned once the surgery is confirmed.

### 2. GitHub Releases generated from the PR titles

- `gh release create v1.3.0 --generate-notes` at each tag. The squash-merge convention means
  PR titles *are* the changelog — this is free today.
- `.github/release.yml` maps labels → changelog sections (`enhancement` → Features,
  `bug` → Fixes, `techdebt`/`documentation`/`chore` → collapsed "Maintenance").
- The release body doubles as the App Store "What's New" draft — write it once.

### 3. Milestones as the unit of "a release"

- One milestone per version (`1.3.0`, `1.4.0`). PRs and issues are filed into the milestone;
  release readiness becomes a query, not a feeling.
- At ship time, leftover open items are moved to the next milestone **explicitly** — the slip
  is a decision, not an omission.

### 4. Issues mirroring the `TD-n` register

- `TechDebt.md` stays the narrative register and decision record — it is good at *why*.
  GitHub issues become the schedulable unit: title `TD-62 — …`, label `techdebt`, filed into a
  milestone, closable by `Closes #N` in the PR body.
- Benefit over the current state: TD items can sit in milestones, get linked from PRs, and
  their status is visible without parsing a 2,600-line file. The register keeps its numbered
  entries; resolved ones stay resolved there.
- Do **not** migrate the resolved history — only open items get issues.

### 5. A minimal label taxonomy

Keep GitHub's defaults; add:

- `techdebt` — TD-register items.
- `release-blocker` — anything that must land (or be consciously waived) before the next tag.
- `area:*` only when an area accumulates enough PRs to justify it (`area:speech` would already
  have earned its keep this month). Don't pre-create a taxonomy.
- Optionally `agent` on agent-authored PRs — provenance that keeps AI attribution out of
  commit messages per the working agreement.

### 6. CI — **decided: tests stay local** (owner, 2026-09-27)

GitHub-hosted minutes are reserved for other projects, and the suite must run *signed* —
`CODE_SIGNING_ALLOWED=NO` strips the CloudKit entitlement and the app traps at launch, so the
easy hosted path was never really open anyway. Self-hosted runners were considered and
declined for the same reason (the runner would live on the one working machine).

Consequence, recorded honestly: every green claim in this repo is a local run, so the green
gate is *discipline*, not automation — the documented `xcodebuild` command in `CLAUDE.md`,
run on the pinned simulator, with the `.xcresult` read for Swift Testing failures. §7's
"require status checks" therefore does not apply here; conversation-resolution and
squash-only protections still do. If a second machine ever joins the project, this is the
first decision to revisit.

### 7. Branch protection on `main`

- Require PR, **require conversation resolution** (mechanically enforces the
  Devin-Review-discharge rule), no force-push, squash-only. No status checks — CI is local
  (§6), so "green" is attested by the PR's Test plan line rather than enforced by GitHub.

### 8. Auto-merge

Enable repo auto-merge where it still helps (it merges once approvals/checks are satisfied —
without CI that means "when the last thread resolves"). Modest value here; keep it as a habit
the other repos' reports may rate differently.

### 9. PR template formalizing the existing body convention

`.github/pull_request_template.md`: Summary / Test plan / DeepWiki consulted (link or "n/a —
indexed code unchanged") / Devin Review threads discharged. It is already the de-facto format;
a template just removes the effort of remembering it.

### 10. Leave alone

- **Merge queue, Projects boards, CODEOWNERS** — scale features; a solo repo buys complexity
  and sells nothing.
- **Migrating resolved TD entries to issues** — churn without a reader.

## Rollout order

30 minutes: labels, `1.3.0` milestone, branch protection (§7 minus status checks), PR
template, `release.yml`, retro-tag nothing but tag the next submission. Next: TD-issue
mirroring for open items. CI is **out** per the owner's call (§6). Everything else is
unchanged habit.

## Repo-agnostic vs. repo-specific

Portable to the other repos in the consolidation: tags-shipped convention, generated releases,
milestones-as-releases, TD-register↔issue mirroring, label minimalism, PR template shape,
protection rules.

LearnWords-specific: the signed-build constraint shaping the CI answer, the `TD-n` register
itself, the DeepWiki→Devin-Review gate (other repos may substitute their own reviewer), and
"MARKETING_VERSION leads the tag".
