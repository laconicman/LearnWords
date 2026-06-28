# Roadmap

Planned work, in rough priority order.

<!--
  Living roadmap. The DocC article is the milestone summary; keep it short and
  link to Design for the authoritative rationale. Order = priority.
-->

## Now

- [x] Harden the share-import path (`ImportAsDictAction`): async/await load,
  `UTType.plainText`, no force-unwraps, loud OSLog on every failure.

## Next

- [ ] Design a "just add, without launching" share UX so importing a word or
  dictionary no longer depends on the unsupported host-app open (retires TD-1).
- [ ] Surface imported-but-untranslated items in the app — highlight entries
  that have no proper user translation yet, which the no-launch flow depends on.
- [ ] Parse the imported text into a dictionary instead of storing the raw
  string (`ActionViewController` currently saves text verbatim).

## Later

- [ ] Replace the App Group suffix heuristic with a single shared constant (TD-2).
- [ ] Promote `Logger.shareImport` to a shared `Logging.swift` across all targets
  once the app/Widget adopt OSLog (TD-4).

## See Also

- <doc:Design>
- <doc:TechDebt>
