//
//  ViewController.swift
//  LearnWords
//
//  Created by Paul on 08.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//
// TODO: Consider NSSpellChecker
// Bundle.main.preferredLocalizations.swapAt(0, 2)
// Consider UserDefaults AppLanguages
// Show help or tutorial on first launch
// Play with UISwipeActionsConfiguration to configure row swipe actions
// Add look up button to navbar

import UIKit

final class WordTableViewController: UITableViewController, UISearchResultsUpdating {
    
    // MARK: searchController variables
    var filteredWords = [WordAndStat]() //? move to model?
    var wordsInTable : [WordAndStat] { // A subset of word pairs to display in tableView
        return (searchController.isActive && searchController.searchBar.text != "") ? filteredWords : Storage.wordsAndStat
    }
    var importedWords = [WordAndStat]()
    var importedWord = ""

    let searchController = UISearchController(searchResultsController: nil)

    @IBAction func goToSettings(_ sender: UIBarButtonItem) {
        gotoAppSettings()
    }
    // TODO: Make set selection screen
    @IBAction func unwindSegue(segue: UIStoryboardSegue) {
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //Some tests to discover various language tests found in system:
//        print("Bundle.main.preferredLocalizations \n", Bundle.main.preferredLocalizations)
//        print("UITextChecker.availableLanguages \n", UITextChecker.availableLanguages)
//        print("UITextInputMode.activeInputModes.map{$0.primaryLanguage...} \n", UITextInputMode.activeInputModes.map{$0.primaryLanguage ?? "primaryLanguage undefined"})
//        print("Bundle.main.bundleIdentifier \n", Bundle.main.bundleIdentifier ?? "")
//
//        //Some tests for user defaults
//
//        print("UserDefaults.standard.double(forKey: pitchMultiplierPreference) = " + String(UserDefaults.standard.double(forKey: "pitchMultiplierPreference")))
//        print("UserDefaults.standard.double(forKey: utteranceRatePreference) = " + String(UserDefaults.standard.double(forKey: "utteranceRatePreference")))
//        print("userDefaultsGroup.double(forKey: pitchMultiplierPreference) = " + String(userDefaultsGroup.double(forKey: "pitchMultiplierPreference")))
//        print("userDefaultsGroup.double(forKey: utteranceRatePreference) = " + String(userDefaultsGroup.double(forKey: "utteranceRatePreference")))
        
        //UserDefaults.standard //NSUserDefaults_Log_Nonsensical_Suites (suiteName: Bundle.main.bundleIdentifier)
        //We can get voices that are present in system and then use set them either with identifiers or by using default for language
        //let voices = AVSpeechSynthesisVoice.speechVoices()
        //utterance.voice = AVSpeechSynthesisVoice(identifier: voice[0])
        //utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        //we can check (get only)
        //let  lang = utterance.voice?.language
        // Another way to get BCP-47 the code for the user’s current locale (as in Settings) This is a class func
        //let currentLang = AVSpeechSynthesisVoice.currentLanguageCode()
        
        //Rebuilt in Storyboard
        //navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addNewWordSet))
        //let startButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(startTest))
        //let autoPlayButton = UIBarButtonItem(barButtonSystemItem: .reply, target: self, action: #selector(autoPlayTest))
        //navigationItem.rightBarButtonItems = [startButton, autoPlayButton]
        //navigationItem.backBarButtonItem = UIBarButtonItem(title: "End Test", style: .plain, target: nil, action: nil)
        //This doesn't work for some reason
        //navigationItem.backBarButtonItem?.title = "End Test"
        //navigationItem.backBarButtonItem?.style = .plain

        setupSearchController(placeholder: NSLocalizedString("Search words in sets", comment: "placeholder"), hideWhenAppear: true)

        if let savedWords: [WordAndStat] = userDefaultsGroup.decodeAndLoad(Storage.currentWordSet) {
                Storage.wordsAndStat = savedWords
            } else {
                Storage.saveInitialValues()
            }
        
/*            if let savedWords = defaults.object(forKey: "knownWords") as? [String] {
                knownWords = savedWords
            }*/

        if let importedString = userDefaultsGroup.string(forKey: "ImportedText") {
            if  importedString.aproxWordCount > 1 {
                let dictionaryEntries = split(importedString, by: "\n" + "\u{2028}", union: .newlines)
                importedWords = dictionaryEntries.compactMap( {
                    // FIXME: remove dash or mind it elsewhere
                    let e = split($0, by: "|:-–")
                    if e.first?.isEmpty ?? true || e.last?.isEmpty ?? true || e.count != 2 { return nil }
                    let f = e[0].trimmingCharacters(in: .whitespaces)
                    let s = e[1].trimmingCharacters(in: .whitespaces)
                    return WordAndStat(firstWord: f, secondWord: s, correct: [:], incorrect: [:], skiped: 0)
                })
                // TODO: Create a screen to verify and select `importedWords`. Check for duplicates
                importedWords = importedWords.filter({ (impW) -> Bool in
                    !Storage.wordsAndStat.contains { (storedW) -> Bool in // TODO: make temporary `Set`
                        impW.firstWord == storedW.firstWord
                    }
                })
                Storage.wordsAndStat.append(contentsOf: importedWords)
                Storage.saveWords(Storage.wordsAndStat.sorted(by: { $0.firstWord < $1.firstWord }))
            } else {
                // import one word
                importedWord = lemmas(from: importedString).first ?? importedString
                performSegue(withIdentifier: "AddWord", sender: self)
            }
            userDefaultsGroup.removeObject(forKey: "ImportedText")
        }
        navigationItem.rightBarButtonItems?.insert(editButtonItem, at: 0)
            //  print("$\(PRODUCT_BUNDLE_IDENTIFIER)")

        // For features avalible after iOS 11 In is coomented out because it is ugly
//        if ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)) {
//            navigationController?.navigationBar.prefersLargeTitles = true
//        }
        checkInstalledLocales()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        // Dynamic font ajustment when we are on screen (for table it is done in cellForRow) - CHECK
        let headlineFont = UIFont.preferredFont(forTextStyle: .headline)
        let titleAttributes = [NSAttributedString.Key.font: headlineFont]
        navigationController?.navigationBar.titleTextAttributes = titleAttributes
        // title = "LearnWords" //better do this in IB
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.reloadData() //beter do animated insertion or deletion here
        
        // NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        defaultsChanged()
        // Some checks:
//        print("LWUserDefaults.standard.languageToStudyPreference: " + (LWUserDefaults.standard.languageToStudyPreference ?? "Undefined"))
//        print("LWUserDefaults.standard.nativeLanguagePreference: " + (LWUserDefaults.standard.nativeLanguagePreference ?? "Undefined"))
//        print("UserDefaults.standard.string(forKey: 'languageToStudyPreference'): " + (UserDefaults.standard.string(forKey: "languageToStudyPreference") ?? "Undefined"))
//        print("UserDefaults.standard.string(forKey: 'nativeLanguagePreference'): " + (UserDefaults.standard.string(forKey: "nativeLanguagePreference") ?? "Undefined"))
        // tableView.reloadData() //inefficient
    }
    
    
    @objc func defaultsChanged(){
        // checkInstalledLocales()
        
        // TODO: more checks:
        // checkSpokenLanguages()
        // checkRecognizedLanguages()
//        if userDefaults.bool(forKey: "redThemeSwitch") {
//            self.view.backgroundColor = UIColor.red
//
//        }
//        else {
//            self.view.backgroundColor = UIColor.green
//        }
    }
    
    @IBAction func addNewWord(_ sender: UIBarButtonItem) {
        // create our alert controller
        let ac = UIAlertController(title: NSLocalizedString("Add new word", comment: "AlertController title"), message: nil, preferredStyle: .alert)
        
        // add two text fields, one for English and one for French
        ac.addTextField { textField in
            textField.placeholder = NSLocalizedString(LWUserDefaults.standard.languageToStudyPreference!, comment: "Foreing language")
        }
        
        ac.addTextField { (textField) in
            textField.placeholder = NSLocalizedString(LWUserDefaults.standard.nativeLanguagePreference!, comment: "Native language")
        }
        
        // create an "Add Word" button that submits the user's input
        let submitAction = UIAlertAction(title: NSLocalizedString("Add Word", comment: "AlertAction title"), style: .default) { [unowned self, ac] (action: UIAlertAction!) in
            // pull out the English and French words, or an empty string if there was a problem
            let firstWord = ac.textFields?[0].text ?? ""
            let secondWord = ac.textFields?[1].text ?? ""
            
            // submit the English and French word to the insertFlashcard() method
            if let indexOfInsertedRow = Storage.insertFlashcard(foreign: firstWord, native: secondWord) {
                //TODO: Check for duplicates and alphabetically sort
                let newIndexPath = IndexPath(row: indexOfInsertedRow, section: 0)
                self.tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
        }
        ac.addAction(submitAction)
        ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"), style: .cancel))
        present(ac, animated: true)
    }
    
//    @objc func startTest() {
//        guard let vc = storyboard?.instantiateViewController(withIdentifier: "WordTest") as? WordTestViewController else { return }
//        vc.wordsInTest = wordsAndStat
//        navigationController?.pushViewController(vc, animated: true)
//    }

    private func checkInstalledLocales() {
        /*if let languageListPreferences = userDefaultsGroup?.stringArray(forKey: "LanguageList")  {
            primaryLanguage = languageListPreferences[0]
            //secondaryLanguage = languageListPreferences[1]
        } else {
            userDefaultsGroup?.set(UITextInputMode.activeInputModes.compactMap{$0.primaryLanguage}.filter{!$0.contains("emoji")}, forKey: "LanguageList")
        } */
        let languageIDs = UITextInputMode.activeInputModes.compactMap{ $0.primaryLanguage }
        
        var checkResultsMessage :String?
        if let secondaryLanguage = LWUserDefaults.standard.languageToStudyPreference, !languageIDs.map({String($0.prefix(2))}).contains(String(secondaryLanguage.prefix(2))) {
            checkResultsMessage = String(format: NSLocalizedString("Keyboard for language to study (%@) is not installed now. ", comment: "Alert message, langID inside"), secondaryLanguage)
        }
        if let primaryLanguage = LWUserDefaults.standard.nativeLanguagePreference, !languageIDs.map({String($0.prefix(2))}).contains(String(primaryLanguage.prefix(2))) {
            checkResultsMessage = (checkResultsMessage ?? "") + String(format: NSLocalizedString("Keyboard for native learner's language (%@) is not installed now. ", comment: "Alert message, langID inside"), primaryLanguage)
        }
        checkResultsMessage?.append(NSLocalizedString("You may add Keyboards from system General Settings pane.", comment: ""))
        
        if checkResultsMessage != nil {
            // If user only has English and Emodsi they woun't be able to add translations
            let ac = UIAlertController(title: NSLocalizedString("Check installed languages", comment: "Alert title"),
                                       message: checkResultsMessage! + NSLocalizedString("Looks like you only have those keyboards:", comment: "Alert message, langID appended") + languageIDs.joined(separator: ", "),
                                       preferredStyle: .alert)
            
            // TODO: create a "Go to Settings" button that opens standart settings
            let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { /*[weak self]*/ (action: UIAlertAction!) in
                gotoAppSettings()
            }
            ac.addAction(settingsAction)
            ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"), style: .cancel))
            present(ac, animated: true)

        }
        
    }
    

    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return wordsInTable.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "Word", for: indexPath) as? WordTableViewCell else { return UITableViewCell() }
        
        let word = wordsInTable[indexPath.row]
        cell.leftTextLabel?.text = word.firstWord
        // cell.imageView?.image = UIImage(systemName: "\(word.known).square")
        cell.progressView.angle = (360.0 / Double(WordAndStat.maxKnownLevel)) * Double(word.known)
        cell.rightTextLabel?.text = word.secondWord
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if let cell = tableView.cellForRow(at: indexPath) as? WordTableViewCell {
            if cell.rightTextLabel?.text == "" {
                let word = wordsInTable[indexPath.row]
                cell.rightTextLabel?.text = word.secondWord
            } else {
                cell.rightTextLabel?.text = ""
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard !(searchController.isActive && searchController.searchBar.text != "") else {return}
        if editingStyle == .delete {
            //TODO: Move operating functions to model
            Storage.wordsAndStat.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            // TODO: Replace with saveCurrentWordSet
            Storage.saveWords(Storage.wordsAndStat)

        }
    }
    // MARK: SearchController for filtering WordTableView
    private func setupSearchController(placeholder: String = "", hideWhenAppear: Bool = true) { //Unify with searchViewControllers
        definesPresentationContext = true
        // searchController.dimsBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        // searchController.searchBar.barTintColor = UIColor(white: 0.9, alpha: 0.4)
        searchController.searchBar.placeholder = placeholder
        searchController.hidesNavigationBarDuringPresentation = false
        tableView.tableHeaderView = searchController.searchBar
        if hideWhenAppear {
            tableView.contentOffset = CGPoint(x: 0, y: searchController.searchBar.frame.height)
        }
    }
    
    func filterRows(for searchText: String) {
        filteredWords = Storage.wordsAndStat.filter{
            $0.firstWord.lowercased().contains(searchText.lowercased()) ||
                $0.secondWord.lowercased().contains(searchText.lowercased())
        }
        tableView.reloadData()
    }
    
    // MARK: UIStoryboardSegues
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
//        case "StartTest":
//            if let wordTestVC = segue.destination as? WordTestViewController {
//                wordTestVC.wordsInTest = Storage.wordsAndStat
//            }
        case "AddWord":
            if let searchWordVC = segue.destination as? SearchWordViewController, let languageToStudy = LWUserDefaults.standard.languageToStudyPreference {
                searchWordVC.searchedObject = .original(lang: languageToStudy, word: importedWord)
                searchWordVC.filterRowsForSearchedText(importedWord)
                searchWordVC.navigationItem.backButtonTitle = NSLocalizedString("Word", comment: "backButtonTitle")
            }
            // TODO: with standart row features
//        case: "EditWord"
//        case: "MoveWordToSet"
        default:
            break
        }
    }

    
    func updateSearchResults(for searchController: UISearchController) {
        if let term = searchController.searchBar.text {
            filterRows(for: term)
        }
    }
    

    
    func lemmas(from str: String) -> [String] {
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType, .lemma], options: 0)
        let options: NSLinguisticTagger.Options = [.omitPunctuation, .omitWhitespace]
        let range = NSRange(location: 0, length: str.utf16.count)
        tagger.string = str
        var l = [String]()
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, options: options) { tag, _, _ in
            if let lemma = tag?.rawValue {
                l.append(lemma)
            }
        }
        return l
    }

}


