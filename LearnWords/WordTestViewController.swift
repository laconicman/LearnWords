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
    
    @IBOutlet weak var wordDefinition: UILabel! //?
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var prompt: UILabel!

    @IBOutlet weak var knowButton: UIButton!
    @IBOutlet weak var forgotButton: UIButton!
    
    @IBAction func lookUpAction(_ sender: UIButton) {
        // TODO: If it is the first time, then show "The app relies on system dictionries, . They can be used ofline. Make sure you have downloaded the dictionaries you need. To add or remove didctionaries use Manage Dictionaries button on the next screen" "Remind me next time" "Got it"
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: prompt.text ?? "") {
            let rlvc = UIReferenceLibraryViewController(term: prompt.text!)
            //rlvc.editButtonItem what is this
            //rlvc.setEditing(true, animated: true)
            rlvc.modalPresentationStyle = .popover //no effect on iphone
            //wordDefinition.text =  rlvc.editButtonItem.title
            present(rlvc, animated: true)
        }
    }
    
    var wordsInTest = [WordAndStat]()
    var shownWord: WordAndStat!
    var questionCounter: Int {
        return wordsInTest.count
    }
 //   var showingQuestion = true
 //   var reflibvc: ReferenceLibraryViewController

    
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
                
                //print(t ?? "no value")

            }
        }*/
    }
    
    @IBAction func forgotButtonAction(_ sender: UIButton) {
        haptic(feedback: .warning)
        //        showingQuestion = !showingQuestion
        afterAnswer(isKnown: false)
    }
    

    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        wordsInTest = Storage.wordsAndStat.shuffled()
        // wordsInTest = GKRandomSource.sharedRandom().arrayByShufflingObjects(in: wordsInTest) as! [WordAndStat]
        //showingQuestion = true
        
        title = "Test"
        
        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0
        
        //let rlvc = storyboard?.instantiateViewController(withIdentifier: "ReferenceLibrary")
        //let rlvc = ReferenceLibraryViewController(term: "apple")
        
        // MARK: - Decoration
        
        //Lets practice loops, typecasts, optionals
        // Buttons are inside the stack
//        for chv in (stackView.viewWithTag(10)?.subviews)! {
//            if let bt = chv as? UIButton {
//
//                bt.layer.borderWidth = 1
//                bt.layer.borderColor = UIColor.lightGray.cgColor
//                bt.layer.cornerRadius = 5
//                // Or if you prefer custom colors
//                //bt.layer.borderColor = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.6).cgColor
//            }
//        }
        
        
        if ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)) {
            navigationItem.largeTitleDisplayMode = .never
        }
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        
        askQuestion()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.hidesBarsOnTap = false
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
        
        UIView.transition(with: wordDefinition,
                          duration: isKnown ? 0.75 : 1.0,
                          options: [.transitionCrossDissolve],
                          animations: { [weak self] in
                            self?.knowButton?.isEnabled = false
                            if isKnown { self?.knowButton?.layer.opacity = 0.1 } else { self?.forgotButton?.layer.opacity = 0.1 }
                            self?.forgotButton?.isEnabled = false
                            self?.wordDefinition.attributedText = NSAttributedString(
                                string: shownWord.pair.components(separatedBy: "::")[0],
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
    }
    
    func askQuestion() {
        //prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[1]
        guard !wordsInTest.isEmpty else {
            navigationController?.tabBarController?.selectedIndex = 0
            return
        }
        prompt.attributedText = NSAttributedString(string: wordsInTest[0].pair.components(separatedBy: "::")[1])
        LWSpeechSynth.standard.speak(utteranceString: prompt.attributedText!)
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
            self.prompt.textColor = UIColor.black
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
