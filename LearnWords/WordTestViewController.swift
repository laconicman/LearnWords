//
//  WordTestViewController.swift
//  LearnWords
//
//  Created by Paul on 09.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//
// TODO: Different animation for right and wrong answers
// TODO: Show translation under the word instead of replacing it. Done
// TODO: Show translation in red (black) if forgot (plus some animation, native lang prounosation or even taptic), in green if know.


import UIKit
import GameplayKit
import AVFoundation

final class WordTestViewController: UIViewController {
    
    // MARK: - Properties
    
    @IBOutlet weak var roundProgress: UIProgressView!
    @IBOutlet weak var wordDefinition: UILabel! //?
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var prompt: UILabel!

    @IBOutlet weak var knowButton: UIButton!
    @IBOutlet weak var forgotButton: UIButton!
    
    @IBAction func lookUpAction(_ sender: UIButton) {
        lookUp(term: prompt.text ?? "", sender: self)
    }
    
    var wordsInTest = [WordAndStat]()
    var shownWord: WordAndStat!

    private var progressStep: Float = 0.0
    //   var showingQuestion = true

    // MARK: -
    func afterAnswer(isKnown: Bool) {
        if !wordsInTest.isEmpty {
            shownWord = wordsInTest.remove(at: 0)
            
            isKnown ? shownWord.increaseKnown() : shownWord.decreaseKnown()
            
            Storage.shownWords.append(shownWord)
            roundProgress.progress = Float(Storage.shownWords.count) * progressStep
//            //disable buttons and ShowNextButton Instead and autoSkip
//            //prepareForNextQuestion()
            showAnswer(for: shownWord, isKnown: isKnown)
        } else { // this never happens for now
            navigationController?.tabBarController?.selectedIndex = 0
        }
    }
    
    // MARK: - Interface Builder actions
    @IBAction func knowButtonAction(_ sender: UIButton) {
        afterAnswer(isKnown: true)
        /*
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: prompt.text ?? "") {
            let rlvc = UIReferenceLibraryViewController(term: prompt.text!)
            //rlvc.editButtonItem what is this
            //rlvc.setEditing(true, animated: true)
            //rlvc.modalPresentationStyle = .popover //no effect on iphone
            //wordDefinition.text =  rlvc.editButtonItem.title
            //present(rlvc, animated: true)
            
            if let definitionValues = rlvc.value(forKey: "_definitionValues") as? NSArray {
                var definitions = [NSAttributedString]()
                
                for (i, definitionValue) in definitionValues.enumerated() {
                    if let dvObj = (definitionValue as? NSObject) {
                        if let def = dvObj.value(forKey: "_definition") as? NSAttributedString {
                            definitions.append(def)
                            print("Index: \(i) \(def.string)")
                        }
                    }
                }
                
                // let terms = definitions[0].string.split(separator: ";")
                var i=0
                definitions[0].string.enumerateLines { (line, stop) in
                    print("\(line) i=\(i) stop=\(stop)")
                    if i<10 {
                        i += 1
                    } else {
                        stop = true
                    }
                }
                
                let dictionaryMain = split(definitions[0].string, by: "\n" + "\u{2028}")[1]
                print(dictionaryMain)
            }
        } */
    }
    
    @IBAction func forgotButtonAction(_ sender: UIButton) {
        haptic(feedback: .warning)
        //        showingQuestion = !showingQuestion
        afterAnswer(isKnown: false)
    }
    
    // MARK: - View Controller Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        startRound()
        
        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0

        if ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)) {
            navigationItem.largeTitleDisplayMode = .never
        }
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if wordsInTest.isEmpty {
            startRound()
        }
        askQuestion()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.hidesBarsOnTap = false
    }
    
    // MARK: - 
    
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
        
        UIView.transition(with: wordDefinition,
                          duration: isKnown ? 0.75 : 1.0,
                          options: [.transitionCrossDissolve],
                          animations: { [weak self] in
                            self?.knowButton?.isEnabled = false
                            if isKnown { self?.knowButton?.layer.opacity = 0.1 } else { self?.forgotButton?.layer.opacity = 0.1 }
                            self?.forgotButton?.isEnabled = false
                            self?.wordDefinition.attributedText = NSAttributedString(
                                string: LWUserDefaults.standard.foreignToNative ? shownWord.secondWord : shownWord.firstWord,
                                attributes: [.foregroundColor: isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)])
                            // prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        }) { [weak self] (ended) in
            self?.knowButton?.isEnabled = true
            if isKnown { self?.knowButton?.layer.opacity = 1 } else { self?.forgotButton?.layer.opacity = 1 }
            self?.forgotButton?.isEnabled = true
            self?.prepareForNextQuestion(withPrewiousKnown: isKnown)
        }
        //            prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[0]
        //            prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        
        if LWUserDefaults.standard.pronounceAnswersPreference {
            LWSpeechSynth.standard.speak(utteranceString: wordDefinition.attributedText!, language:
                                            LWUserDefaults.standard.foreignToNative ?
                                            LWUserDefaults.standard.nativeLanguagePreference! :  LWUserDefaults.standard.languageToStudyPreference!)
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
        prompt.attributedText = NSAttributedString(string: LWUserDefaults.standard.foreignToNative ? wordsInTest[0].firstWord : wordsInTest[0].secondWord)
        if LWUserDefaults.standard.pronounceQuestionsPreference {
            LWSpeechSynth.standard.speak(utteranceString: prompt.attributedText!, language: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.languageToStudyPreference! :  LWUserDefaults.standard.nativeLanguagePreference!)
        }
        wordDefinition.attributedText = NSAttributedString(
            string: "?",
            attributes: [.foregroundColor: UIColor(red: 0, green: 0.7, blue: 0.7, alpha: 1)])
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
            // self.prompt.textColor = UIColor.black
            self.wordDefinition.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 0)
            self.askQuestion()
        }
        animation.startAnimation(afterDelay: withPrewiousKnown ? 0.1 : 2.0)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return navigationController?.hidesBarsOnTap ?? true
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
