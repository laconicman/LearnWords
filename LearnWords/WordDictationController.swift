//
//  WordDictation.swift
//  LearnWords
//
//  Created by  Paul on 26.05.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

// TODO: Add segmented control "Text|Sound|Both" (можно в виде иконок)

import UIKit
import AVFoundation

final class WordDictationController: UIViewController, UITextFieldDelegate {
    
    var wordsInTest = [WordAndStat]()
    var shownWord: WordAndStat!
    
    var answerMatched: Bool = false {
        didSet {
            if answerMatched == true {
                translationInput.isUserInteractionEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                    self.afterAnswer(isKnown: true)
                })
                
            }
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let answer = textField.text?.replacingCharacters(in: Range(range, in: textField.text!)!, with: string).lowercased().trimmingCharacters(in: .whitespaces)
        answerMatched = answer == wordsInTest[0].pair.components(separatedBy: "::")[0]
        print("Answer matched \(answerMatched)", string, textField.text, wordsInTest[0].pair.components(separatedBy: "::")[0])
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        afterAnswer(isKnown: false)
        textField.resignFirstResponder()
        return true
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        underKeyboardLayoutConstraint.setup(stackBottomConstraint, view: view, minMargin: 0)
        //navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        wordsInTest = Storage.wordsAndStat.shuffled()
        Storage.shownWords = []
        // title = "Translate"
        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0
        translationInput.clearsOnBeginEditing = true
        translationInput.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if wordsInTest.isEmpty { wordsInTest = Storage.wordsAndStat.shuffled() }
        askQuestion()
    }
    
    @IBOutlet weak var foreignWord: UILabel!
    @IBOutlet weak var translationInput: UITextField!
    @IBOutlet weak var stackView: UIStackView!
    
    @IBOutlet weak var knowButton: UIButton!
    @IBOutlet weak var forgotButton: UIButton!
    
    @IBOutlet weak var stackBottomConstraint: NSLayoutConstraint!
    let underKeyboardLayoutConstraint = UnderKeyboardLayoutConstraint()
    @IBAction func lookupAction(_ sender: UIButton) {
        guard let term = foreignWord.text, !term.isEmpty else { return }
        // self.searchingIndicator.startAnimating()
        let dictionaryViewController = UIReferenceLibraryViewController(term: term)
        self.present(dictionaryViewController, animated: true)
            //debugLog("presented dictionary view controlller")
            
            DispatchQueue.main.async
            { [weak self] in
                //debugLog("checking definition")
                if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) || !(self?.isReal(word: term) ?? false) { return }
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
        
//        // TODO: If it is the first time, then show "The app relies on system dictionries, . They can be used ofline. Make sure you have downloaded the dictionaries you need. To add or remove didctionaries use Manage Dictionaries button on the next screen" "Remind me next time" "Got it"
//        // TODO: show alert if no definition
//        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: foreignWord.text ?? "") {
//            let rlvc = UIReferenceLibraryViewController(term: foreignWord.text!)
//            //rlvc.editButtonItem what is this
//            //rlvc.setEditing(true, animated: true)
//            rlvc.modalPresentationStyle = .popover //no effect on iphone
//            //wordDefinition.text =  rlvc.editButtonItem.title
//            present(rlvc, animated: true)
//        }
    }
    
    func isReal(word: String) -> Bool {
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: word.utf16.count)
        // guard let range = NSRange(word) else { return false }
        // TODO: set language from settings
        let misspelledRange = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en")
        return misspelledRange.location == NSNotFound
    }
    
    func afterAnswer(isKnown: Bool) {
        if !wordsInTest.isEmpty {
            shownWord = wordsInTest.remove(at: 0)

            isKnown ? shownWord.increaseKnown() : shownWord.decreaseKnown()
            Storage.shownWords.append(shownWord)
//            //disable buttons and ShowNextButton Instead and autoSkip
//            //prepareForNextQuestion()
            showAnswer(for: shownWord, isKnown: isKnown)
        } else { // this never happens for now
            navigationController?.tabBarController?.selectedIndex = 0
        }
    }
    
    @IBAction func knowButtonAction(_ sender: UIButton) {
       afterAnswer(isKnown: true)
    }
    
    @IBAction func forgotButtonAction(_ sender: UIButton) {
        haptic(feedback: .warning)
        afterAnswer(isKnown: false)
    }
    
    @objc func nextTapped() {
//        showingQuestion = true
        if !wordsInTest.isEmpty {
            var knownWord = wordsInTest.remove(at: 0)
            knownWord.skiped += 1
            Storage.shownWords.append(knownWord)
            askQuestion()
        }
        //prepareForNextQuestion()
        
    }
    
    func showAnswer(for shownWord: WordAndStat, isKnown: Bool = false) {
        
        UIView.transition(with: translationInput,
                          duration: isKnown ? 0.75 : 1.0,
                          options: [.transitionCrossDissolve],
                          animations: { [weak self] in
                            self?.knowButton?.isEnabled = false
                            self?.forgotButton?.isEnabled = false
                            if isKnown { self?.knowButton?.layer.opacity = 0.1 } else { self?.forgotButton?.layer.opacity = 0.1 }
                            self?.translationInput.attributedText = NSAttributedString(
                                string: shownWord.pair.components(separatedBy: "::")[0],
                                attributes: [.foregroundColor: isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)])
                            self?.translationInput.textColor = isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)
        }) { [weak self] (ended) in
            self?.knowButton?.isEnabled = true
            if isKnown { self?.knowButton?.layer.opacity = 1 } else { self?.forgotButton?.layer.opacity = 1 }
            self?.forgotButton?.isEnabled = true
            self?.prepareForNextQuestion(withPrewiousKnown: isKnown)
        }
        //            prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[0]
        //            prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
    }
    
    
    func askQuestion() {
        //foreignWord.text = wordsInTest[questionCounter].components(separatedBy: "::")[1]
        guard !wordsInTest.isEmpty else {
            Storage.saveWords(Storage.shownWords)
            Storage.wordsAndStat = Storage.shownWords
            navigationController?.tabBarController?.selectedIndex = 0
            return
        }
        foreignWord.attributedText = NSAttributedString(string: wordsInTest[0].pair.components(separatedBy: "::")[1])
        LWSpeechSynth.standard.speak(utteranceString: foreignWord.attributedText!)
        translationInput.isUserInteractionEnabled = true
        translationInput.attributedPlaceholder = NSAttributedString(
            string: "type in translation",
            attributes: [.foregroundColor: UIColor(red: 0, green: 0.7, blue: 0.7, alpha: 1)])
        translationInput.text = ""
        translationInput.textColor = .black
        // foreignWord.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)


//        let rlvc = UIReferenceLibraryViewController(term: "apple")
//
//        addChildViewController(rlvc)
//
//        // 3: give the child a meaningfull frame: make it fill our view
//        rlvc.view.frame = container.bounds //not view.frame - mind the coodinate system
//        rlvc.view.translatesAutoresizingMaskIntoConstraints = false
//        container.addSubview(rlvc.view)
        
        
        
        
        

        //present(rlvc, animated: true)
        
        let animation = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.5) { [unowned self] in
            self.stackView.alpha = 1
            self.stackView.transform = CGAffineTransform.identity
        }
//        animation.addAnimations {
//            self.stackView.alpha = 0.5
//        }
        animation.startAnimation()

    
    }
    
    
    
    
    func prepareForNextQuestion(withPrewiousKnown: Bool = true) {
        let animation = UIViewPropertyAnimator(duration: 0.5, curve: .easeInOut) { [unowned self] in
            self.stackView.transform =  CGAffineTransform(scaleX: 0.8, y: 0.8)
            //self.stackView.transform =  CGAffineTransform(rotationAngle: 0.3*CGFloat.pi)
            self.stackView.alpha = 0
        }
        animation.addCompletion { [unowned self] position in
            //self.foreignWord.textColor = UIColor.black
            //self.translationInput.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 0)
            self.askQuestion()
        }
        animation.startAnimation(afterDelay: withPrewiousKnown ? 0.1 : 2.0)
    }
    
    
    
    
}
