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
            debugPrint("forcedPrimaryLanguage", forcedPrimaryLanguage ?? "Undefined")
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
                case .original(lang: let lang, word: _):
                    //searchLanguage = lang
                    tableView.allowsMultipleSelection = false
                case .translation(orig_lang: _, orig_word: _, dest_lang: let lang, translations: _):
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
            debugPrint(#function, " - ", lang)
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
        searchBar.placeholder = "start typing"
        //navigationItem.titleView = searchBar
        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
        //navigationItem.titleView = searchBar
    }
    
    @objc func AddWordOrDefinition() {
        debugPrint(#function)
        switch searchedObject { //Add emoji flags
        case .original:
            break
        case .translation(orig_lang: _, orig_word: let foreignWord, dest_lang: _, translations: _): break
            // TODO: make an opportunity to select words - move them to defifnitions section
//            for indexPath in tableView?.indexPathsForSelectedRows ?? [] {
//                if let stc = tableView.cellForRow(at: indexPath), let translation = stc.textLabel?.text {
//                translations += [translation]
//            }
//        }

        // take care to refresh words table?
        // insertFlashcard(first: translations[0], second: foreignWord)

    }
        searchBarSearchButtonClicked(searchBar)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
       // searchBar.setNeedsFocusUpdate()
    }
    
    //------------------------------------------------------------------------------
    // Present a UIReferenceLibraryViewController showing a definition.
    // Variations for regular and compact size class environments
    //------------------------------------------------------------------------------
    private func presentReferenceViewControllerWithTerm(_ term: String) {

        debugPrint(#function)
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
                    suggestionWithAttributes.addAttribute(.foregroundColor, value: UIColor(red: 0, green: 0.1, blue: 0.7, alpha: 1), range: searchTextNSRangeInSuggestion)
                    cell.textLabel?.attributedText = suggestionWithAttributes
                } else {
                    cell.textLabel?.text = suggestion
                }
                
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
                        suggestionWithAttributes.addAttribute(.foregroundColor, value: UIColor(red: 0, green: 0.1, blue: 0.7, alpha: 1), range: searchTextNSRangeInSuggestion)
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
            return NSLocalizedString("Original ", comment: "") + originalLanguage
        case .translation(orig_lang: let originalLanguage, orig_word: _, dest_lang: let translationLanguage, translations: _):
            switch section {
            case 0:
                return NSLocalizedString("Original ", comment: "") + originalLanguage
            case 1:
                return NSLocalizedString("Translation ", comment: "") + translationLanguage
            default:
                return ""
            }
        }
    }
    
    
//    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
//        Implement this
//    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if let term = searchBar.text {
            filterRowsForSearchedText(term)
        }
        debugPrint(#function)
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
        //let guesses = textChecker.guesses(forWordRange: searchText.fullRange(), in: searchText, language: language ) ?? []
        //unfilteredSuggestions.append(contentsOf: guesses)
        //can play with animation here later
        if searchLanguage.hasPrefix("en") { // for english only: if the word does not end in ' or 's
            // use the filtered list of suggested words for English
            suggestions = unfilteredSuggestions.filter{!($0.hasSuffix("'") || $0.hasSuffix("'s"))}
        } else { // for all languages except English
            suggestions = unfilteredSuggestions
        }
        debugPrint(suggestions)
        debugPrint("searchText ",(searchText as NSString).substring(with: searchText.fullNSRange()), " ", NSStringFromRange(searchText.fullNSRange()))
        
        tableView.reloadData()
    }
    // MARK: - UISearchBarDelegate
    //------------------------------------------------------------------------------
    // This is called when the user touches the Search button on the Keyboard
    //------------------------------------------------------------------------------
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        debugPrint(#function)
        if let term = searchBar.text {
            addToRecentSearches(term)
            // check for term to exist
            if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {

            } else {
                // put up a faiding alert : Unknown word. Are you sure you typed it right?
            }
            switch searchedObject {
            case .original(lang: let lang, word: _):
                searchedObject = .original(lang: lang, word: term)
                performSegue(withIdentifier: "Add Translation", sender: searchBar)
            case .translation(orig_lang: let ol, orig_word: let ow, dest_lang: let dl, translations: let tls):
                searchedObject = .translation(orig_lang: ol, orig_word: ow, dest_lang: dl, translations: (tls + [term]))
                //check duplicates
                //TODO: deal with array of terms, store languages, init as unlearned
                _ = Storage.insertFlashcard(first: term, second: ow)
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
    private func addToRecentSearches(_ aSearch: String)
    {
        let foundIndex = recentSearches.firstIndex(of: aSearch)
        if  foundIndex == nil {
            // not already in recents, add it
            recentSearches.insert(aSearch, at: 0)
        }
        else {
            // move found object to index 0
            let object = recentSearches[foundIndex!]
            recentSearches.remove(at: foundIndex!)
            recentSearches.insert(object, at: 0)
        }
        
        // trim recent searches if over 10
        if recentSearches.count > 10 {
            recentSearches.removeLast()
        }
        userDefaultsGroup.set(recentSearches, forKey: kRecentSearchesKey)

    }
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

            if let wordTest = segue.destination as? WordTestViewController {
                // Do someting to scroll to new word definition and flash-highlight it
            }
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
// TODO: Those are ugly
extension String {
    /// Not a totally correct
    func fullRange1() -> NSRange {
        return NSMakeRange(0, self.count)
    }
    /* Deprecated
    func fullNSRange() -> NSRange {
        return NSRange(self.startIndex.encodedOffset ..< self.endIndex.encodedOffset)
    } */
}

extension String {
    func fullRange2() -> Range<String.Index> {
        return Range(uncheckedBounds: (lower: self.startIndex, upper: self.endIndex))
    }
    func fullNSRange() -> NSRange {
        return NSRange(self) ?? NSRange(location: 0, length: 0)
    }

    /* Deprecated
    func fullRange7() -> NSRange {
        return NSRange(self.startIndex.encodedOffset ..< self.endIndex.encodedOffset)
    } */
    func nsRange(of substring: String) -> NSRange? {
        if let rangeOfSubstring = self.range(of: substring) {
            return NSRange(rangeOfSubstring, in: self)
        } else {
           return nil
        }
    }
}

extension String {
    var fullRange3: Range<String.Index> { return startIndex..<endIndex }
}
// Usage
//let swiftRange = "abc".fullRange
//or
//let nsRange = "abc".fullRange.toRange

//And when you need NSRange from String in Swift 4:
//NSRange(string.startIndex.encodedOffset ..< string.endIndex.encodedOffset)

// Deprecated
//extension NSRange {
//    public init(_ range: Range<String.Index>) {
//        self.init(location: range.lowerBound.encodedOffset, length: range.upperBound.encodedOffset - range.lowerBound.encodedOffset)
//    }
//}
//
//extension Range where Bound == String.Index {
//    var nsRange: NSRange {
//        return NSRange(location: self.lowerBound.encodedOffset, length: self.upperBound.encodedOffset - self.lowerBound.encodedOffset)
//    }
//}
