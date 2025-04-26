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

func lookUp(term: String, sender: UIViewController, location: CGPoint? = nil) {
    guard !term.isEmpty else { return }
    guard let term = split(term, by: ",;").first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
    // self.searchingIndicator.startAnimating()
    let dictionaryViewController = UIReferenceLibraryViewController(term: term)

        // Set the presentation style to .pageSheet or .formSheet
    dictionaryViewController.modalPresentationStyle = .pageSheet
        
    if #available(iOS 15.0, *) {
        if let sheet = dictionaryViewController.sheetPresentationController {
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .medium(),
                    .custom(identifier: .init("custom")) { context in
                        return context.maximumDetentValue - 44
                    },
                    .large()
                ]
            } else {
                sheet.detents = [
                    .medium(),
                    .large()
                ]
            }
            
            if #available(iOS 16.0, *) {
                sheet.selectedDetentIdentifier = sheet.detents.first(where: { $0.identifier.rawValue == "custom" })?.identifier ?? .large
            } else {
                sheet.selectedDetentIdentifier = .large
            }

            // Show a grabber at the top of the sheet
            sheet.prefersGrabberVisible = true
            
        }
    } /* else { // Not needed if we don't use `popover` `modalPresentationStyle`.
        // A safeguard for iPad issues with `present`
        // This was just an experiment with popover controller and it works fine on iOS
        if let popoverController = dictionaryViewController.popoverPresentationController {
            popoverController.sourceView = sender.view
            if let location {
                popoverController.sourceRect = CGRect(origin: location, size: CGSize(width: 1, height: 1))
            }
        }
    } */
    
    sender.present(dictionaryViewController, animated: true)
        // debugLog("presented dictionary view controller")
        
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

/*
func definition(for term: String, index: Int = 0) -> String {
    var dictionaryMain: String = ""
    // if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
        let rlvc = UIReferenceLibraryViewController(term: term)
        //rlvc.editButtonItem what is this
        //rlvc.setEditing(true, animated: true)
        //rlvc.modalPresentationStyle = .popover //no effect on iphone
        //wordDefinition.text =  rlvc.editButtonItem.title
        //present(rlvc, animated: true)
        var definitions = [NSAttributedString]()
        if let definitionValues = rlvc.value(forKey: "_definitionValues") as? NSArray {
            
            
            let definitionValue = definitionValues[0]
                if let dvObj = (definitionValue as? NSObject) {
                    if let def = dvObj.value(forKey: "_definition") as? NSAttributedString {
                        definitions.append(def)
                        // print("\(def.string)")
                        
                    }
                }
            
            
            // let terms = definitions[0].string.split(separator: ";")
            var i=0
            definitions[0].string.enumerateLines { (line, stop) in
                //print("\(line) i=\(i) stop=\(stop)")
                if i<3 {
                    i += 1
                } else {
                    stop = true
                }
            }
            
            dictionaryMain = split(definitions[index].string, by: "\n" + "\u{2028}")[1]
            // print(dictionaryMain)
            
        }
        return dictionaryMain.replacingOccurrences(of: "1", with: "")
//    } else {
//        return nil
//    }
} */

func split(_ str: String, by oneOfTheCharacters: String, union chSet: CharacterSet? = nil) -> [String] {
    var separatorSet = CharacterSet(charactersIn: oneOfTheCharacters)
    if let chSet = chSet { separatorSet = separatorSet.union(chSet) }
    return str.components(separatedBy: separatorSet).map({ $0.trimmingCharacters(in: .whitespaces)}).filter( { !$0.isEmpty })
}

 func pluralizedWordCount(_ count: Int) -> String
{
    let format = NSLocalizedString("WordCount", comment: "Count of words available")
    let wordCount = String.localizedStringWithFormat(format, count)
    return wordCount
}

func match3(pattern: String, answer: String, language: String, delimiters: String = ",;") -> Bool {
    
    // let patternComponents = pattern.components(separatedBy: CharacterSet(charactersIn: delimiters)).compactMap({$0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)})
    func filterLexicalClasses(phrase: String, lang: String, classes: [String] = ["Determiner", "Particle",  /* "Other", "Preposition","OtherWord"*/]) -> [String] {
        var phraseWordsClassified = [String]()
        
        phrase.enumerateLinguisticTags(in: phrase.startIndex..<phrase.endIndex,
                                       scheme: NSLinguisticTagScheme.nameTypeOrLexicalClass.rawValue,
                                       orthography: NSOrthography.defaultOrthography(forLanguage: lang),
                                       invoking: { (tag, tokenRange, QRange, stop) in
            debugLog("Tag for word \(String(phrase[tokenRange])) is \(tag)")
            if !classes.contains(tag) {
                
                let word = String(phrase[tokenRange])
                phraseWordsClassified.append(word)}
            //print("\(String(describing: phraseWordsClassified.last)): \(tag) t2: \(phrase[QRange])")
        })
        
//        taggerLexical.enumerateTags(in: phrase.startIndex..<phrase.endIndex, unit: .word, scheme: .lexicalClass /*, options: [.omitPunctuation, .omitWhitespace]*/) { tag, tokenRange in
//            if let tag = tag, !classes.contains(tag.rawValue) {
//                let word = String(phrase[tokenRange])
//                phraseWordsClassified.append(word)
//                // print("\(word): \(tag.rawValue)\(word == lemma ? "" : " | Lemma: \(lemma) " )")
//            }
//            return true
//        }
        return phraseWordsClassified
    }
    
//    taggerLexical.string = answer.lowercased()
//    taggerLexical.setLanguage(NLLanguage(rawValue: "en"), range: answer.startIndex..<answer.endIndex)
//    var answerSet = Set<WordAndClass>()
//    taggerLexical.enumerateTags(in: answer.startIndex..<answer.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
//        if let tag = tag {
//            // let lemma = taggerLexical.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? ""
//            let word = String(answer[tokenRange])
//            answerSet.insert(WordAndClass(word: word, lexicalClass: tag.rawValue))
//            // print("\(word): \(tag.rawValue)\(word == lemma ? "" : " | Lemma: \(lemma) " )")
//        }
//        return true
//    }
    
    debugLog(filterLexicalClasses(phrase: answer,  lang: language).debugDescription)
    debugLog(filterLexicalClasses(phrase: pattern, lang: language).debugDescription)
    
    let answerFiltered = filterLexicalClasses(phrase: answer, lang: language)
    let patternFiltered = filterLexicalClasses(phrase: pattern, lang: language)
    
    // let filterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: delimiters))
    let patternFilteredString = patternFiltered.joined().lowercased()
    //.filter({ filterSet.contains($0.unicodeScalars.first!) == false })
    //.filter({ ($0.isPunctuation || $0.isWhitespace) == false })
    print(patternFilteredString)
    let answerSetString = answerFiltered.joined().lowercased()
    //.filter({ filterSet.contains($0.unicodeScalars.first!) == false })
    //.replacingOccurrences(of: " ", with: "")
    print(answerSetString)
    //let patternSet = Set(patternFiltered.map({ $0.word }))
    let patternSet = patternFilteredString.components(separatedBy: CharacterSet(charactersIn: delimiters))
        .compactMap({$0.filter({ ($0.isPunctuation || $0.isWhitespace) == false })})
    print(patternSet)
    let answerSet = answerSetString.components(separatedBy: CharacterSet(charactersIn: delimiters))
        .compactMap({$0.filter({ ($0.isPunctuation || $0.isWhitespace) == false })})
    //let intersection = answerSet.intersection(patternSet)

 //   print(Array(intersection))
//    print(Array(patternSet).map({ $0.word + " - " + $0.lexicalClass}))
//    let aarr = Array(answerSet).map({ $0.word + " - " + $0.lexicalClass})
//    print(aarr)
    
    //return patternSet.contains(answerSetString)
    
    if Set(patternSet).intersection(Set(answerSet)).isEmpty {
        return false
    } else {
        return true
    }
}
