//
//  SetSummaryViewController.swift
//  LearnWords
//
//  How a whole set stands (TD-51).
//
//  **Distribution first, averages beside it.** A mean mastery of 0.5 is produced both by
//  fifty half-learned words and by twenty-five mastered plus twenty-five untouched, and
//  those sets need opposite actions. So each exercise gets a bar showing where its meanings
//  actually sit, with the requested average printed next to it rather than instead of it.
//
//  **Pivoted by exercise** (owner). Since TD-49 memory is per exercise, so one bar for the
//  set would average away the thing worth knowing: which of the three is behind.
//
//  **Rings fill one way; colour carries the bad news** — the owner's answer to TD-51's open
//  question. A ring that runs backwards for a losing set reads as an animation bug on first
//  sight, and `ProgressRing` already blends toward red as retention falls, which says the
//  same thing without asking the learner to learn a new convention.
//
//  Store-free: handed a `SetSummary`, which is a pure reading of the log.
//

import UIKit

final class SetSummaryViewController: UITableViewController {

    private let summary: SetSummary
    private let setName: String

    init(summary: SetSummary, setName: String) {
        self.summary = summary
        self.setName = setName
        super.init(style: .grouped)
        // **The set's name, not a generic "Progress".** A preview or a pushed screen that
        // does not say which set it describes is a screen the learner has to guess at, and
        // the name was already being passed in and dropped. Reported by review, PR #5.
        title = setName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("use init(summary:setName:)") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // No cell is registered: every row is built by `cell(embedding:)` with its own
        // subview tree, and a registration nobody dequeues only invites a future reader to
        // dequeue it. Reported by review, PR #5.
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
    }

    /// Sections in the order the questions are asked: *where am I*, *what is coming*, *how
    /// am I doing*, *how hard have I worked*.
    private enum Section: Int, CaseIterable {
        case exercises, forecast, retention, effort
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .exercises: return Exercise.allCases.count
        case .forecast, .retention, .effort: return 1
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .exercises:
            return String.localizedStringWithFormat(
                NSLocalizedString("WordCount", comment: "Count of words available"), summary.total)
        case .forecast: return NSLocalizedString("Coming up", comment: "Summary section")
        case .retention: return NSLocalizedString("Answers so far", comment: "Summary section")
        case .effort: return NSLocalizedString("Effort", comment: "Statistics")
        case nil: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .forecast:
            return String.localizedStringWithFormat(
                NSLocalizedString("DueNowCount", comment: "Count of meanings due now"), summary.dueNow)
        case .retention:
            // Said only when there is a gap to speak of. Production lagging recognition is
            // the expected asymmetry, not an alarm (ProgressResearch §1.4).
            guard let share = summary.productiveShare, share < 0.25,
                  (summary.answersByDirection[.receptive] ?? 0) > 0 else { return nil }
            return NSLocalizedString(
                "Mostly recognition so far — producing these words is the harder half.",
                comment: "Summary footer")
        case .exercises, .effort, nil: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .exercises: return exerciseCell(Exercise.allCases[indexPath.row])
        case .forecast: return forecastCell()
        case .retention: return retentionCell()
        case .effort: return effortCell()
        case nil: return UITableViewCell()
        }
    }

    // MARK: - Rows

    /// A ring, the exercise's name, its distribution bar and its counts.
    private func exerciseCell(_ exercise: Exercise) -> UITableViewCell {
        let distribution = summary.distribution(for: exercise)

        let ring = ProgressRing()
        ring.setProgress(mastery: distribution.meanMastery,
                         effort: summary.meanEffort,
                         retention: distribution.meanRetention,
                         animated: false)
        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: Self.ringSize),
            ring.heightAnchor.constraint(equalToConstant: Self.ringSize),
        ])

        let bar = BarStrip(layout: .stacked)
        bar.show([
            .init(value: distribution.learned, colour: .lwAnswerCorrect,
                  label: NSLocalizedString("Learned", comment: "Summary legend")),
            .init(value: distribution.learning, colour: .lwAccent,
                  label: NSLocalizedString("Learning", comment: "Exercise screen title")),
            .init(value: distribution.untouched, colour: .lwTextSecondary.withAlphaComponent(0.25),
                  label: NSLocalizedString("Untouched", comment: "Summary legend")),
        ])

        let counts = caption(String(
            format: NSLocalizedString("%1$d learned · %2$d learning · %3$d untouched",
                                      comment: "Summary counts"),
            distribution.learned, distribution.learning, distribution.untouched))

        let text = stack([title(exercise.title), bar, counts], spacing: 6)
        let row = stack([ring, text], axis: .horizontal, spacing: 12)
        row.alignment = .center
        return cell(embedding: row)
    }

    private func forecastCell() -> UITableViewCell {
        let bar = BarStrip(layout: .alongside)
        bar.show(summary.dueForecast.enumerated().map { day, count in
            .init(value: count, colour: .lwAccent, label: Self.dayLabel(day))
        })
        // `forecastDays` slots are indexed 0…n-1, so the last bar is day 13, not day 14.
        // Reported by review, PR #5.
        let scale = caption(String(
            format: NSLocalizedString("Today to day %d", comment: "Summary axis"),
            SetSummary.forecastDays - 1))
        return cell(embedding: stack([bar, scale], spacing: 6))
    }

    /// True retention, split young from mature — Anki's number, and the one its community
    /// adopted because it is harder to fool than any average.
    private func retentionCell() -> UITableViewCell {
        var lines: [UIView] = []
        if let young = summary.retention.young {
            lines.append(title(String(
                format: NSLocalizedString("Still learning: %d%% right", comment: "Summary"),
                Int((young * 100).rounded()))))
        }
        if let mature = summary.retention.mature {
            lines.append(title(String(
                format: NSLocalizedString("Well known: %d%% right", comment: "Summary"),
                Int((mature * 100).rounded()))))
        }
        if lines.isEmpty {
            lines.append(title(NSLocalizedString("Nothing answered yet", comment: "Summary")))
        }

        let receptive = summary.answersByDirection[.receptive] ?? 0
        let productive = summary.answersByDirection[.productive] ?? 0
        if receptive + productive > 0 {
            lines.append(caption(String(
                format: NSLocalizedString("%1$d recognised · %2$d produced", comment: "Summary counts"),
                receptive, productive)))
        }
        return cell(embedding: stack(lines, spacing: 4))
    }

    private func effortCell() -> UITableViewCell {
        cell(embedding: stack([
            title(String(format: NSLocalizedString("%d%% of the way in", comment: "Summary effort"),
                         Int((summary.meanEffort * 100).rounded()))),
            caption(NSLocalizedString("Work invested never falls, whatever a bad week does.",
                                      comment: "Summary caption")),
        ], spacing: 4))
    }

    // MARK: - Building blocks

    private static let ringSize: CGFloat = 44

    private static func dayLabel(_ day: Int) -> String {
        day == 0
            ? NSLocalizedString("Today", comment: "Summary axis")
            : String(format: NSLocalizedString("Day %d", comment: "Summary axis"), day)
    }

    private func title(_ text: String) -> UILabel {
        label(text, style: .body, colour: .lwTextPrimary)
    }

    private func caption(_ text: String) -> UILabel {
        label(text, style: .caption1, colour: .lwTextSecondary)
    }

    private func label(_ text: String, style: UIFont.TextStyle, colour: UIColor) -> UILabel {
        let view = UILabel()
        view.text = text
        view.font = .preferredFont(forTextStyle: style)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = colour
        view.numberOfLines = 0
        return view
    }

    private func stack(_ views: [UIView], axis: NSLayoutConstraint.Axis = .vertical,
                       spacing: CGFloat) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Rows are built rather than dequeued: this screen draws about six of them once, and
    /// reuse would mean tearing down and rebuilding a subview tree for no gain.
    private func cell(embedding content: UIView) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.contentView.addSubview(content)
        let margins = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            content.topAnchor.constraint(equalTo: margins.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -6),
        ])
        return cell
    }
}
