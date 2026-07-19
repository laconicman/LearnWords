//
//  LanguagePickerViewController.swift
//  LearnWords
//
//  Single-choice language list for the settings screen.
//

import UIKit

final class LanguagePickerViewController: UITableViewController {

    private let currentCode: String?
    private let onSelect: (String) -> Void

    init(title: String?, currentCode: String?, onSelect: @escaping (String) -> Void) {
        self.currentCode = currentCode
        self.onSelect = onSelect
        if #available(iOS 13.0, *) {
            super.init(style: .insetGrouped)
        } else {
            super.init(style: .grouped)
        }
        self.title = title
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        SettingsViewController.languages.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Language")
            ?? UITableViewCell(style: .default, reuseIdentifier: "Language")
        let language = SettingsViewController.languages[indexPath.row]
        cell.textLabel?.text = language.name
        cell.accessoryType = language.code == currentCode ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect(SettingsViewController.languages[indexPath.row].code)
        navigationController?.popViewController(animated: true)
    }
}
