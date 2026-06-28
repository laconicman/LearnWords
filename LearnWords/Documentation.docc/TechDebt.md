# Tech Debt

Known compromises, each with its cost and how it gets discharged.

<!--
  Living tech-debt register. Convention (see the repo-init skill):
  number each item; give Cost (what it hurts) and Discharge (what retires it).
  Reference IDs (TD-1, TD-2, …) from code markers: // TODO(TD-1): ...
-->

## Open

### TD-1 — Action extension cannot open the host app via supported API

`ImportAsDictAction` is an Action extension (`com.apple.ui-services`).
`NSExtensionContext.open(_:)` is only supported for Today/iMessage extensions,
so `ActionViewController.openHostApp(_:)` resolves `open(_:options:completionHandler:)`
dynamically off the responder chain (the method is hidden behind the
extension-only API wall via `APPLICATION_EXTENSION_API_ONLY = YES`).

- **Cost:** Unsupported/undocumented; may break on a future iOS and carries App
  Store review risk. Works on current iOS as a best-effort convenience only.
- **Discharge:** Design the "add without launching" share UX (see <doc:Roadmap>);
  once words can be imported without a host-app jump, the hack can be removed.

### TD-2 — App Group identifier resolved by a bundle-id suffix heuristic

`AppGroup.identifier` (`AppConstants.swift`) derives the group from
`Bundle.main.bundleIdentifier` by stripping a long hardcoded list of extension
suffixes. A renamed or new extension suffix silently yields the wrong group →
`AppGroup.userDefaults == nil` → the share import becomes a no-op.

- **Cost:** Silent breakage of all app⇄extension data sharing on a bundle-id
  change. The failure is now at least *logged* (`Logger.shareImport`) rather than
  silent, but the resolution is still fragile.
- **Discharge:** Replace the heuristic with a single shared constant (or read the
  group from the entitlement), so all three targets agree on one source of truth.

### TD-3 — `ActionViewController.done()` force-unwraps `extensionContext`

Left untouched during the import rewrite to keep the change surgical.

- **Cost:** Crash on a malformed extension invocation.
- **Discharge:** `guard let extensionContext` as in `importSharedText()`.

### TD-4 — `Logger.shareImport` lives inside `ActionViewController.swift`

Defined as a `private extension Logger` in the view-controller file (YAGNI: the
extension is the only OSLog consumer today).

- **Cost:** When a second target adopts OSLog, the subsystem/category vocabulary
  must be relocated rather than reused.
- **Discharge:** Extract to a shared `Logging.swift` added to all three targets
  (subsystem = target, categories app-global).

## See Also

- <doc:Design>
- <doc:Roadmap>
