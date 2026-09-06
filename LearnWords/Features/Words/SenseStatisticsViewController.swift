//
//  SenseStatisticsViewController.swift
//  LearnWords
//
//  What the log knows about one meaning (TD-50).
//
//  **A section per exercise, because that is the owner's headline ask** and, since TD-49,
//  the shape of the data: memory is kept per exercise (`StrandProgress`), so a word can be
//  solid as a flashcard and failing in dictation. The ring on the word list shows the
//  *weakest* engaged strand, which is the right summary and tells you nothing about which
//  one is weak. This screen is where that goes.
//
//  **The receptive/productive split is the reason it exists.** No app in the survey behind
//  docs/MasteryAndProgressUI.md shows it, and `ReviewDirection` has been recorded per event
//  since TD-13 precisely so it could be. "You recognise it / you can produce it" is the
//  distinction a learner feels and no single percentage can express.
//
//  Store-free, like the entry screens: it is handed a meaning and its `SenseProgress`.
//  Everything shown is a replay of the event log — no schema change, and nothing cached.
//

import UIKit

final class SenseStatisticsViewController: UITableViewController {

    private let sense: Sense

    /// Which meaning this screen describes, so a caller holding only the preview instance can
    /// find it again — the commit path rebuilds the screen rather than pushing the preview.
    var senseID: UUID { sense.id }

    private let progress: SenseProgress
    private let languages: LanguagePair
    private let now: Date

    /// Whether to offer looking the word up.
    ///
    /// Offered from here because the context menu that presents this screen took the long
    /// press that used to do it, and at the iOS 12 floor there is no menu to hang an action
    /// on. **A flag rather than a closure**, and the presentation happens here: the closure
    /// version was handed `WordTableViewController` as the presenter, whose view UIKit has
    /// removed from the window by the time this screen is on top — so the dictionary could
    /// fail to appear at all. A view controller presents from itself. Reported by review,
    /// PR #3.
    ///
    /// Off for the context-menu *preview*, which is not interactive: the row would be pure
    /// extra height, and height is the known clipping problem on that path.
    private let offersLookUp: Bool

    /// The distinct-day gate to explain, defaulted to the one in force.
    ///
    /// **Told, not looked up.** It became a preference in TD-57, and a screen that read
    /// the global while rendering could describe a gate that changed underneath it — and
    /// gave the tests a shared mutable dependency they had no way to pin. A defaulted
    /// parameter costs no call site and makes both problems go away.
    private let minimumSuccessfulDays: Int

    init(sense: Sense,
         progress: SenseProgress,
         languages: LanguagePair,
         now: Date = Date(),
         offersLookUp: Bool = false,
         minimumSuccessfulDays: Int = ScoringPolicy.default.minimumSuccessfulDays) {
        self.minimumSuccessfulDays = minimumSuccessfulDays
        self.sense = sense
        self.progress = progress
        self.languages = languages
        self.now = now
        self.offersLookUp = offersLookUp
        super.init(style: .grouped)
        title = sense.terms(in: languages.secondary).map(\.text).joined(separator: ", ")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("use init(sense:progress:languages:now:offersLookUp:minimumSuccessfulDays:)")
    }

    // MARK: - The table, as one value

    /// Sections are built once, in one place — the same single-snapshot rule the entry
    /// screens document. Nothing here changes while the screen is up: it is a reading of
    /// the log at the moment it was opened, and it says so by never moving.
    private lazy var sections: [Section] = buildSections()

    private struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private struct Row {
        let text: String
        /// The right-hand value, when the row is a measurement rather than a statement.
        let detail: String?
        let isAction: Bool

        init(_ text: String, detail: String? = nil, isAction: Bool = false) {
            self.text = text
            self.detail = detail
            self.isAction = isAction
        }
    }

    private func buildSections() -> [Section] {
        // **No overall section for a meaning with *nothing to report*** — which is not the
        // same as no engaged exercise. A progress reset clears every strand's memory but
        // deliberately keeps effort and the answer counts, as the record of work actually
        // done; keying on `engagedExercises` hid exactly those retained totals on exactly the
        // meanings whose history the learner had just chosen to set aside. Reported by
        // review, PR #3.
        let hasSomethingToReport = progress.effort > 0
            || progress.answersByDirection.values.contains { $0 > 0 }
        let overall = hasSomethingToReport ? [overallSection] : []
        return Exercise.allCases.map(strandSection) + overall + lookUpSection
    }

    /// One exercise: what it remembers, when it is next due, and how much spacing it has.
    ///
    /// An exercise never tried says exactly that and nothing else. Showing 0% mastery and
    /// "due now" for an exercise the learner has never opened is three numbers about
    /// nothing, and it reads as failure rather than as absence.
    private func strandSection(_ exercise: Exercise) -> Section {
        let strand = progress[exercise]
        guard strand.isEngaged else {
            return Section(title: exercise.title,
                           footer: nil,
                           rows: [Row(NSLocalizedString("Not practised yet",
                                                        comment: "Statistics; an exercise"))])
        }

        var rows = [Row(MemoryWording.horizon(days: strand.memory?.stability ?? 0))]
        rows.append(Row(NSLocalizedString("Recall right now", comment: "Statistics"),
                        detail: percent(strand.retention)))
        rows.append(Row(MemoryWording.due(strand.dueAt, now: now)))
        // **"Successful days", not "Practised on".** The number is days carrying a *success*,
        // and a strand becomes engaged on its first answer however that answer went — so a
        // word tried once and got wrong read "Practised on — never", which is both wrong and
        // discouraging. The label now says what the number counts, and the footer below
        // explains why it matters. Reported by review, PR #3.
        rows.append(Row(NSLocalizedString("Successful days", comment: "Statistics; days"),
                        detail: dayCount(strand.successfulDays)))

        return Section(title: exercise.title,
                       // The two-day gate is the half of the learned rule that a single
                       // fast answer cannot satisfy, and the only one worth explaining
                       // where it applies (TD-49).
                       // **The number in force, not the shipped default.** It is settable
                       // now, so a footer reading the constant would tell a learner who
                       // moved the slider something the app is not doing. Reported by
                       // review, PR #3, and left then because there was nothing to read.
                       footer: strand.successfulDays < minimumSuccessfulDays
                           ? String.localizedStringWithFormat(
                               NSLocalizedString("SuccessfulDaysGate", comment: "Statistics; footer"),
                               minimumSuccessfulDays)
                           : nil,
                       rows: rows)
    }

    /// Effort, and the split the screen exists for.
    private var overallSection: Section {
        let receptive = progress.answersByDirection[.receptive] ?? 0
        let productive = progress.answersByDirection[.productive] ?? 0

        var rows = [Row(NSLocalizedString("Effort", comment: "Statistics"),
                        detail: percent(progress.effort))]
        rows.append(Row(NSLocalizedString("Recognised", comment: "Statistics; receptive answers"),
                        detail: answerCount(receptive)))
        rows.append(Row(NSLocalizedString("Produced", comment: "Statistics; productive answers"),
                        detail: answerCount(productive)))

        return Section(
            title: NSLocalizedString("Overall", comment: "Statistics section"),
            // Said only when it is true and actionable. Recognition running ahead of
            // production is the normal, expected asymmetry (ProgressResearch §1.4); it is
            // worth naming, not worth alarming about.
            footer: productive == 0 && receptive > 0
                ? NSLocalizedString("Only recognised so far — producing it is the harder half.",
                                    comment: "Statistics; footer")
                : nil,
            rows: rows)
    }

    private var lookUpSection: [Section] {
        guard offersLookUp, !prompt.isEmpty else { return [] }
        return [Section(title: nil, footer: nil,
                        rows: [Row(String(format: NSLocalizedString("Look up %@",
                                                                    comment: "Button label; a word"),
                                          prompt),
                                   isAction: true)])]
    }

    /// The word this screen is about, in the language being studied.
    private var prompt: String {
        sense.terms(in: languages.secondary).first?.text ?? ""
    }

    // MARK: - Wording

    /// Whole percents: the underlying floats are model outputs, and a decimal place would
    /// claim a precision they do not have.
    private func percent(_ value: Float) -> String {
        String(format: NSLocalizedString("%d%%", comment: "Statistics; a percentage"),
               Int((value * 100).rounded()))
    }

    private func dayCount(_ days: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("DayCount", comment: "Count of separate days practised"), days)
    }

    private func answerCount(_ answers: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("AnswerCount", comment: "Count of graded answers"), answers)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Only the action cell is registered. Value rows are built as `.value1`, a style
        // that cannot be registered, and a spare registration only invites a future reader to
        // dequeue it and lose every detail label. Reported by review, PR #3.
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Cell.action)
    }

    private enum Cell {
        static let action = "action"
    }

    /// The size the context-menu preview opens at, measured from the content rather than
    /// guessed — a preview too short scrolls inside a popover, one too tall is mostly empty.
    ///
    /// **Set, not an overridden getter.** Overriding the getter made the property write-only:
    /// any caller setting a preferred size (a popover, a form sheet, a split view) was
    /// silently ignored and always read a width of 0, and computing it forced a layout pass
    /// from inside a property UIKit queries *during* layout. Reported by review, PR #3.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = tableView.contentSize.height
        if preferredContentSize.height != height {
            preferredContentSize = CGSize(width: preferredContentSize.width, height: height)
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section < sections.count ? sections[section].rows.count : 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section < sections.count ? sections[section].title : nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section < sections.count ? sections[section].footer : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = row(at: indexPath) else { return UITableViewCell() }

        if row.isAction {
            let cell = tableView.dequeueReusableCell(withIdentifier: Cell.action, for: indexPath)
            cell.textLabel?.text = row.text
            cell.textLabel?.textColor = .lwAccent
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.textLabel?.numberOfLines = 0
            return cell
        }

        // Built rather than dequeued: `.value1` cells cannot be registered by style, and a
        // statistics screen draws a handful of rows once — reuse buys nothing here and
        // dequeuing the wrong style silently drops every detail label.
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = row.text
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = row.detail
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.textColor = .lwTextSecondary
        return cell
    }

    private func row(at indexPath: IndexPath) -> Row? {
        guard indexPath.section < sections.count,
              indexPath.row < sections[indexPath.section].rows.count else { return nil }
        return sections[indexPath.section].rows[indexPath.row]
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard row(at: indexPath)?.isAction == true, !prompt.isEmpty else { return }
        lookUp(term: prompt, sender: self)
    }
}
