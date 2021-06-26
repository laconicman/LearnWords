//
//  HapticFeedback.swift
//  LearnWords
//
//  Created by  Paul on 17.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import Foundation
import UIKit

func haptic(feedback: UINotificationFeedbackGenerator.FeedbackType) {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(feedback)
}

func lookUp(term: String, sender: UIViewController) {
    guard !term.isEmpty else { return }
    // self.searchingIndicator.startAnimating()
    let dictionaryViewController = UIReferenceLibraryViewController(term: term)
    sender.present(dictionaryViewController, animated: true)
        //debugLog("presented dictionary view controlller")
        
        DispatchQueue.main.async
        {
            //debugLog("checking definition")
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) || !(isReal(word: term)) { return }
            //debugLog("hasDefinition = \(hasDefinition)")
            // Prompt the user to set up their iOS dictionaries, the first time they use this only
            //if LWUserDefaults.standard.shouldDisplayFirstUseDictionaryPrompt
            //{
                // debugLog("First-time lookup. Let's see if the user has dictionaries set up...")
                // TODO: cherck for proper term in target language
                // if !UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: "OK")
                // {
                    // debugLog("No dictionaries set up. Prompting user.")
                    let alert = UIAlertController(
                        title: NSLocalizedString("DICTIONARY_TITLE", comment: "Title for dictionary prompt"),
                        message: NSLocalizedString("DICTIONARY_MESSAGE", comment: "Message for dictionary prompt"),
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(
                        title: NSLocalizedString("DICTIONARY_ACTION", comment: "Action for dictionary prompt"),
                        style: .default,
                        handler: nil))
                    dictionaryViewController.present(alert, animated: true, completion: nil)
                // }

                // Update preferences to silence this prompt next time
                // LWUserDefaults.standard.didDisplayFirstUseDictionaryPrompt()
            //}
        
    }
    // TODO: If it is the first time, then show "The app relies on system dictionries, . They can be used ofline. Make sure you have downloaded the dictionaries you need. To add or remove didctionaries use Manage Dictionaries button on the next screen" "Remind me next time" "Got it"
}
