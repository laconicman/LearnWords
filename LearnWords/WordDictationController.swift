//
//  WordDictation.swift
//  LearnWords
//
//  Created by  Paul on 26.05.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import UIKit
import AVFoundation

final class WordDictationController: UIViewController, UITextFieldDelegate {
    
    private lazy var sytheiser = AVSpeechSynthesizer() //Make it global, to avoid initialization for every vc creation
    private var utteranceString: NSString = ""
    
    var wordsInTest = [WordAndStat]()
    var shownWord: WordAndStat!
    
    var answerMatched: Bool = false {
        didSet {
            if answerMatched == true {
                // showAnswer(for: shownWord, isKnown: true)
                knowButtonAction(knowButton)
                
            }
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        answerMatched = textField.text?.replacingCharacters(in: Range(range, in: textField.text!)!, with: string) == wordsInTest[0].pair.components(separatedBy: "::")[0]
        print("Answer matched \(answerMatched)", string, textField.text, wordsInTest[0].pair.components(separatedBy: "::")[0])
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
    }
    
//    func textFieldDidBeginEditing(_ textField: UITextField) {
//        knowButtonAction(knowButton)
//    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        wordsInTest = Storage.wordsAndStat.shuffled()
        title = "Translate"
        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0
        translationInput.clearsOnBeginEditing = true
        translationInput.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        
        askQuestion()
    }
    
    @IBOutlet weak var foreignWord: UILabel!
    @IBOutlet weak var translationInput: UITextField!
    @IBOutlet weak var stackView: UIStackView!
    
    @IBOutlet weak var knowButton: UIButton!
    @IBOutlet weak var forgotButton: UIButton!
    
    @IBAction func lookupAction(_ sender: UIButton) {
        // TODO: If it is the first time, then show "The app relies on system dictionries, . They can be used ofline. Make sure you have downloaded the dictionaries you need. To add or remove didctionaries use Manage Dictionaries button on the next screen" "Remind me next time" "Got it"
        // TODO: show alert if no definition
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: foreignWord.text ?? "") {
            let rlvc = UIReferenceLibraryViewController(term: foreignWord.text!)
            //rlvc.editButtonItem what is this
            //rlvc.setEditing(true, animated: true)
            rlvc.modalPresentationStyle = .popover //no effect on iphone
            //wordDefinition.text =  rlvc.editButtonItem.title
            present(rlvc, animated: true)
        }
    }
    @IBAction func knowButtonAction(_ sender: UIButton) {
        if !wordsInTest.isEmpty {
            shownWord = wordsInTest.remove(at: 0)

            shownWord.known += 1
            Storage.shownWords.append(shownWord)
//            //disable buttons and ShowNextButton Instead and autoSkip
//            //prepareForNextQuestion()
            showAnswer(for: shownWord, isKnown: true)
        }
    }
    
    func showAnswer(for shownWord: WordAndStat, isKnown: Bool = false) {
        
        UIView.transition(with: translationInput,
                          duration: isKnown ? 0.75 : 1.0,
                          options: [.transitionCrossDissolve],
                          animations: { [weak self] in
                            self?.knowButton?.isEnabled = false
                            if isKnown { self?.knowButton?.layer.opacity = 0.1 }
                            self?.forgotButton?.isEnabled = false
//                            self?.translationInput.attributedText = NSAttributedString(
//                                string: shownWord.pair.components(separatedBy: "::")[0],
//                                attributes: [.foregroundColor: isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)])
                            self?.translationInput.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        }) { [weak self] (ended) in
            self?.knowButton?.isEnabled = true
            if isKnown { self?.knowButton?.layer.opacity = 1 }
            self?.forgotButton?.isEnabled = true
            self?.prepareForNextQuestion(withPrewiousKnown: isKnown)
        }
        //            prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[0]
        //            prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
    }
    

    
    @IBAction func forgotButtonAction(_ sender: UIButton) {
        // TODO: haptic feedback - wrap into function and use elsewhere
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
//        showingQuestion = !showingQuestion
        if !wordsInTest.isEmpty {
            var shownWord = wordsInTest.remove(at: 0)
            showAnswer(for: shownWord, isKnown: false)
            shownWord.unknown += 1
            Storage.shownWords.append(shownWord)
        }
    }
    
    
    func askQuestion() {
        //foreignWord.text = wordsInTest[questionCounter].components(separatedBy: "::")[1]
        guard !wordsInTest.isEmpty else { return }
        foreignWord.attributedText = NSAttributedString(string: wordsInTest[0].pair.components(separatedBy: "::")[1])
        utteranceString = (foreignWord.attributedText?.string as NSString?)!
        translationInput.attributedPlaceholder = NSAttributedString(
            string: "?",
            attributes: [.foregroundColor: UIColor(red: 0, green: 0.7, blue: 0.7, alpha: 1)])
        translationInput.text = ""
        translationInput.textColor = .black
        // foreignWord.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        let utterance = AVSpeechUtterance(attributedString: NSAttributedString(string: utteranceString as String))
        //var utterance =  AVSpeechUtterance(string: foreignWord.text ?? "")
        //We can get voices that are present in system and then use set them either with identifiers or by using default for language
        //let voices = AVSpeechSynthesisVoice.speechVoices()
        //utterance.voice = AVSpeechSynthesisVoice(identifier: voice[0])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        //we can check (get only)
        //let  lang = utterance.voice?.language
        // Another way to get BCP-47 the code for the user’s current locale (as in Settings) This is a class func
        //let currentLang = AVSpeechSynthesisVoice.currentLanguageCode()
        
        utterance.rate = 0.35
        
        utterance.pitchMultiplier = UserDefaults.standard.float(forKey: "pitchMultiplierPreference")
       // utterance.rate = AVSpeechUtteranceMinimumSpeechRate * 2
        //we can set pre and post utterance delay
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        
        sytheiser.stopSpeaking(at: .immediate)
        sytheiser.speak(utterance)


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
