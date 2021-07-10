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
    
    // MARK: - Properties
    
    @IBOutlet weak var roundProgress: UIProgressView!
    @IBOutlet weak var prompt: UILabel!
    @IBOutlet weak var translationInput: UITextField!
    @IBOutlet weak var stackView: UIStackView!
    
    @IBOutlet weak var knowButton: UIButton!
    @IBOutlet weak var forgotButton: UIButton!
    
    @IBOutlet weak var stackBottomConstraint: NSLayoutConstraint!
    let underKeyboardLayoutConstraint = UnderKeyboardLayoutConstraint()
    
    @IBAction func lookupAction(_ sender: UIButton) {
        lookUp(term: prompt.text ?? "", sender: self)
    }
    
    @IBAction func listenAction(_ sender: Any) {
        LWSpeechSynth.standard.speak(utteranceString: NSAttributedString(string: wordsInTest[0].firstWord), language: LWUserDefaults.standard.languageToStudyPreference!)
    }
    
    var wordsInTest = [WordAndStat]()
    var shownWord: WordAndStat!
    
    private var progressStep: Float = 0.0
    
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
        if LWUserDefaults.standard.foreignToNative {
            answerMatched = answer == wordsInTest[0].secondWord
        } else {
            answerMatched = answer == wordsInTest[0].firstWord
        }
        // print("Answer matched \(answerMatched)", string, textField.text, wordsInTest[0].pair.components(separatedBy: "::")[0])
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        
//        if let answer = textField.text?.lowercased().trimmingCharacters(in: .whitespaces),
//           split(answer, by: " " + ",").contains(
//            LWUserDefaults.standard.foreignToNative ? wordsInTest[0].secondWord : wordsInTest[0].firstWord) {
//            afterAnswer(isKnown: true)
//        } else {
//            afterAnswer(isKnown: false)
//        }
        
        if let answer = textField.text?.trimmingCharacters(in: .whitespaces) {
            let res = match3(pattern: (LWUserDefaults.standard.foreignToNative ? wordsInTest[0].secondWord : wordsInTest[0].firstWord),
                            answer: answer,
                            language: (LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.nativeLanguagePreference :
                                        LWUserDefaults.standard.languageToStudyPreference)!)
            afterAnswer(isKnown: res)
        } else {
            afterAnswer(isKnown: false)
        }
            
        // textField.resignFirstResponder()
        return true
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        underKeyboardLayoutConstraint.setup(stackBottomConstraint, view: view, minMargin: 0)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        startRound()
        
        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0
        
        translationInput.clearsOnBeginEditing = true
        translationInput.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if wordsInTest.isEmpty {
            startRound()
        }
        askQuestion()
    }
    
    func afterAnswer(isKnown: Bool) {
        if !wordsInTest.isEmpty {
            shownWord = wordsInTest.remove(at: 0)

            isKnown ? shownWord.increaseCorrect(exercize: "D") : shownWord.decreaseCorrect(exercize: "D")
            Storage.shownWords.append(shownWord)
            roundProgress.progress = Float(Storage.shownWords.count) * progressStep
//            //disable buttons and ShowNextButton Instead and autoSkip
//            //prepareForNextQuestion()
            showAnswer(for: shownWord, isKnown: isKnown)
        } else { // this never happens for now
            navigationController?.popToRootViewController(animated: true)
        }
    }
    
    @IBAction func knowButtonAction(_ sender: UIButton) {
       afterAnswer(isKnown: true)
    }
    
    @IBAction func forgotButtonAction(_ sender: UIButton) {
        haptic(feedback: .warning)
        afterAnswer(isKnown: false)
    }
    
    func startRound() {
        wordsInTest = Storage.wordsAndStat.shuffled()
        Storage.shownWords = []
        progressStep = 1.0 / Float(wordsInTest.count)
    }
    
    @objc func nextTapped() {
//        showingQuestion = true
        if !wordsInTest.isEmpty {
            var knownWord = wordsInTest.remove(at: 0)
            knownWord.skiped += 1
            Storage.shownWords.append(knownWord)
            roundProgress.progress = Float(Storage.shownWords.count) * progressStep
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
                                string: LWUserDefaults.standard.foreignToNative ? shownWord.secondWord : shownWord.firstWord,
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
        
        if LWUserDefaults.standard.pronounceAnswersPreference {
            LWSpeechSynth.standard.speak(utteranceString: translationInput.attributedText!, language: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.nativeLanguagePreference! : LWUserDefaults.standard.languageToStudyPreference!)
        }
    }
    
    
    func askQuestion() {
        //prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[1]
        guard !wordsInTest.isEmpty else {
            Storage.saveWords(Storage.shownWords)
            Storage.wordsAndStat = Storage.shownWords
            navigationController?.popToRootViewController(animated: true)
            return
        }
        if  (wordsInTest[0].known >= WordAndStat.maxKnownLevel) && (!LWUserDefaults.standard.includeLearnedWords) {
            nextTapped()
            return
        }
        prompt.attributedText = NSAttributedString(string: LWUserDefaults.standard.foreignToNative ?
                                                   wordsInTest[0].firstWord : wordsInTest[0].secondWord)
        if LWUserDefaults.standard.pronounceQuestionsPreference {
            LWSpeechSynth.standard.speak(utteranceString: prompt.attributedText!, language: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.languageToStudyPreference!: LWUserDefaults.standard.nativeLanguagePreference!)
        }
        translationInput.isUserInteractionEnabled = true
        translationInput.attributedPlaceholder = NSAttributedString(
            string: NSLocalizedString("type in translation", comment: "Placeholder promt"),
            attributes: [.foregroundColor: UIColor(red: 0, green: 0.7, blue: 0.7, alpha: 1)])
        translationInput.text = ""
        if #available(iOS 13.0, *) {
            translationInput.textColor = .label
        } else {
            translationInput.textColor = .black
        }
        // prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)


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
            //self.prompt.textColor = UIColor.black
            //self.translationInput.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 0)
            self.askQuestion()
        }
        animation.startAnimation(afterDelay: withPrewiousKnown ? 0.1 : 2.0)
    }
    
    
    
    
}
