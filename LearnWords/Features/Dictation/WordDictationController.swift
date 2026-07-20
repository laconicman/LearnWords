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
        guard let word = session.currentWord else { return }
        SpeechManager.shared.speak(NSAttributedString(string: word.firstWord), language: LWUserDefaults.standard.languageToStudyPreference!)
    }
    
    /// The round: queue, scoring and progress (TD-20). The screen keeps only its views.
    private var session = ExerciseSession(exercise: .dictation, words: [])
    
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
        guard let word = session.currentWord else { return true }
        answerMatched = answer == (LWUserDefaults.standard.foreignToNative ? word.secondWord : word.firstWord)
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
        
        if let answer = textField.text?.trimmingCharacters(in: .whitespaces), let word = session.currentWord {
            let res = match3(pattern: (LWUserDefaults.standard.foreignToNative ? word.secondWord : word.firstWord),
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        startRound()

        // Re-parenting drops `stackBottomConstraint` along with the stack, so keyboard
        // avoidance moves to the scroll view's bottom pin — same helper, same behaviour.
        let wrapped = ScrollableContent.wrap(stackView)
        if let bottom = wrapped?.bottomConstraint {
            underKeyboardLayoutConstraint.setup(bottom, view: view, minMargin: 0)
        }

        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0
        
        translationInput.clearsOnBeginEditing = true
        translationInput.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if session.isFinished {
            startRound()
        }
        askQuestion()
    }
    
    func afterAnswer(isKnown: Bool) {
        guard let answer = session.answer(isKnown: isKnown) else { // this never happens for now
            navigationController?.popToRootViewController(animated: true)
            return
        }

        // Answer feedback on the child view; the container transition stays separate (TD-16).
        if answer.isKnown {
            translationInput.kapow.shine()
            if answer.reachedKnownLevel {
                ExerciseFeedback.levelUp(on: view)
            }
        } else {
            translationInput.kapow.shake()
        }

        roundProgress.progress = session.progress
        showAnswer(for: answer.word, isKnown: answer.isKnown)
    }
    
    @IBAction func knowButtonAction(_ sender: UIButton) {
       afterAnswer(isKnown: true)
    }
    
    @IBAction func forgotButtonAction(_ sender: UIButton) {
        haptic(feedback: .warning)
        afterAnswer(isKnown: false)
    }
    
    func startRound() {
        session = .start(.dictation)
    }
    
    @objc func nextTapped() {
        guard !session.isFinished else { return }
        session.skip()
        roundProgress.progress = session.progress
        askQuestion()
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
                                attributes: [.foregroundColor: isKnown ? UIColor.lwAnswerCorrect : UIColor.lwAnswerWrong])
                            self?.translationInput.textColor = isKnown ? .lwAnswerCorrect : .lwAnswerWrong
        }) { [weak self] (ended) in
            self?.knowButton?.isEnabled = true
            if isKnown { self?.knowButton?.layer.opacity = 1 } else { self?.forgotButton?.layer.opacity = 1 }
            self?.forgotButton?.isEnabled = true
            self?.prepareForNextQuestion(withPrewiousKnown: isKnown)
        }
        //            prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[0]
        //            prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        
        if LWUserDefaults.standard.pronounceAnswersPreference {
            SpeechManager.shared.speak(translationInput.attributedText!, language: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.nativeLanguagePreference! : LWUserDefaults.standard.languageToStudyPreference!)
        }
    }
    
    
    func askQuestion() {
        //prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[1]
        guard let word = session.currentWord else {
            session.commit()
            navigationController?.popToRootViewController(animated: true)
            return
        }
        if session.skipsCurrentWord(includingLearned: LWUserDefaults.standard.includeLearnedWords) {
            nextTapped()
            return
        }
        prompt.attributedText = NSAttributedString(string: LWUserDefaults.standard.foreignToNative ?
                                                   word.firstWord : word.secondWord)
        if LWUserDefaults.standard.pronounceQuestionsPreference {
            SpeechManager.shared.speak(prompt.attributedText!, language: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.languageToStudyPreference!: LWUserDefaults.standard.nativeLanguagePreference!)
        }
        translationInput.isUserInteractionEnabled = true
        translationInput.attributedPlaceholder = NSAttributedString(
            string: NSLocalizedString("type in the translation", comment: "Placeholder promt"),
            attributes: [.foregroundColor: UIColor.lwAnswerPending])
        translationInput.text = ""
        translationInput.textColor = .lwTextPrimary
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

        ExerciseTransition.show(stackView)
    }

    func prepareForNextQuestion(withPrewiousKnown: Bool = true) {
        ExerciseTransition.advance(stackView, afterDelay: withPrewiousKnown ? 0.1 : 2.0) { [weak self] in
            self?.askQuestion()
        }
    }
    
    
    
    
}
