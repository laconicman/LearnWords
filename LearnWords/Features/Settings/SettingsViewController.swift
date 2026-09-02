//
//  SettingsViewController.swift
//  LearnWords
//
//  In-app settings screen; replaces the retired Settings.bundle pane (TD-14).
//  Values live in the App-Group suite via LWUserDefaults, so the app and its
//  extensions agree.
//

import UIKit

final class SettingsViewController: UITableViewController {

    private let prefs = LWUserDefaults.standard

    /// Codes match AVSpeechSynthesisVoice languages (BCP-47).
    static let languages: [(code: String, name: String)] = [
        ("en-GB", NSLocalizedString("English (GB)", comment: "language")),
        ("en-US", NSLocalizedString("English (US)", comment: "language")),
        ("ru-RU", NSLocalizedString("Russian", comment: "language")),
        ("es-ES", NSLocalizedString("Spanish", comment: "language")),
        ("de-DE", NSLocalizedString("German", comment: "language")),
        ("fr-FR", NSLocalizedString("French", comment: "language")),
        ("it-IT", NSLocalizedString("Italian", comment: "language")),
    ]

    static func languageName(for code: String?) -> String {
        languages.first(where: { $0.code == code })?.name ?? code ?? ""
    }

    // MARK: - Cells (created once; this is a small static screen)

    private let studyLanguageCell = UITableViewCell(style: .value1, reuseIdentifier: nil)
    private let nativeLanguageCell = UITableViewCell(style: .value1, reuseIdentifier: nil)

    private lazy var pitchCell = SliderCell(
        title: NSLocalizedString("Pitch", comment: "Speech setting: voice pitch for text-to-speech"),
        minimum: 0.7, maximum: 1.9, format: "%.1f",
        value: Float(prefs.pitchMultiplierPreference)
    ) { [weak self] in self?.prefs.pitchMultiplierPreference = Double($0) }

    private lazy var rateCell = SliderCell(
        title: NSLocalizedString("Rate", comment: "Speech setting: speaking rate (speed) for text-to-speech"),
        minimum: 0.2, maximum: 0.8, format: "%.2f",
        value: Float(prefs.utteranceRatePreference)
    ) { [weak self] in self?.prefs.utteranceRatePreference = Double($0) }

    private lazy var pronounceAnswersCell = SwitchCell(
        title: NSLocalizedString("Pronounce answers", comment: "setting"),
        isOn: prefs.pronounceAnswersPreference
    ) { [weak self] in self?.prefs.pronounceAnswersPreference = $0 }

    private lazy var pronounceQuestionsCell = SwitchCell(
        title: NSLocalizedString("Pronounce questions", comment: "setting"),
        isOn: prefs.pronounceQuestionsPreference
    ) { [weak self] in self?.prefs.pronounceQuestionsPreference = $0 }

    /// Renamed from "Known level" when scoring moved to FSRS: the number used to mean
    /// "correct answers in a row" and now means "days it should stay remembered" — the
    /// stability at which `ScoringPolicy` calls a meaning learned. Same preference key,
    /// same 1…100 range, which reads sensibly as days.
    private lazy var masteryHorizonCell = SliderCell(
        title: NSLocalizedString("Remembered for (days)", comment: "setting"),
        // Floor matches `ScoringPolicy.minimumHorizonDays`: below it a single fast answer
        // fills the ring outright, so offering 1…9 would be a control that does nothing.
        minimum: Float(ScoringPolicy.minimumHorizonDays), maximum: 100, format: "%.0f",
        value: Float(prefs.maxKnownLevelPreference)
    ) { [weak self] in self?.prefs.maxKnownLevelPreference = Int($0.rounded()) }

    /// The other half of the learned rule, and the half a learner can feel: how many
    /// separate days must carry a success before a meaning is called learned. The horizon
    /// above says *how long* it should stick; this says *how much evidence* is enough.
    private lazy var successfulDaysCell = SliderCell(
        title: NSLocalizedString("Successful days needed", comment: "setting"),
        minimum: Float(ScoringPolicy.minimumSuccessfulDaysRange.lowerBound),
        maximum: Float(ScoringPolicy.minimumSuccessfulDaysRange.upperBound),
        format: "%.0f",
        value: Float(prefs.minimumSuccessfulDaysPreference)
    ) { [weak self] in self?.prefs.minimumSuccessfulDaysPreference = Int($0.rounded()) }

    private lazy var remindersCell = SwitchCell(
        title: NSLocalizedString("Daily reminder", comment: "setting"),
        isOn: prefs.remindersEnabled
    ) { [weak self] isOn in self?.setRemindersEnabled(isOn) }

    /// What the system currently allows, re-read every time this screen appears. `nil`
    /// until the first read comes back.
    private var reminderStanding: ReminderScheduler.Standing?

    private lazy var reminderTimeCell = TimeCell(
        title: NSLocalizedString("Remind me at", comment: "setting"),
        hour: prefs.reminderHour, minute: prefs.reminderMinute
    ) { [weak self] hour, minute in
        guard let self else { return }
        self.prefs.reminderHour = hour
        self.prefs.reminderMinute = minute
        // Re-read *after* the rebuild lands, or the footer shows the schedule the old time
        // produced.
        ReminderScheduler.shared.rebuild(from: Library.shared.lexicon) { [weak self] in
            self?.refreshReminderStanding()
        }
    }

    private var sections: [(title: String, cells: [UITableViewCell])] {
        [
            (NSLocalizedString("Languages", comment: "settings section"),
             [studyLanguageCell, nativeLanguageCell]),
            (NSLocalizedString("Speech", comment: "Settings section: text-to-speech options"),
             [pitchCell, rateCell, pronounceAnswersCell, pronounceQuestionsCell]),
            (NSLocalizedString("Study", comment: "Settings section: study/learning options"),
             [masteryHorizonCell, successfulDaysCell]),
            // Both rows, always. Adding and removing a row while handing out the *same*
            // cell instances left UIKit holding a hidden cell with no index path
            // ("Unable to obtain index path for accessory"), which is noise at best and a
            // dead control at worst. The time row is disabled instead of removed.
            (NSLocalizedString("Reminders", comment: "settings section"),
             [remindersCell, reminderTimeCell]),
        ]
    }

    /// The time row is pointless unless reminders are both wanted and deliverable.
    private var canBeReminded: Bool {
        prefs.remindersEnabled && reminderStanding != .blocked
    }

    /// When the next reminder is due to fire, as last read.
    private var nextReminderAt: Date?

    /// Re-reads the live notification setting and reconciles the switch with it.
    ///
    /// **This is the rule the feature was missing.** The preference said "on" and the
    /// switch drew "on", but the learner could have turned notifications off in Settings
    /// at any point since — and nothing would ever have arrived, with the app still
    /// claiming otherwise. Apple's guidance is to check the status rather than remember
    /// it; this is where that check happens for the UI, as `rebuild` is for the schedule.
    private func refreshReminderStanding() {
        ReminderScheduler.shared.standing { [weak self] standing in
            guard let self else { return }
            self.reminderStanding = standing
            if standing == .blocked && self.prefs.remindersEnabled {
                // Not "turn the preference off": the learner did ask for reminders, and if
                // they re-allow them in Settings that wish should still stand. Only the
                // switch is corrected, and the footer says why.
                self.remindersCell.setOn(false)
            } else {
                self.remindersCell.setOn(self.prefs.remindersEnabled)
            }
            self.reminderTimeCell.isEnabled = self.canBeReminded
            self.tableView.reloadData()
        }
        ReminderScheduler.shared.pending { [weak self] next, _ in
            self?.nextReminderAt = next
            self?.tableView.reloadData()
        }
    }

    /// Turning reminders on asks for permission first, and turns the switch back off if it
    /// is refused — a switch that stays on while nothing can be delivered is a lie.
    private func setRemindersEnabled(_ isOn: Bool) {
        guard isOn else {
            prefs.remindersEnabled = false
            ReminderScheduler.shared.clear()
            tableView.reloadData()
            return
        }
        ReminderScheduler.shared.requestAuthorization { [weak self] granted in
            guard let self else { return }
            self.prefs.remindersEnabled = granted
            if granted {
                ReminderScheduler.shared.rebuild(from: Library.shared.lexicon) { [weak self] in
                    self?.refreshReminderStanding()
                }
            } else {
                self.showNotificationsRefused()
            }
            self.tableView.reloadData()
        }
    }

    private func showNotificationsRefused() {
        let alert = UIAlertController(
            title: NSLocalizedString("Notifications are off", comment: "Alert title"),
            message: NSLocalizedString(
                "Turn them on for LearnWords in Settings to be reminded. Practice works either way — the Exercises screen always shows what is due.",
                comment: "Alert message when notification permission was refused"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""),
                                      style: .default) { _ in
            // The notification page directly, not the app's general one (iOS 15.4+).
            if let url = ReminderScheduler.settingsURL { UIApplication.shared.open(url) }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"),
                                      style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Lifecycle

    init() {
        if #available(iOS 13.0, *) {
            super.init(style: .insetGrouped)
        } else {
            super.init(style: .grouped)
        }
        title = NSLocalizedString("Settings", comment: "screen title")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        studyLanguageCell.textLabel?.text = NSLocalizedString("Language to study", comment: "setting")
        nativeLanguageCell.textLabel?.text = NSLocalizedString("Native language", comment: "setting")
        [studyLanguageCell, nativeLanguageCell].forEach { $0.accessoryType = .disclosureIndicator }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        studyLanguageCell.detailTextLabel?.text = Self.languageName(for: prefs.languageToStudyPreference)
        nativeLanguageCell.detailTextLabel?.text = Self.languageName(for: prefs.nativeLanguagePreference)
        // Every appearance, not just the first: returning from Settings is exactly when
        // the answer is most likely to have changed.
        refreshReminderStanding()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    /// Says what the app can and cannot do, and what still works either way.
    ///
    /// Silence is the failure mode here: a switch drawn "off" with no explanation reads as
    /// a bug, and one drawn "on" that delivers nothing reads as a broken app. Neither
    /// wording asks for anything — practice never depended on notifications.
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard sections[section].title == NSLocalizedString("Reminders", comment: "settings section")
        else { return nil }

        switch reminderStanding {
        case .blocked:
            return NSLocalizedString(
                "Notifications are turned off for LearnWords in Settings. The Exercises screen still shows what is due.",
                comment: "Settings footer when notifications are blocked")
        case .silenced:
            return NSLocalizedString(
                "Reminders are allowed but every alert style is off, so they will arrive silently in Notification Center.",
                comment: "Settings footer when notifications are allowed but invisible")
        case .allowed where prefs.remindersEnabled:
            let rule = NSLocalizedString(
                "You are reminded on days when words are due, and not on days when none are.",
                comment: "Settings footer when reminders are on")
            guard let next = nextReminderAt else {
                return rule + " " + NSLocalizedString(
                    "Nothing is scheduled: no words come due in the next two weeks.",
                    comment: "Settings footer when no reminder is pending")
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return rule + " " + String(format: NSLocalizedString(
                "Next reminder: %@.", comment: "Settings footer; placeholder is a date and time"),
                                       formatter.string(from: next))
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].cells.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        sections[indexPath.section].cells[indexPath.row]
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cell = sections[indexPath.section].cells[indexPath.row]

        if cell === studyLanguageCell {
            pushLanguagePicker(title: studyLanguageCell.textLabel?.text,
                               current: prefs.languageToStudyPreference) { [weak self] in
                self?.prefs.languageToStudyPreference = $0
            }
        } else if cell === nativeLanguageCell {
            pushLanguagePicker(title: nativeLanguageCell.textLabel?.text,
                               current: prefs.nativeLanguagePreference) { [weak self] in
                self?.prefs.nativeLanguagePreference = $0
            }
        }
    }

    private func pushLanguagePicker(title: String?, current: String?, onSelect: @escaping (String) -> Void) {
        let picker = LanguagePickerViewController(title: title, currentCode: current, onSelect: onSelect)
        navigationController?.pushViewController(picker, animated: true)
    }
}

// MARK: - Cells (view layer: emit intent, decide nothing)

private final class SliderCell: UITableViewCell {

    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let format: String
    private let onChange: (Float) -> Void

    init(title: String, minimum: Float, maximum: Float, format: String, value: Float,
         onChange: @escaping (Float) -> Void) {
        self.format = format
        self.onChange = onChange
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = UIColor(named: "TextSecondary")
        valueLabel.textAlignment = .right

        slider.minimumValue = minimum
        slider.maximumValue = maximum
        slider.value = value
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        updateValueLabel()

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        let stack = UIStackView(arrangedSubviews: [titleRow, slider])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    @objc private func sliderChanged() {
        updateValueLabel()
        onChange(slider.value)
    }

    private func updateValueLabel() {
        valueLabel.text = String(format: format, slider.value)
    }
}

/// A time of day. `UIDatePicker`'s compact style keeps it to one row on iOS 14+; below
/// that the wheel is inline, which is what iOS 12 and 13 have always looked like.
private final class TimeCell: UITableViewCell {

    private let picker = UIDatePicker()
    private let titleLabel = UILabel()
    private let onChange: (Int, Int) -> Void

    init(title: String, hour: Int, minute: Int, onChange: @escaping (Int, Int) -> Void) {
        self.onChange = onChange
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none
        textLabel?.text = title

        picker.datePickerMode = .time
        if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .compact }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        picker.date = Calendar.current.date(from: components) ?? Date()
        picker.addTarget(self, action: #selector(changed), for: .valueChanged)

        // Laid out rather than parked in `accessoryView`. As an accessory the compact
        // picker takes its intrinsic width first and the title gets whatever is left —
        // which on a real device was four characters: "R…". A stack with the picker
        // resisting compression and the label free to shrink last puts the space where the
        // words are, and matches how `SliderCell` is built.
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        textLabel?.text = nil

        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, picker])
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Greyed rather than hidden when reminders are off, so the chosen time stays visible.
    var isEnabled: Bool {
        get { picker.isEnabled }
        set {
            picker.isEnabled = newValue
            titleLabel.textColor = newValue ? .lwTextPrimary : .lwTextSecondary
        }
    }

    @objc private func changed() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
        onChange(parts.hour ?? 0, parts.minute ?? 0)
    }
}

private final class SwitchCell: UITableViewCell {

    private let toggle = UISwitch()
    private let onChange: (Bool) -> Void

    init(title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none
        textLabel?.text = title
        toggle.isOn = isOn
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        accessoryView = toggle
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Moves the switch without reporting it as a change — for correcting the UI to match
    /// the world, which is not the learner doing something.
    func setOn(_ isOn: Bool) {
        guard toggle.isOn != isOn else { return }
        toggle.setOn(isOn, animated: true)
    }

    @objc private func toggled() {
        onChange(toggle.isOn)
    }
}
