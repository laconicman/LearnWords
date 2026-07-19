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
        title: NSLocalizedString("Pitch", comment: "setting"),
        minimum: 0.7, maximum: 1.9, format: "%.1f",
        value: Float(prefs.pitchMultiplierPreference)
    ) { [weak self] in self?.prefs.pitchMultiplierPreference = Double($0) }

    private lazy var rateCell = SliderCell(
        title: NSLocalizedString("Rate", comment: "setting"),
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

    private lazy var maxKnownLevelCell = SliderCell(
        title: NSLocalizedString("Known level", comment: "setting"),
        minimum: 1, maximum: 100, format: "%.0f",
        value: Float(prefs.maxKnownLevelPreference)
    ) { [weak self] in self?.prefs.maxKnownLevelPreference = Int($0.rounded()) }

    private var sections: [(title: String, cells: [UITableViewCell])] {
        [
            (NSLocalizedString("Languages", comment: "settings section"),
             [studyLanguageCell, nativeLanguageCell]),
            (NSLocalizedString("Speech", comment: "settings section"),
             [pitchCell, rateCell, pronounceAnswersCell, pronounceQuestionsCell]),
            (NSLocalizedString("Study", comment: "settings section"),
             [maxKnownLevelCell]),
        ]
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
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
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

    @objc private func toggled() {
        onChange(toggle.isOn)
    }
}
