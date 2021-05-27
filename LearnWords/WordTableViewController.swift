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

import UIKit

final class WordTableViewController: UITableViewController, UISearchResultsUpdating {
    
    // MARK: searchController variables
    var filteredWords = [WordAndStat]() //? move to model?
    var wordsInTable : [WordAndStat] { // A subset of word pairs to display in tableView
        return (searchController.isActive && searchController.searchBar.text != "") ? filteredWords : Storage.wordsAndStat
    }

    let searchController = UISearchController(searchResultsController: nil)

    @IBAction func goToSettings(_ sender: UIBarButtonItem) {
        gotoAppSettings()
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        //Some tests to discover various language tests found in system:
        print("Bundle.main.preferredLocalizations \n", Bundle.main.preferredLocalizations)
        print("UITextChecker.availableLanguages \n", UITextChecker.availableLanguages)
        print("UITextInputMode.activeInputModes.map{$0.primaryLanguage...} \n", UITextInputMode.activeInputModes.map{$0.primaryLanguage ?? "primaryLanguage undefined"})
        print("Bundle.main.bundleIdentifier \n", Bundle.main.bundleIdentifier ?? "")
        
        //Some tests for user defaults

        print("UserDefaults.standard.double(forKey: pitchMultiplierPreference) = " + String(UserDefaults.standard.double(forKey: "pitchMultiplierPreference")))
        print("UserDefaults.standard.double(forKey: utteranceRatePreference) = " + String(UserDefaults.standard.double(forKey: "utteranceRatePreference")))
        print("userDefaultsGroup.double(forKey: pitchMultiplierPreference) = " + String(userDefaultsGroup.double(forKey: "pitchMultiplierPreference") ?? 99))
        print("userDefaultsGroup.double(forKey: utteranceRatePreference) = " + String(userDefaultsGroup.double(forKey: "utteranceRatePreference") ?? 99))
        
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
        //navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addNewWord))
        //let startButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(startTest))
        //let autoPlayButton = UIBarButtonItem(barButtonSystemItem: .reply, target: self, action: #selector(autoPlayTest))
        //navigationItem.rightBarButtonItems = [startButton, autoPlayButton]
        //navigationItem.backBarButtonItem = UIBarButtonItem(title: "End Test", style: .plain, target: nil, action: nil)
        //This doesn't work for some reason
        //navigationItem.backBarButtonItem?.title = "End Test"
        //navigationItem.backBarButtonItem?.style = .plain

        setupSearchController(placeholder: NSLocalizedString("Search words in sets", comment: "placeholder"), hideWhenAppear: true)

        if let savedWords = userDefaultsGroup.stringArray(forKey: "Words")  {
                Storage.wordsAndStat = (savedWords.compactMap{($0,0,0,0)} )
            } else {
                Storage.saveInitialValues()
            }
        
/*            if let savedWords = defaults.object(forKey: "knownWords") as? [String] {
                knownWords = savedWords
            }*/

            //  print("$\(PRODUCT_BUNDLE_IDENTIFIER)")

        // For features avalible after iOS 11 In is coomented out because it is ugly
//        if ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)) {
//            navigationController?.navigationBar.prefersLargeTitles = true
//        }
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
        checkInstalledLocales()
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        defaultsChanged()
        // Some checks:
        print("LWUserDefaults.standard.languageToStudyPreference: " + (LWUserDefaults.standard.languageToStudyPreference ?? "Undefined"))
        print("LWUserDefaults.standard.nativeLanguagePreference: " + (LWUserDefaults.standard.nativeLanguagePreference ?? "Undefined"))
        tableView.reloadData() //inefficient
    }
    
    
    @objc func defaultsChanged(){
        if UserDefaults.standard.bool(forKey: "redThemeSwitch") {
            self.view.backgroundColor = UIColor.red
            
        }
        else {
            self.view.backgroundColor = UIColor.green
        }
    }
    
    @IBAction func addNewWord(_ sender: UIBarButtonItem) {
        // create our alert controller
        let ac = UIAlertController(title: NSLocalizedString("Add new word", comment: "AlertController title"), message: nil, preferredStyle: .alert)
        
        // add two text fields, one for English and one for French
        ac.addTextField { textField in
            textField.placeholder = NSLocalizedString("Russian", comment: "Russian language")
        }
        
        ac.addTextField { (textField) in
            textField.placeholder = NSLocalizedString("English", comment: "English language")
        }
        
        // create an "Add Word" button that submits the user's input
        let submitAction = UIAlertAction(title: NSLocalizedString("Add Word", comment: "AlertAction title"), style: .default) { [unowned self, ac] (action: UIAlertAction!) in
            // pull out the English and French words, or an empty string if there was a problem
            let firstWord = ac.textFields?[0].text ?? ""
            let secondWord = ac.textFields?[1].text ?? ""
            
            // submit the English and French word to the insertFlashcard() method
            if let indexOfInsertedRow = Storage.insertFlashcard(first: firstWord, second: secondWord) {
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
    
    @IBAction func autoPlayTest(_ sender: UIBarButtonItem) {
        navigationItem.rightBarButtonItems?[1].isEnabled = !(navigationItem.rightBarButtonItems?[1].isEnabled)!
    }

    private func checkInstalledLocales() {
        /*if let languageListPreferences = userDefaultsGroup?.stringArray(forKey: "LanguageList")  {
            primaryLanguage = languageListPreferences[0]
            //secondaryLanguage = languageListPreferences[1]
        } else {
            userDefaultsGroup?.set(UITextInputMode.activeInputModes.compactMap{$0.primaryLanguage}.filter{!$0.contains("emoji")}, forKey: "LanguageList")
        } */
        let languageIDs = UITextInputMode.activeInputModes.compactMap{ $0.primaryLanguage }
        
        var checkResultsMessage :String?
        if let secondaryLanguage = LWUserDefaults.standard.languageToStudyPreference, !languageIDs.contains(secondaryLanguage) {
            checkResultsMessage = NSLocalizedString("Keyboard for language to study (\(secondaryLanguage)) is not installed now. ", comment: "Alert message, langID inside")
        }
        if let primaryLanguage = LWUserDefaults.standard.nativeLanguagePreference, !languageIDs.contains(primaryLanguage) {
            checkResultsMessage = (checkResultsMessage ?? "") + NSLocalizedString("Keyboard for native learner's language (\(primaryLanguage)) is not installed now. ", comment: "Alert message, langID inside")
        }
        checkResultsMessage?.append(NSLocalizedString("You may add Keyboards from system General Settings pane.", comment: ""))
        
        if checkResultsMessage != nil {
            // If user only has English and Emodsi they woun't be able to add translations
            let ac = UIAlertController(title: NSLocalizedString("Check installed languages", comment: "Alert title"),
                                       message: checkResultsMessage! + NSLocalizedString("Looks like you only have those keyboards:", comment: "Alert message, langID appended") + languageIDs.joined(separator: ", "),
                                       preferredStyle: .alert)
            
            // create a "Go to Settings" button that opens standart settings
            let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { [weak self] (action: UIAlertAction!) in
                self?.gotoAppSettings()
            }
            ac.addAction(settingsAction)
            ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"), style: .cancel))
            present(ac, animated: true)

        }
        
    }
    
    private func gotoAppSettings() {
        let url = URL(string: UIApplication.openSettingsURLString) //+ "root=General&path=Network"
        if url != nil, UIApplication.shared.canOpenURL(url!) {UIApplication.shared.open(url!) }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return wordsInTable.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Word", for: indexPath)
        
        let word = wordsInTable[indexPath.row]
        let split = word.pair.components(separatedBy: "::")

        cell.textLabel?.text = split[0]
        cell.detailTextLabel?.text = ""
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if let cell = tableView.cellForRow(at: indexPath) {
            if cell.detailTextLabel?.text == "" {
                let word = wordsInTable[indexPath.row]

                let split = word.pair.components(separatedBy: "::")
                cell.detailTextLabel?.text = split[1]
            } else {
                cell.detailTextLabel?.text = ""
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
            Storage.saveWordsOnly(Storage.wordsAndStat)

        }
    }
    // MARK: SearchController for filtering WordTableView
    private func setupSearchController(placeholder: String = "", hideWhenAppear: Bool = true) { //Unify with searchViewControllers
        definesPresentationContext = true
        searchController.dimsBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.barTintColor = UIColor(white: 0.9, alpha: 0.9)
        searchController.searchBar.placeholder = placeholder
        searchController.hidesNavigationBarDuringPresentation = false
        tableView.tableHeaderView = searchController.searchBar
        if hideWhenAppear {
            tableView.contentOffset = CGPoint(x: 0, y: searchController.searchBar.frame.height)
        }
    }
    
    func filterRows(for searchText: String) {
        filteredWords = Storage.wordsAndStat.filter{$0.pair.lowercased().contains(searchText.lowercased())}
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
                searchWordVC.searchedObject = .original(lang: languageToStudy, word: "")
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

}
