//
//  ExersizeChooserViewController.swift
//  LearnWords
//
//  Created by  Paul on 28.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import UIKit

class ExersizeChooserViewController: UIViewController {


    
    override func viewDidLoad() {
        super.viewDidLoad()
        directionOfExercises.setImage(.systemImage("arrow.left.arrow.right"), for: .normal)
        // Before the storyboard's placeholder title can show.
        showDirection()
        ScrollableContent.wrap(contentStack,
                               insets: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showDirection()
        includeLeanedWords.isOn = LWUserDefaults.standard.includeLearnedWords
    }

    @IBOutlet weak var contentStack: UIStackView!
    @IBOutlet weak var numberOfWordsInSet: UILabel!

    @IBOutlet weak var directionOfExercises: LWButton!
    @IBOutlet weak var includeLeanedWords: UISwitch!

    /// One row that names the current direction and swaps it on tap.
    ///
    /// This replaces a two-segment control that had to fit both directions side by
    /// side. The titles are built from localized language names, so a pair like
    /// Portuguese/Ukrainian left ~170pt per segment and `UISegmentedControl` shrank
    /// the text to near-illegible. Showing one direction at a time gives the names
    /// the full width whatever languages are chosen.
    private func showDirection() {
        guard let native = Locale.current.localizedString(
                forLanguageCode: LWUserDefaults.standard.nativeLanguagePreference!)?.capitalized,
              let foreign = Locale.current.localizedString(
                forLanguageCode: LWUserDefaults.standard.languageToStudyPreference!)?.capitalized
        else { return }

        let reversed = LWUserDefaults.standard.foreignToNative
        let from = reversed ? foreign : native
        let to = reversed ? native : foreign
        directionOfExercises.setTitle("\(from) → \(to)", for: .normal)
    }

    @IBAction func directionChanged(_ sender: LWButton) {
        LWUserDefaults.standard.foreignToNative.toggle()
        showDirection()
    }
    
    @IBAction func includeLearnedWordsChanged(_ sender: UISwitch) {
        LWUserDefaults.standard.includeLearnedWords = sender.isOn
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        numberOfWordsInSet.text = NSLocalizedString("Total in set: ", comment: "Label total words in current set") + pluralizedWordCount(Storage.wordsAndStat.count) + ". " + NSLocalizedString("Learned: ", comment: "Label learned words") + pluralizedWordCount(Storage.wordsAndStat.reduce(0, { result, wAs in
            if wAs.known == WordAndStat.maxKnownLevel { return result + 1 } else { return result }
        })) + "."
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if  ["Learning Exercise", "Dictation Exercise", "Phonetic Exercise"].contains(segue.identifier) {
            let countOfWordsToShow: Int
            var alertMessage: String = NSLocalizedString("Current set is empty. Add some words to learn.", comment: "Message for alert for empty set to display")
            if includeLeanedWords.isOn {
                countOfWordsToShow = Storage.wordsAndStat.count
            } else {
                countOfWordsToShow = Storage.wordsAndStat.filter({ $0.known < WordAndStat.maxKnownLevel}).count
                if Storage.wordsAndStat.count > 0 {
                    alertMessage = NSLocalizedString("You may opt to include learned words if you'd like to continue exercises.", comment: "Message for alert for empty set to display")
                }
            }
            if countOfWordsToShow == 0 {
                let alert = UIAlertController(
                    title: NSLocalizedString("No words to study", comment: "Title for alert"),
                    message: alertMessage,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("OK", comment: "Action for alert for empty set"),
                    style: .default,
                    handler: nil))
                present(alert, animated: true, completion: nil)
            }
        }
    }

}
