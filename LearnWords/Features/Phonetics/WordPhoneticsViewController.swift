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

    // MARK: - Properties
    
    @IBOutlet weak var roundProgress: UIProgressView!
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var prompt: UILabel!

    @IBOutlet weak var knowButton: UIButton!
    @IBOutlet weak var forgotButton: UIButton!
    
    @IBAction func lookUpAction(_ sender: UIButton) {
        lookUp(term: prompt.text ?? "", sender: self)
    }
    
    @IBAction func listenAction(_ sender: Any) {
        if audioEngine.isRunning {
            recordButtonTapped()
        }
        // try? audioSession.setCategory(.playback, mode: .measurement, options: [])
        try? audioSession.setCategory(.playback, mode: .default, policy: .default, options: [])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        SpeechManager.shared.speak(NSAttributedString(string: wordsInTest[0].firstWord), language: LWUserDefaults.standard.languageToStudyPreference!)
    }
    var wordsInTest = [WordAndStat]()
    var shownWord: WordAndStat!
    
    private var progressStep: Float = 0.0
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.nativeLanguagePreference! : LWUserDefaults.standard.languageToStudyPreference!))!
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioEngine = AVAudioEngine()
    
    let audioSession = AVAudioSession.sharedInstance()
    
    @IBOutlet var recognized: UILabel!
    
    @IBOutlet var recordButton: UIButton!
    
    // MARK: - View Controller Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(nextTapped))
        startRound()
        
        stackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        stackView.alpha = 0
        
        // Disable the record buttons until authorization has been granted.
        recordButton.isEnabled = false
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.hidesBarsOnTap = false
        if wordsInTest.isEmpty {
            startRound()
        }
        askQuestion()
        
            audioSession.requestRecordPermission()
            { [unowned self] allowed in
                DispatchQueue.main.async {
                    if !allowed {
                        self.recordButton.isEnabled = false
                        self.recordButton.setTitle(NSLocalizedString("Microphone access denied.", comment: "Button title"), for: .disabled)
                        let ac = UIAlertController(title: NSLocalizedString("Allow microphone usage", comment: "Alert title"), message: NSLocalizedString("for phonetic exercises", comment: "Alert message"), preferredStyle: .alert)
                        
                        let submitAction = UIAlertAction(title: NSLocalizedString("Allow in settings", comment: ""), style: .default) { /* [unowned self] */ (action: UIAlertAction!) in
                            gotoAppSettings()
                        }
                        ac.addAction(submitAction)
                        ac.addAction(UIAlertAction(title: NSLocalizedString("Got it", comment: "Button title"), style: .default))
                        self.present(ac, animated: true)
                    }
                }
            }
        
        // Configure the SFSpeechRecognizer object already
        // stored in a local member variable.
        speechRecognizer.delegate = self
//        if #available(iOS 13, *) {
//            print("Supports on device recognition \(speechRecognizer.supportsOnDeviceRecognition)")
//        }
        
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
                    self.recordButton.setTitle(NSLocalizedString("Recognition not allowed", comment: "Button title"), for: .disabled)
                    let ac = UIAlertController(title: NSLocalizedString("Allow speech recognition", comment: "Alert title"), message: NSLocalizedString("for phonetic exercises", comment: "Alert message"), preferredStyle: .alert)
                    
                    let submitAction = UIAlertAction(title: NSLocalizedString("Allow in settings", comment: ""), style: .default) { /* [unowned self] */ (action: UIAlertAction!) in
                        gotoAppSettings()
                    }
                    ac.addAction(submitAction)
                    ac.addAction(UIAlertAction(title: NSLocalizedString("Got it", comment: "Button title"), style: .default))
                    self.present(ac, animated: true)
                    
                case .notDetermined:
                    self.recordButton.isEnabled = false
                    self.recordButton.setTitle(NSLocalizedString("Recognition permission needed", comment: "Button title"), for: .disabled)
                    let ac = UIAlertController(title: NSLocalizedString("Allow speech recognition", comment: "for phonetic exercises"), message: nil, preferredStyle: .alert)

                    ac.addAction(UIAlertAction(title: NSLocalizedString("Got it", comment: "Button title"), style: .default))
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

        try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        // try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.])
        try audioSession.setActive(true) // options: .notifyOthersOnDeactivation) - this option can be passed only only when passing `false` to `setActive()`.
        let inputNode = audioEngine.inputNode

        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object") }
        recognitionRequest.shouldReportPartialResults = true
        
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        // TODO: Check if recognition is avaliable
        // guard speechRecognizer.isAvailable else { showAlert(); return }
        // Create a recognition task for the speech recognition session.
        // Keep a reference to the task so that it can be canceled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false
            
            if let result = result {
                // Update the text view with the results.
                self?.recognized.text = result.bestTranscription.formattedString.lowercased()
                isFinal = result.isFinal
                // print("Text \(result.bestTranscription.formattedString)")
                // print("Transcriptions \(result.transcriptions.map{ $0.formattedString.lowercased() })")
                if !(self?.wordsInTest.isEmpty ?? true),  match3(
                    pattern: (LWUserDefaults.standard.foreignToNative ? self?.wordsInTest[0].secondWord: self?.wordsInTest[0].firstWord) ?? "",
                    answer: result.bestTranscription.formattedString.lowercased(),
                    language: (LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.nativeLanguagePreference :
                                LWUserDefaults.standard.languageToStudyPreference)!,
                    delimiters: ",; ")    /* && isFinal */ {
                    self?.recordButtonTapped() // stop the audio
                    
                    self?.recognized.text = LWUserDefaults.standard.foreignToNative ? self?.wordsInTest[0].secondWord : self?.wordsInTest[0].firstWord
                    self?.afterAnswer(isKnown: true)
                } else {
                   // self.correct.text = ""
                }
            }
            
            if error != nil  || isFinal  {
                // print("Stopping isFinal = \(isFinal). Error = \(String(describing: error))")
                // Stop recognizing speech if there is a problem.
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self?.recognitionRequest = nil
                self?.recognitionTask = nil

                self?.recordButton.isEnabled = true
                self?.recordButton.setTitle(NSLocalizedString("Start recognition", comment: "Button title"), for: [])
                self?.recordButton.tintColor = .black
                if let error, (error as NSError).code != 203 {
                    
                    var ac = UIAlertController(title: NSLocalizedString("Speech recognition error", comment: ""), message: error.localizedDescription + "\n" + (error as NSError).userInfo.debugDescription, preferredStyle: .alert)
                    if (error as NSError).code == 4 {
                        ac = UIAlertController(title: NSLocalizedString("Speech recognition error", comment: ""), message: error.localizedDescription + "\n Probably there is no internet connection. \n Recognition happens on Apple servers for most of devices. " , preferredStyle: .alert)
                    }
                    ac.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                    self?.present(ac, animated: true)
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
        // correct.text = "pronounce the translation"
    }
    
    // MARK: SFSpeechRecognizerDelegate
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            recordButton.isEnabled = true
            recordButton.setTitle(NSLocalizedString("Start recognition", comment: "Button title"), for: [])
        } else {
            recordButton.isEnabled = false
            recordButton.setTitle(NSLocalizedString("Recognition Not Available", comment: "Button title"), for: .disabled)
            // print("Unavalible")
        }
        recordButton.tintColor = .black
    }
    
    // MARK: - Interface Builder actions
    
    @IBAction func recordButtonTapped() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            
            recordButton.isEnabled = false
            recordButton.setTitle(NSLocalizedString("Stopping", comment: "Button title"), for: .disabled)
            recordButton.tintColor = .black
        } else {
            do {
                try startRecording()
                recordButton.setTitle(NSLocalizedString("Stop recognition", comment: "Button title"), for: [])
                recordButton.tintColor = .red
            } catch {
                recordButton.setTitle(NSLocalizedString("Recognition Not Available", comment: "Button title"), for: [])
                recordButton.tintColor = .black
            }
        }
    }
    // MARK: - 
    
    
    
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
            SpeechManager.shared.speak(prompt.attributedText!, language: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.languageToStudyPreference! : LWUserDefaults.standard.nativeLanguagePreference!)
        }
        recognized.attributedText = NSAttributedString(
            string: NSLocalizedString("pronounce the translation", comment: "label prompt"),
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

        ExerciseTransition.show(stackView)
    }
    
    func afterAnswer(isKnown: Bool) {
        if !wordsInTest.isEmpty {
            shownWord = wordsInTest.remove(at: 0)
            let wasKnown = shownWord.known >= WordAndStat.maxKnownLevel
            isKnown ? shownWord.increaseCorrect(exercize: "P") : shownWord.decreaseCorrect(exercize: "P")

            // Answer feedback on the child view; the container transition stays separate (TD-16).
            if isKnown {
                recognized.kapow.shine()
                if !wasKnown && shownWord.known >= WordAndStat.maxKnownLevel {
                    ExerciseFeedback.levelUp(on: view)
                }
            } else {
                recognized.kapow.shake()
            }

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
            
            if audioEngine.isRunning {
                recordButtonTapped()
            }
            // try? audioSession.setCategory(.playback, mode: .measurement, options: [])
            try? audioSession.setCategory(.playback, mode: .default, policy: .default, options: [])
            try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
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
                                string: LWUserDefaults.standard.foreignToNative ? shownWord.secondWord : shownWord.firstWord,
                                attributes: [.foregroundColor: isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)])
                            self?.view.layoutIfNeeded()
                            debugLog("begin transition")
                            self?.recognized.textColor = isKnown ? UIColor(red: 0, green: 0.7, blue: 0, alpha: 1) : UIColor(red: 0.7, green: 0.0, blue: 0, alpha: 1)
        }) { [weak self] (ended) in
            self?.knowButton?.isEnabled = true
            if isKnown { self?.knowButton?.layer.opacity = 1 } else { self?.forgotButton?.layer.opacity = 1 }
            self?.forgotButton?.isEnabled = true
            self?.prepareForNextQuestion(withPrewiousKnown: isKnown)
        }
        //            prompt.text = wordsInTest[questionCounter].components(separatedBy: "::")[0]
        //            prompt.textColor = UIColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        if audioEngine.isRunning {
            recordButtonTapped()
        }
        // try? audioSession.setCategory(.playback, mode: .measurement, options: [])
        try? audioSession.setCategory(.playback, mode: .default, policy: .default, options: [])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        if LWUserDefaults.standard.pronounceAnswersPreference {
            SpeechManager.shared.speak(recognized.attributedText!, language: LWUserDefaults.standard.foreignToNative ? LWUserDefaults.standard.nativeLanguagePreference! : LWUserDefaults.standard.languageToStudyPreference!)
        }
    }
    
    func prepareForNextQuestion(withPrewiousKnown: Bool = true) {
        ExerciseTransition.advance(stackView, afterDelay: withPrewiousKnown ? 0.1 : 2.0) { [weak self] in
            self?.askQuestion()
        }
    }
    

}

