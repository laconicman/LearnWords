//
//  WordPhoneticsViewController.swift
//  LearnWords
//
//  Created by  Paul on 24.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import UIKit
import Speech

class WordPhoneticsViewController: UIViewController, SFSpeechRecognizerDelegate {

    // MARK: Properties
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
    
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioEngine = AVAudioEngine()
    
    @IBOutlet var recognized: UILabel!
    
    @IBOutlet var recordButton: UIButton!
    
    // MARK: View Controller Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        // navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        wordsInTest = Storage.wordsAndStat.shuffled()
        Storage.shownWords = []
        
        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0
        
        // Disable the record buttons until authorization has been granted.
        recordButton.isEnabled = false
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if wordsInTest.isEmpty { wordsInTest = Storage.wordsAndStat.shuffled() }
        askQuestion()
        // Configure the SFSpeechRecognizer object already
        // stored in a local member variable.
        speechRecognizer.delegate = self
        if #available(iOS 13, *) {
            print("Supports on device recognition \(speechRecognizer.supportsOnDeviceRecognition)")
        }
        
        // Asynchronously make the authorization request.
        SFSpeechRecognizer.requestAuthorization { authStatus in

            // Divert to the app's main thread so that the UI
            // can be updated.
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.recordButton.isEnabled = true
                    
                case .denied, .restricted:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition not allowed", for: .disabled)
                    let ac = UIAlertController(title: NSLocalizedString("Allow speech recognition", comment: ""), message: NSLocalizedString("for phonetic exercises", comment: ""), preferredStyle: .alert)
                    
                    // create an "Add Word" button that submits the user's input
                    let submitAction = UIAlertAction(title: NSLocalizedString("Allow in settings", comment: ""), style: .default) { [unowned self] (action: UIAlertAction!) in
                        gotoAppSettings()
                    }
                    ac.addAction(submitAction)
                    ac.addAction(UIAlertAction(title: NSLocalizedString("Got it", comment: ""), style: .default))
                    self.present(ac, animated: true)
                    
                case .notDetermined:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle("Speech recognition permission needed", for: .disabled)
                    let ac = UIAlertController(title: NSLocalizedString("Allow speech recognition", comment: "for phonetic exercises"), message: nil, preferredStyle: .alert)

                    ac.addAction(UIAlertAction(title: NSLocalizedString("Got it", comment: ""), style: .default))
                    self.present(ac, animated: true)
                    
                default:
                    self.recordButton.isEnabled = false
                }
            }
        }
    }
    
    private func startRecording() throws {
        
        // Cancel the previous task if it's running.
        recognitionTask?.cancel()
        self.recognitionTask = nil
        
        // Configure the audio session for the app.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode

        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object") }
        recognitionRequest.shouldReportPartialResults = true
        
        // Keep speech recognition data on device
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // Create a recognition task for the speech recognition session.
        // Keep a reference to the task so that it can be canceled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [unowned self] result, error in
            var isFinal = false
            
            if let result = result {
                // Update the text view with the results.
                self.recognized.text = result.bestTranscription.formattedString
                isFinal = result.isFinal
                print("Text \(result.bestTranscription.formattedString)")
                if result.bestTranscription.formattedString.contains(self.wordsInTest[0].pair.components(separatedBy: "::")[0]) && isFinal {
                    self.afterAnswer(isKnown: true)
                }
            }
            
            if error != nil  || isFinal  {
                print("Stopping isFinal = \(isFinal). Error = \(String(describing: error))")
                // Stop recognizing speech if there is a problem.
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
                self.recordButton.setTitle("Start Recording", for: [])
                if error != nil, (error as! NSError).code != 203 {
                    let ac = UIAlertController(title: NSLocalizedString("Speech recognition error", comment: ""), message: error!.localizedDescription + "\n" + (error as! NSError).userInfo.debugDescription, preferredStyle: .alert)
                    ac.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                    self.present(ac, animated: true)
                }
            }
        }

        // Configure the microphone input.
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        // Let the user know to start talking.
        recognized.text = "Speak the translation"
    }
    
    // MARK: SFSpeechRecognizerDelegate
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle("Start Recording", for: [])
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle("Recognition Not Available", for: .disabled)
            print("Unavalible")
        }
        recordButton.tintColor = .black
    }
    
    // MARK: Interface Builder actions
    
    @IBAction func recordButtonTapped() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recordButton.isEnabled = false
            recordButton.setTitle("Stopping", for: .disabled)
            recordButton.tintColor = .black
        } else {
            do {
                try startRecording()
                recordButton.setTitle("Stop Recording", for: [])
                recordButton.tintColor = .red
            } catch {
                recordButton.setTitle("Recording Not Available", for: [])
                recordButton.tintColor = .black
            }
        }
    }
    
    
    
    
    func askQuestion() {
        //foreignWord.text = wordsInTest[questionCounter].components(separatedBy: "::")[1]
        guard !wordsInTest.isEmpty else {
            Storage.saveWords(Storage.shownWords)
            Storage.wordsAndStat = Storage.shownWords
            navigationController?.popToRootViewController(animated: true)
            return
        }
        prompt.attributedText = NSAttributedString(string: wordsInTest[0].pair.components(separatedBy: "::")[1])
        LWSpeechSynth.standard.speak(utteranceString: prompt.attributedText!)
        recognized.attributedText = NSAttributedString(
            string: "speak the translation",
            attributes: [.foregroundColor: UIColor(red: 0, green: 0.7, blue: 0.7, alpha: 1)])
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
        
        UIView.transition(with: recognized,
                          duration: isKnown ? 0.75 : 1.0,
                          options: [.transitionCrossDissolve],
                          animations: { [weak self] in
                            self?.knowButton?.isEnabled = false
                            self?.forgotButton?.isEnabled = false
                            if isKnown { self?.knowButton?.layer.opacity = 0.1 } else { self?.forgotButton?.layer.opacity = 0.1 }
                            self?.recognized.attributedText = NSAttributedString(
                                string: shownWord.pair.components(separatedBy: "::")[0],
                                attributes: [.foregroundColor: isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)])
                            self?.recognized.textColor = isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)
        }) { [weak self] (ended) in
            self?.knowButton?.isEnabled = true
            if isKnown { self?.knowButton?.layer.opacity = 1 } else { self?.forgotButton?.layer.opacity = 1 }
            self?.forgotButton?.isEnabled = true
            self?.prepareForNextQuestion(withPrewiousKnown: isKnown)
        }
        //            prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[0]
        //            prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
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

