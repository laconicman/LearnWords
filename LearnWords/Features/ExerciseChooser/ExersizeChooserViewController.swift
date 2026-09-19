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
        // Also before the first frame. The storyboard draws this switch *on* and the stored
        // preference defaults to *off*, so assigning it in `viewDidAppear` showed the one and
        // then flipped to the other on first launch. This screen is the preference's only
        // writer, so reading it once is enough.
        includeLeanedWords.isOn = storedIncludeLearnedWords()
        ScrollableContent.wrap(contentStack,
                               insets: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16),
                               fillsScreen: false)
        // The counts on this screen are read from the store, so they go stale too.
        NotificationCenter.default.addObserver(self, selector: #selector(storeChangedRemotely),
                                               name: LWPersistence.storeDidChangeRemotely, object: nil)
    }

    @objc private func storeChangedRemotely() {
        if viewIfLoaded?.window != nil { showSetSummary() }
    }

    @IBOutlet weak var contentStack: UIStackView!
    @IBOutlet weak var numberOfWordsInSet: UILabel!

    @IBOutlet weak var directionOfExercises: LWButton!
    @IBOutlet weak var includeLeanedWords: UISwitch!

    /// Where the switch's first state comes from — a property with a default rather than a
    /// read of `LWUserDefaults` in `viewDidLoad`, so a test can pin it (REVIEW.md). A property,
    /// not an initialiser argument, because the storyboard builds this screen.
    var storedIncludeLearnedWords: () -> Bool = { LWUserDefaults.standard.includeLearnedWords }

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
    
    /// The switch now *chooses the scope* rather than filtering inside one.
    ///
    /// It had become vestigial: under due-driven practice the schedule already decides what
    /// is asked, and a learned word that is due should be asked — that is review. Its only
    /// remaining reader was the "Practise anyway" alert, so flipping it appeared to do
    /// nothing, which is exactly what the owner observed.
    ///
    /// The preference *key* keeps its historic name because it is persisted data; only the
    /// meaning and the label moved on.
    @IBAction func includeLearnedWordsChanged(_ sender: UISwitch) {
        LWUserDefaults.standard.includeLearnedWords = sender.isOn
        showSetSummary()
    }

    /// What the three exercise buttons will practise, as the switch currently reads.
    private var chosenScope: PracticeSession.Scope {
        includeLeanedWords.isOn ? .everything(includingLearned: true) : .due
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The practised set can change on another tab, so the direction is re-read on every
        // return — before the screen shows, not after, or the old direction flashes first.
        showDirection()
        showSetSummary()
    }

    /// Words in the set, how many are learned, and how many the schedule says are waiting.
    ///
    /// The due count is the headline: it is what the exercise buttons will actually ask,
    /// and what a reminder would have told them.
    private func showSetSummary() {
        let library = Library.shared
        let senses = (try? library.selectedSenses()) ?? []
        let learned = (try? ProgressCache.shared.index(for: senses, in: library.lexicon))?
            .learnedCount ?? 0

        var summary =
            NSLocalizedString("Total in set: ", comment: "Label total words in current set")
            + pluralizedWordCount(senses.count) + ". "
            + NSLocalizedString("Learned: ", comment: "Label learned words")
            + pluralizedWordCount(learned) + "."

        if includeLeanedWords?.isOn == true {
            return numberOfWordsInSet.text = summary + " " + NSLocalizedString(
                "Practising everything, due or not.",
                comment: "Label when the schedule is being bypassed")
        }
        if let digest = setDigest() {
            // `anyExerciseDueCount`, not `dueCount`: this screen's buttons each open a
            // per-exercise queue, so a headline built from engaged strands alone could say
            // "Nothing due" while Dictation had the whole set waiting. Reported by review,
            // PR #1. Reminders keep using `dueCount` — they should stay quiet about
            // exercises the learner has never chosen.
            summary += " " + (digest.anyExerciseDueCount > 0
                ? String(format: NSLocalizedString("%@ due now.", comment: "Label words due now"),
                         pluralizedWordCount(digest.anyExerciseDueCount))
                : nextDueDescription(digest))
        }
        numberOfWordsInSet.text = summary
    }

    /// "Nothing due — next on Thursday", or just "Nothing due" when the schedule is empty.
    ///
    /// `exercise` picks which schedule the date comes from. Without it the alert shown for
    /// one exercise quoted the whole set's earliest date — belonging to a different
    /// exercise, or missing entirely because a meaning due elsewhere is never "upcoming".
    /// Reported by review, PR #1.
    private func nextDueDescription(_ digest: ReviewSchedule.SetDigest,
                                    for exercise: Exercise? = nil) -> String {
        guard let next = exercise.map({ digest.nextDueAt(for: $0) }) ?? digest.nextDueAt else {
            return NSLocalizedString("Nothing due.", comment: "Label when nothing is scheduled")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return String(format: NSLocalizedString("Nothing due until %@.",
                                                comment: "Label; placeholder is a date"),
                      formatter.string(from: next))
    }

    private func setDigest() -> ReviewSchedule.SetDigest? {
        guard let set = Library.shared.selectedSet else { return nil }
        return try? ReviewSchedule(sets: [set], lexicon: Library.shared.lexicon).sets.first
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
    /// Practises what is due. When nothing is, offers to practise anyway rather than
    /// refusing — Anki's split between studying and studying *ahead*, where the second is a
    /// deliberate choice and answers are recorded the same either way.
    private func start(_ exercise: Exercise) {
        guard let set = Library.shared.selectedSet else { return }
        guard let digest = setDigest(), digest.askableCount > 0 else {
            showEmptySetAlert()
            return
        }
        // With the switch on, the schedule is bypassed on purpose and there is nothing to
        // ask about; with it off, an empty due list is worth a word before drilling ahead.
        // The exercise's own count, not the set's: with per-exercise schedules the set can
        // have work waiting while *this* exercise has none, and pushing then would open a
        // sitting with an empty queue that pops straight back. Reported by review, PR #1.
        if includeLeanedWords.isOn || digest.dueCount(for: exercise) > 0 {
            push(exercise, in: set, scope: chosenScope)
        } else {
            offerToPractiseAhead(exercise, in: set, digest: digest)
        }
    }

    private func push(_ exercise: Exercise, in set: WordSet, scope: PracticeSession.Scope) {
        do {
            let screen = try ExerciseViewController.make(exercise, in: set,
                                                        lexicon: Library.shared.lexicon,
                                                        scope: scope)
            navigationController?.pushViewController(screen, animated: true)
        } catch {
            debugLog("Could not start \(exercise): \(error)")
        }
    }

    private func offerToPractiseAhead(_ exercise: Exercise,
                                      in set: WordSet,
                                      digest: ReviewSchedule.SetDigest) {
        let alert = UIAlertController(
            title: NSLocalizedString("Nothing is due", comment: "Title for alert"),
            message: nextDueDescription(digest, for: exercise) + " "
                + NSLocalizedString("Practising ahead of schedule still counts, it just teaches less.",
                                    comment: "Message when nothing is due"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Practise anyway", comment: "AlertAction title"),
            style: .default) { [weak self] _ in
                // `includingLearned: true`, not the learner's filter. This button is only
                // reachable when nothing is due, so with the filter on it can select an
                // empty queue and the screen opens and bounces straight back. Choosing
                // "practise anyway" at that moment *is* the request to include them.
                // Reported by review, PR #1.
                self?.push(exercise, in: set, scope: .everything(includingLearned: true))
            })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "AlertAction title"), style: .cancel))
        present(alert, animated: true)
    }

    private func showEmptySetAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("No words to study", comment: "Title for alert"),
            message: NSLocalizedString("Current set is empty. Add some words to learn.",
                                       comment: "Message for alert for empty set to display"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Action for alert for empty set"), style: .default))
        present(alert, animated: true)
    }
}
