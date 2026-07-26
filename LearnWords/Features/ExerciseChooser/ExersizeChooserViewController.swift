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
                               insets: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16),
                               fillsScreen: false)
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
        // Read from the set actually being practised, so a German set shows German even
        // if the global preference still says Spanish (`LanguagePair.forSet`).
        let pair = Library.shared.selectedSet.map(LanguagePair.forSet) ?? .current
        directionOfExercises.setTitle(
            "\(LanguageCode.displayName(pair.promptLanguage)) → "
            + LanguageCode.displayName(pair.answerLanguage), for: .normal)
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
        showSetSummary()
    }

    private func showSetSummary() {
        let library = Library.shared
        let senses = (try? library.selectedSenses()) ?? []
        let learned = (try? ProgressIndex(lexicon: library.lexicon, senses: senses))?
            .learnedCount ?? 0

        numberOfWordsInSet.text =
            NSLocalizedString("Total in set: ", comment: "Label total words in current set")
            + pluralizedWordCount(senses.count) + ". "
            + NSLocalizedString("Learned: ", comment: "Label learned words")
            + pluralizedWordCount(learned) + "."
    }

    // MARK: - Starting an exercise

    @IBAction func learningTapped(_ sender: Any) { start(.learning) }
    @IBAction func dictationTapped(_ sender: Any) { start(.dictation) }
    @IBAction func phoneticsTapped(_ sender: Any) { start(.phonetics) }

    /// Pushes the exercise, unless there is nothing to study.
    ///
    /// This guard used to live in `prepare(for:)`, which **cannot cancel a segue** — the
    /// alert appeared and the empty exercise was pushed underneath it anyway. Building the
    /// screen here instead of segueing makes refusing it a plain early return, and lets the
    /// exercise screen take its answer surface through an initializer.
    private func start(_ exercise: Exercise) {
        guard let set = Library.shared.selectedSet, hasWordsToStudy(in: set) else { return }
        do {
            let screen = try ExerciseViewController.make(exercise, in: set,
                                                        lexicon: Library.shared.lexicon)
            navigationController?.pushViewController(screen, animated: true)
        } catch {
            debugLog("Could not start \(exercise): \(error)")
        }
    }

    private func hasWordsToStudy(in set: WordSet) -> Bool {
        let library = Library.shared
        let pair = LanguagePair.forSet(set)
        let askable = (try? library.lexicon.senses(in: set.id,
                                                   from: pair.promptLanguage,
                                                   to: pair.answerLanguage)) ?? []
        let studiable: Int
        if includeLeanedWords.isOn {
            studiable = askable.count
        } else {
            let index = try? ProgressIndex(lexicon: library.lexicon, senses: askable)
            studiable = askable.count - (index?.learnedCount ?? 0)
        }
        guard studiable == 0 else { return true }

        let message = askable.isEmpty
            ? NSLocalizedString("Current set is empty. Add some words to learn.",
                                comment: "Message for alert for empty set to display")
            : NSLocalizedString("You may opt to include learned words if you'd like to continue exercises.",
                                comment: "Message for alert for empty set to display")
        let alert = UIAlertController(
            title: NSLocalizedString("No words to study", comment: "Title for alert"),
            message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Action for alert for empty set"), style: .default))
        present(alert, animated: true)
        return false
    }
}
