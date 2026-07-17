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
    }
 
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let nativeLang = Locale.current.localizedString(forLanguageCode: LWUserDefaults.standard.nativeLanguagePreference!)?.capitalized,
           let foreignLang = Locale.current.localizedString(forLanguageCode: LWUserDefaults.standard.languageToStudyPreference!)?.capitalized {
            directionOfExercises.setTitle(nativeLang + ">" + foreignLang, forSegmentAt: 0)
            directionOfExercises.setTitle(foreignLang + ">" + nativeLang, forSegmentAt: 1)
            directionOfExercises.selectedSegmentIndex = LWUserDefaults.standard.foreignToNative ? 1 : 0
        }
        includeLeanedWords.isOn = LWUserDefaults.standard.includeLearnedWords
    }
    
    @IBOutlet weak var numberOfWordsInSet: UILabel!
    
    @IBOutlet weak var directionOfExercises: UISegmentedControl!
    @IBOutlet weak var includeLeanedWords: UISwitch!
    
    @IBAction func directionChanged(_ sender: UISegmentedControl) {
        LWUserDefaults.standard.foreignToNative = (sender.selectedSegmentIndex == 0) ? false : true
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
