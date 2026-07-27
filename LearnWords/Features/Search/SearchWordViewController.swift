//
//  SearchViewController.swift
//  Compact Swift Dictionary
//
//  Created by Paul on 11.11.2018.
//  Copyright © 2018 Laconic. All rights reserved.
//
// TODO: Limit search term to one word at least for suggestions, maybe visually
// This is solved in TableSearch example from Apple
// TODO: Add tableView Animation
// TODO: Introduce constants for languages (hint: use system ones)

import UIKit

//class LocalizedUISearchController: UISearchController{
//
//    override var textInputMode: UITextInputMode?{
//        for inputMode in UITextInputMode.activeInputModes{
//            print("inputMode.primaryLanguage: \(inputMode.primaryLanguage ?? "Undefined")")
//            if (inputMode.primaryLanguage?.hasPrefix("ru"))! {
//                return inputMode
//            }
//        }
//        return super.textInputMode
//    }
//}
//
//class UILocalizedSearchController: UISearchController{
//    private var _textInputMode: UITextInputMode?
//    // or
//    var forcedPrimaryLanguage = LWUserDefaults.standard.languageToStudyPreference { //or computed var
//        didSet {
//            debugPrint("forcedPrimaryLanguage", forcedPrimaryLanguage ?? "Undefined")
//            for inputMode in UITextInputMode.activeInputModes{
//                if (inputMode.primaryLanguage?.hasPrefix(forcedPrimaryLanguage ?? "")) ?? false {
//                    _textInputMode = inputMode
//                    break
//                }
//// TODO: correct the logic
////              _textInputMode = nil //reset if Language is not found
////              forcedPrimaryLanguage = oldValue or UITextInputMode.activeInputModes.first?.primaryLanguage
//            }
//        }
//    }
//
//    func setTextInputModePrimaryLanguage(by prefix: String) {
//        forcedPrimaryLanguage = prefix
//    }
//    override var textInputMode: UITextInputMode?
//        {
//        get { //prioty 1 if is set
//            if let definedTextInputMode = _textInputMode {
//                return definedTextInputMode
//            } // fallback to default if not manually set by var o funk
//            return super.textInputMode
//        }
//        set {
//            _textInputMode = newValue
//        }
//    }
//
//    override var canBecomeFirstResponder: Bool {
//        return true
//    }
//
//}

class LWLocalizedSearchBar: UISearchBar {
    private var _textInputMode: UITextInputMode?
    // or
    var forcedPrimaryLanguage = LWUserDefaults.standard.languageToStudyPreference { //or computed var
        didSet {
            for inputMode in UITextInputMode.activeInputModes{
                if (inputMode.primaryLanguage?.hasPrefix(forcedPrimaryLanguage ?? "")) ?? false {
                    _textInputMode = inputMode
                    break
                }
// TODO: correct the logic
//              _textInputMode = nil //reset if Language is not found
//              forcedPrimaryLanguage = oldValue or UITextInputMode.activeInputModes.first?.primaryLanguage
            }
        }
    }

    func setTextInputModePrimaryLanguage(by prefix: String) {
        forcedPrimaryLanguage = prefix
    }
    override var textInputMode: UITextInputMode?
        {
        get { //prioty 1 if is set
            if let definedTextInputMode = _textInputMode {
                return definedTextInputMode
            } // fallback to default if not manually set by var o funk
            return super.textInputMode
        }
        set {
            _textInputMode = newValue
        }
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

}


class SearchWordViewController: UITableViewController, UISearchBarDelegate {
    
    // Create standard defaults
    // TODO: Check this: looks like it is never called
//    static func registerDefaults() {
//        UserDefaults.standard.register(defaults: [:])
//    }
    // API:
    enum SearchedObject {
        case original(lang: String, word: String)
        case translation(orig_lang: String, orig_word: String, dest_lang: String, translations: [String])
    }
    var searchedObject = SearchedObject.original(lang: LWUserDefaults.standard.languageToStudyPreference ?? "en", word: "") {
            didSet {
                switch searchedObject {
                case .original(lang: _, word: let word):
                    //searchLanguage = lang
                    searchBar.text = word
                    tableView.allowsMultipleSelection = false
                case .translation(orig_lang: _, orig_word: _, dest_lang: _, translations: _):
                    tableView.allowsMultipleSelection = true
                    //searchLanguage = lang
                }
            }
        }
    
    
    //UITextInputMode.activeInputModes.compactMap{$0.primaryLanguage}
    
    // Keep an instance of UITextChecker for getting suggested words from word fragments.
    // This is the autocorrect word list, not the actual dictionary list, so it will return some words without definitions.
    private let textChecker = UITextChecker() // Use global?
    private var suggestions = [String]()
    var searchLanguage: String { get { //TODO: move to searchedObject.didSet?
        switch searchedObject {
        case .original(lang: let lang, word: _):
            return lang
        case .translation(orig_lang: _, orig_word: _, dest_lang: let lang, translations: _):
            return lang
        }
        }
    }
    
    private var kRecentSearchesKey: String { return "RecentSearchesFor_" + searchLanguage }
    //private var kLastSearchKey: String { return "LastSearchFor_" + searchLanguage }
    private lazy var recentSearches: [String] = (userDefaultsGroup.stringArray(forKey: kRecentSearchesKey)) ?? []
    
//    let themeTint = UIColor.orange // UIColor(white: 0.9, alpha: 0.9)
    
//    lazy var searchController: UILocalizedSearchController = {
//        let  sc = UILocalizedSearchController(searchResultsController: nil)
//        sc.forcedPrimaryLanguage = searchLanguage
//        return sc
//    }()
    
    lazy var searchBar: LWLocalizedSearchBar = {
        let  sb = LWLocalizedSearchBar()
        sb.searchBarStyle = .prominent
        sb.showsSearchResultsButton = true //TODO : in future
        // sb.keyboardType = .alphabet //this limits to English alphabet only
        sb.autocapitalizationType = .none
        // sb.showsBookmarkButton = true
        switch searchedObject {
        case .original:
            sb.returnKeyType = .continue
        case .translation:
            sb.returnKeyType = .done
        }
        sb.returnKeyType = .next
        sb.forcedPrimaryLanguage = searchLanguage
        sb.sizeToFit()
        return sb
    }()
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //setupSearchController()
        // tableView.keyboardDismissMode = .onDrag
        
        /* switch searchedObject {
        case .translation(orig_lang: _, orig_word: _, dest_lang: _, translations: _):
            //language = d_lang
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(AddWordOrDefinition))
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(AddWordOrDefinition))
            navigationItem.rightBarButtonItems = [cancelButton, doneButton]
        case.original(_, _):
            //language = o_lang
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(AddWordOrDefinition))
        } */
        // searchController.becomeFirstResponder // display the keyboard right away

        // Search bar setup.Move to didAppear?
        searchBar.delegate = self;
        searchBar.searchBarStyle = .prominent // use the prominent style to get a white background
        searchBar.autocapitalizationType = .none
        // searchBar.prompt = "Foreign word"
        searchBar.placeholder = NSLocalizedString("Start typing", comment: "placeholder in a searchbar")
        //navigationItem.titleView = searchBar
        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
        tableView.rowHeight = UITableView.automaticDimension
        //navigationItem.titleView = searchBar
    }
    
    @objc func AddWordOrDefinition() {
        switch searchedObject { //Add emoji flags
        case .original:
            break
        case .translation(orig_lang: _, orig_word: _, dest_lang: _, translations: _): break
            // TODO: make an opportunity to select words - move them to defifnitions section
//            for indexPath in tableView?.indexPathsForSelectedRows ?? [] {
//                if let stc = tableView.cellForRow(at: indexPath), let translation = stc.textLabel?.text {
//                translations += [translation]
//            }
//        }

        // take care to refresh words table?
        // insertFlashcard(first: translations[0], second: prompt)

    }
        searchBarSearchButtonClicked(searchBar)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
       // searchBar.setNeedsFocusUpdate()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: Table DataSource Protocol
    
    //------------------------------------------------------------------------------
    // Vend a cell and set the suggestion or recent term text
    //------------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WordCell", for: indexPath)
        switch (searchedObject, indexPath.section) {
        case (.original, 0):
            if let searchText = searchBar.text, !searchText.isEmpty {
                //TODO: move to function that outputs NSAttributedString
                let suggestion = suggestions[indexPath.row]
                if let searchTextRangeInSuggestion = suggestion.range(of: searchText) {
                    let searchTextNSRangeInSuggestion = NSRange(searchTextRangeInSuggestion, in: suggestion)
                    let suggestionWithAttributes = NSMutableAttributedString(string: suggestion)
                    if #available(iOS 13.0, *) {
                        suggestionWithAttributes.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: searchTextNSRangeInSuggestion)
                    } else {
                        // Fallback on earlier versions
                        suggestionWithAttributes.addAttribute(.foregroundColor, value:UIColor(red: 0, green: 0.1, blue: 0.7, alpha: 1), range: searchTextNSRangeInSuggestion)
                    }
                    cell.textLabel?.attributedText = suggestionWithAttributes
                } else {
                    cell.textLabel?.text = suggestion
                }
//                DispatchQueue.global(qos: .userInitiated).async {
//                    cell.detailTextLabel?.text = definition(for: suggestion)
//                }
// Could not use it without swift UI
//                if #available(iOS 18.0, *) {
//                    TranslationViewModel.shared.translate(text: suggestion, using: ???)
//                }
            } else {
                cell.textLabel?.text = recentSearches[indexPath.row]
            }
        case (.translation(let lang, let word, _, _), 0):
            cell.textLabel?.text = word
            cell.detailTextLabel?.text = lang
        case (.translation, 1):
            if let searchText = searchBar.text, !searchText.isEmpty {
                if suggestions.indices.contains(indexPath.row) { //Check why this may happen
                    //Shorter and better than in previous case
                    let suggestion = suggestions[indexPath.row]
                    if let searchTextNSRangeInSuggestion = suggestion.nsRange(of: searchText) {
                        let suggestionWithAttributes = NSMutableAttributedString(string: suggestion)
                        if #available(iOS 13.0, *) {
                            suggestionWithAttributes.addAttribute(.foregroundColor, value: UIColor.systemIndigo, range: searchTextNSRangeInSuggestion)
                        } else {
                            suggestionWithAttributes.addAttribute(.foregroundColor, value: UIColor(red: 0, green: 0.1, blue: 0.7, alpha: 1), range: searchTextNSRangeInSuggestion)
                        }
                        cell.textLabel?.attributedText = suggestionWithAttributes
                    } else {
                        cell.textLabel?.text = suggestions[indexPath.row]
                    }
                }
            } else {
                cell.textLabel?.text = recentSearches[indexPath.row]
            }
        default:
            break
        }
        
        return cell
    }

    //------------------------------------------------------------------------------
    // Enough rows to show the suggestions
    //------------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        //    if (searchText && searchText.length > 0)    // if the search bar has some text in it
        switch searchedObject {
        case .original:
            if searchBar.text != "" { // searchBar.isFocused &&
                return suggestions.count;        // show suggestions
            } else {
                return recentSearches.count;
            }
        case .translation:
            switch section {
            case 0:
                return 1
            case 1:
                if  searchBar.text != "" { //searchBar.isFocused &&
                    return suggestions.count;        // show suggestions
                } else {
                    return recentSearches.count;
                }
            default:
                return 3
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        switch searchedObject {
        case .original:
            return 1
        case .translation:
            return 2
        }
        
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch searchedObject { //Add emoji flags
        case .original(lang: let originalLanguage, word: _):
            return NSLocalizedString("Word in ", comment: "Language") + Locale.current.localizedString(forLanguageCode: originalLanguage)!.capitalized
        case .translation(orig_lang: let originalLanguage, orig_word: _, dest_lang: let translationLanguage, translations: _):
            switch section {
            case 0:
                return NSLocalizedString("Word in ", comment: "Language") + Locale.current.localizedString(forLanguageCode: originalLanguage)!.capitalized
            case 1:
                return NSLocalizedString("Meaning in ", comment: "Meaing in native lang") + Locale.current.localizedString(forLanguageCode: translationLanguage)!.capitalized
            default:
                return ""
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        46.0
    }
    
    /// Tapping a suggestion commits it — the same thing the keyboard's Return key does.
    ///
    /// Until this existed, tapping a row did **nothing at all**: the only way to add a
    /// word was to finish typing and press Return, while the obvious gesture — tap the
    /// word you were looking for — silently did nothing and made sync look broken.
    /// The accessory button is a dictionary lookup, not a commit, which made it worse.
    ///
    /// Routed through `searchBarSearchButtonClicked` rather than duplicating the segue
    /// logic, so the two entry points cannot drift: the choice between "Add Translation"
    /// and "Add Word Pair" is made in exactly one place.
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let picked = tableView.cellForRow(at: indexPath)?.textLabel?.text,
              !picked.isEmpty else { return }
        searchBar.text = picked
        searchBar.resignFirstResponder()
        searchBarSearchButtonClicked(searchBar)
    }

    override func tableView(_ tableView: UITableView , accessoryButtonTappedForRowWith: IndexPath) {
        lookUp(term: tableView.cellForRow(at: accessoryButtonTappedForRowWith)?.textLabel?.text ?? "", sender: self)
    }
    
//    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
//        Implement this
//    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if let term = searchBar.text {
            filterRowsForSearchedText(term)
        }
    }
    
//    func setupSearchController() {
//        /** Search presents a view controller by applying normal view controller presentation semantics.
//         This means that the presentation moves up the view controller hierarchy until it finds the root
//         view controller or one that defines a presentation context.
//         */
//
//        /** Specify that this view controller determines how the search controller is presented.
//         The search controller should be presented modally and match the physical size of this view controller.
//         */
//
//        definesPresentationContext = true
//        debugPrint(#function, " - ", searchLanguage)
//        //searchController.setTextInputModePrimaryLanguage(by: searchLanguage)
//        searchController.searchResultsUpdater = self
//        // searchController.searchBar.barTintColor = themeTint
//        searchController.searchBar.placeholder = NSLocalizedString("New word", comment: "placeholder for adding new word to vocabulary")
//        searchController.hidesNavigationBarDuringPresentation = false
//        searchController.searchBar.searchBarStyle = .prominent // use the prominent style to get a white background
//        searchController.searchBar.autocapitalizationType = .none;
//
//        // Idea from official Apple sample:
//        // https://developer.apple.com/documentation/uikit/view_controllers/displaying_searchable_content_by_using_a_search_controller
//        if #available(iOS 13.0, *) {
//            // For iOS 11 and later, place the search bar in the navigation bar.
//            navigationItem.searchController = searchController
//
//            // Make the search bar always visible.
//            navigationItem.hidesSearchBarWhenScrolling = false
//        } else {
//            // For iOS 10 and earlier, place the search controller's search bar in the table view's header.
//            tableView.tableHeaderView = searchController.searchBar
//        }
//
//        //searchController.delegate = self
//        searchController.dimsBackgroundDuringPresentation = false // The default is true.
//        searchController.searchBar.delegate = self // Monitor when the search button is tapped.
//        // Ideas from Compact Dictionary
//        // Another thing that should work from iOS 9 to 12 is:
//        //navigationItem.titleView = searchController.searchBar
//        // but this needs checking. Besides we will loose NavigationBar.title if use this.
//        searchController.searchBar.becomeFirstResponder // display the keyboard right away
//    }
//
  
    //------------------------------------------------------------------------------
    // As each new character is typed in the search bar, get new suggestions
    // In english, skip over suggestions that end in ' or 's (those come up often
    // but never have definitions)
    //------------------------------------------------------------------------------
    func filterRowsForSearchedText(_ searchText: String) {
        let unfilteredSuggestions = textChecker.completions(forPartialWordRange: searchText.fullNSRange(), in: searchText, language: searchLanguage ) ?? []
        // TODO: - Why not? Try add guesses as contjoin. Limit additional work to powerful devices only
//        let guesses = Set(textChecker.guesses(forWordRange: searchText.fullNSRange(), in: searchText, language: searchLanguage ) ?? [])
//        unfilteredSuggestions.append(contentsOf: guesses.subtracting(unfilteredSuggestions))
        //can play with animation here later
        if searchLanguage.hasPrefix("en") { // for english only: if the word does not end in ' or 's
            // use the filtered list of suggested words for English
            // TODO: - use lema instead
            suggestions = unfilteredSuggestions.filter{!($0.hasSuffix("'") || $0.hasSuffix("'s"))}
        } else { // for all languages except English
            suggestions = unfilteredSuggestions
        }
        tableView.reloadData()
    }
    // MARK: - UISearchBarDelegate
    //------------------------------------------------------------------------------
    // This is called when the user touches the Search button on the Keyboard
    //------------------------------------------------------------------------------
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        if let term = searchBar.text {
            // addToRecentSearches(term)
            // TODO: check for term to exist
//            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
//
//            } else {
//                // TODO: put up a faiding alert : Unknown word. Are you sure you typed it right?
//            }
            switch searchedObject {
            case .original(lang: let lang, word: _):
                searchedObject = .original(lang: lang, word: term)
                performSegue(withIdentifier: "Add Translation", sender: searchBar)
            case .translation(orig_lang: let ol, orig_word: let ow, dest_lang: let dl, translations: let tls):
                searchedObject = .translation(orig_lang: ol, orig_word: ow, dest_lang: dl, translations: (tls + [term]))
                performSegue(withIdentifier: "Add Word Pair", sender: searchBar)
            }

            //presentReferenceViewControllerWithTerm(term)
        }
        //presentingViewController?.dismiss(animated: true)
    }
    
//    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
//        searchBar.inputView?.inputViewController?.primaryLanguage = "ru"
//        return true
//    }
    

    //------------------------------------------------------------------------------
    // When the user moves the table, get the keyboard out of the way
    //------------------------------------------------------------------------------
    //TODO: Check if weed it (maybe use tableView.keyboardDismissMode = .onDrag or in Storyboard)
//    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
//        searchController.searchBar.resignFirstResponder
//        resignFirstResponder
//        debugPrint(#function)
//    }
    //------------------------------------------------------------------------------
    // not used for now
    //------------------------------------------------------------------------------
    //-(void)clearRecentSearches
    //{
    //    [self.recentSearches removeAllObjects];
    //    [[NSUserDefaults standardUserDefaults] setObject:self.recentSearches forKey:kRecentSearchesKey];
    //}
    
    
    //------------------------------------------------------------------------------
    // Add the search term to our list of recent searches, dealing with duplicates
    // and keeping the list trimmed to 10
    //------------------------------------------------------------------------------
//    private func addToRecentSearches(_ aSearch: String)
//    {
//        let foundIndex = recentSearches.firstIndex(of: aSearch)
//        if  foundIndex == nil {
//            // not already in recents, add it
//            recentSearches.insert(aSearch, at: 0)
//        }
//        else {
//            // move found object to index 0
//            let object = recentSearches[foundIndex!]
//            recentSearches.remove(at: foundIndex!)
//            recentSearches.insert(object, at: 0)
//        }
//
//        // trim recent searches if over 10
//        if recentSearches.count > 10 {
//            recentSearches.removeLast()
//        }
//        userDefaultsGroup.set(recentSearches, forKey: kRecentSearchesKey)
//
//    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

        if segue.identifier == "Add Translation" { //, searchedObject = .original(lang: termLanguage, word: termToDefine) - underused word
            
            if let wordSearchVC = segue.destination as? SearchWordViewController,
                let languageToStudy = LWUserDefaults.standard.languageToStudyPreference,
                let nativeLanguage = LWUserDefaults.standard.nativeLanguagePreference {
                //wordSearchVC.language = "ru" //Bundle.main.preferredLocalizations[1]
                let termToDefine: String // use searchedObject = .original(lang: termLanguage instead
                if let cell = (sender as? UITableViewCell) {
                    termToDefine = cell.textLabel?.text ?? "?"
                } else if let sb = (sender as? UISearchBar) {
                    termToDefine = sb.text ?? "?"
                } else { termToDefine = "?" }
                wordSearchVC.searchedObject = .translation(
                    orig_lang: languageToStudy,
                    orig_word: termToDefine,
                    dest_lang: nativeLanguage,
                    translations: [])
            }
        } else if segue.identifier == "Add Word Pair" {
            var term: String = ""
            if let cell = (sender as? UITableViewCell) {
                term = cell.textLabel?.text ?? "?"
            } else if let sb = (sender as? UISearchBar) {
                if sb.text == nil { return }
                term = sb.text!
            }
                
                switch searchedObject {
                case .original(lang: _, word: _):
                    return
                case .translation(orig_lang: let ol, orig_word: let ow, dest_lang: let dl, translations: let tls):
                    searchedObject = .translation(orig_lang: ol, orig_word: ow, dest_lang: dl, translations: (tls + [term]))
                    addWord(ow, in: ol, meaning: term, in: dl)
            }
            // if let wordTest = segue.destination as? WordTestViewController {
                // Do someting to scroll to new word definition and flash-highlight it
            // }
        
    }
    }

    

    // MARK: - Adding to the lexicon

    /// Stores the word and its translation as one meaning in the selected set.
    ///
    /// Both languages come from the search itself, not from settings, so looking up a
    /// German word files it as German. `Lexicon.addSense` links an existing word rather
    /// than making a twin, which is how a word looked up twice stays one row (TD-18).
    private func addWord(_ word: String, in wordLanguage: String,
                         meaning: String, in meaningLanguage: String) {
        let library = Library.shared
        guard let set = library.selectedSet else {
            // Reachable: every set deleted, or the selection pointing at one another
            // device removed. Silence here reads as "the app lost my word".
            debugLog("No word set selected — \(word)/\(meaning) was not added.")
            return
        }
        do {
            try library.lexicon.addSense(to: set.id,
                                         terms: [Term.Draft(word, in: wordLanguage),
                                                 Term.Draft(meaning, in: meaningLanguage)])
            debugLog("Added \(word) [\(wordLanguage)] / \(meaning) [\(meaningLanguage)] to \(set.name).")
        } catch {
            debugLog("Could not add \(word): \(error)")
        }
    }

}

//extension SearchWordViewController: UISearchResultsUpdating {
//    func updateSearchResults(for searchController: UISearchController) {
//        if let term = searchController.searchBar.text {
//            filterRowsForSearchedText(term)
//        }
//    }
//}
