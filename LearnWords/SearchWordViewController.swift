//
//  SearchViewController.swift
//  Compact Swift Dictionary
//
//  Created by Paul on 11.11.2018.
//  Copyright © 2018 Laconic. All rights reserved.
//
// TODO: Limit search term to one word at least for suggestions, maybe visually
// TODO: Add tableView Animation
// TODO: Introduce constants for languages (hint: use system ones)

import UIKit

class LocalizedUISearchController: UISearchController{
    
    override var textInputMode: UITextInputMode?{
        for inputMode in UITextInputMode.activeInputModes{
            print("inputMode.primaryLanguage: \(inputMode.primaryLanguage)")
            if (inputMode.primaryLanguage?.hasPrefix("ru"))! {
                return inputMode
            }
        }
        return super.textInputMode
    }
}

class UILocalizedSearchController: UISearchController{
    private var _textInputMode: UITextInputMode?
    // or
    private var forcedPrimaryLanguage = UITextInputMode.activeInputModes.first?.primaryLanguage { //or computed var
        didSet {
            debugPrint("forcedPrimaryLanguage", forcedPrimaryLanguage)
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
    var searchedObject = SearchedObject.original(lang: "en", word: "") //UITextInputMode.activeInputModes.compactMap{$0.primaryLanguage}
    
    // Keep an instance of UITextChecker for getting suggested words from word fragments.
    // This is the autocorrect word list, not the actual dictionary list, so it will return some words without definitions.
    private let textChecker = UITextChecker() // Use global?
    private var suggestions = [String]()
    private var searchLanguage: String { get {
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
    private lazy var recentSearches: [String] = (userDefaults?.stringArray(forKey: kRecentSearchesKey)) ?? []
    
    let themeTint = UIColor.orange // UIColor(white: 0.9, alpha: 0.9)
    
    let searchController = LocalizedUISearchController(searchResultsController: nil)
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSearchController()
        // tableView.keyboardDismissMode = .onDrag
        
        switch searchedObject {
        case .translation(orig_lang: _, orig_word: _, dest_lang: _, translations: _):
            //language = d_lang
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(startTest))
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(startTest))
            navigationItem.rightBarButtonItems = [cancelButton, doneButton]
        case.original(_, _):
            //language = o_lang
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(startTest))
        }

    }
    
    @objc func startTest() {
        debugPrint(#function)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchController.becomeFirstResponder // display the keyboard right away
    }
    
    //------------------------------------------------------------------------------
    // Present a UIReferenceLibraryViewController showing a definition.
    // Variations for regular and compact size class environments
    //------------------------------------------------------------------------------
    private func presentReferenceViewControllerWithTerm(_ term: String) {
        addToRecentSearches(term)
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
            if let searchText = searchController.searchBar.text, !searchText.isEmpty {
                cell.textLabel?.text = suggestions[indexPath.row]
            } else {
                cell.textLabel?.text = recentSearches[indexPath.row]
            }
        case (.translation(let lang, let word, _, _), 0):
            cell.textLabel?.text = word
            cell.detailTextLabel?.text = lang
        case (.translation, 1):
            if let searchText = searchController.searchBar.text, !searchText.isEmpty {
                cell.textLabel?.text = suggestions[indexPath.row]
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
            if searchController.isActive && searchController.searchBar.text != "" {
                return suggestions.count;        // show suggestions
            } else {
                return recentSearches.count;
            }
        case .translation:
            switch section {
            case 0:
                return 1
            case 1:
                if searchController.isActive && searchController.searchBar.text != "" {
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
    func setupSearchController() {
        /** Search presents a view controller by applying normal view controller presentation semantics.
         This means that the presentation moves up the view controller hierarchy until it finds the root
         view controller or one that defines a presentation context.
         */
        
        /** Specify that this view controller determines how the search controller is presented.
         The search controller should be presented modally and match the physical size of this view controller.
         */

        definesPresentationContext = true
        debugPrint(#function, " - ", searchLanguage)
        //searchController.setTextInputModePrimaryLanguage(by: searchLanguage)
        searchController.searchResultsUpdater = self
        // searchController.searchBar.barTintColor = themeTint
        searchController.searchBar.placeholder = NSLocalizedString("New word", comment: "placeholder for adding new word to vocabulary")
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.searchBarStyle = .prominent // use the prominent style to get a white background
        searchController.searchBar.autocapitalizationType = .none;
        
        // Idea from official Apple sample:
        // https://developer.apple.com/documentation/uikit/view_controllers/displaying_searchable_content_by_using_a_search_controller
        if #available(iOS 13.0, *) {
            // For iOS 11 and later, place the search bar in the navigation bar.
            navigationItem.searchController = searchController
            
            // Make the search bar always visible.
            navigationItem.hidesSearchBarWhenScrolling = false
        } else {
            // For iOS 10 and earlier, place the search controller's search bar in the table view's header.
            tableView.tableHeaderView = searchController.searchBar
        }
        
        //searchController.delegate = self
        searchController.dimsBackgroundDuringPresentation = false // The default is true.
        searchController.searchBar.delegate = self // Monitor when the search button is tapped.
        // Ideas from Compact Dictionary
        // Another thing that should work from iOS 9 to 12 is:
        //navigationItem.titleView = searchController.searchBar
        // but this needs checking. Besides we will loose NavigationBar.title if use this.
        searchController.searchBar.becomeFirstResponder // display the keyboard right away
    }
    
  
    //------------------------------------------------------------------------------
    // As each new character is typed in the search bar, get new suggestions
    // In english, skip over suggestions that end in ' or 's (those come up often
    // but never have definitions)
    //------------------------------------------------------------------------------
    func filterRowsForSearchedText(_ searchText: String) {
        let unfilteredSuggestions = textChecker.completions(forPartialWordRange: searchText.fullRange(), in: searchText, language: searchLanguage ) ?? []
        //let guesses = textChecker.guesses(forWordRange: searchText.fullRange(), in: searchText, language: language ) ?? []
        //unfilteredSuggestions.append(contentsOf: guesses)
        //can play with animation here later
        if searchLanguage.hasPrefix("en") { // for english only: if the word does not end in ' or 's
            // use the filtered list of suggested words for English
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
        debugPrint(#function)
        if let term = searchBar.text {
            presentReferenceViewControllerWithTerm(term)
        }
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
        userDefaults?.set(recentSearches, forKey: kRecentSearchesKey)
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Add Translation", let cell = (sender as? UITableViewCell) {
            if let wordSearchVC = segue.destination as? SearchWordViewController {
                //wordSearchVC.language = "ru" //Bundle.main.preferredLocalizations[1]
                wordSearchVC.searchedObject = .translation(
                    orig_lang: "en",
                    orig_word: cell.textLabel?.text ?? "?",
                    dest_lang: "ru",
                    translations: [])
            }
        }
    }

    
}

extension SearchWordViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        if let term = searchController.searchBar.text {
            filterRowsForSearchedText(term)
        }
    }
}
// TODO: Those are ugly
extension String {
    func fullRange() -> NSRange {
        return NSMakeRange(0, self.count)
    }
}

extension String {
    func fullRange2() -> Range<String.Index> {
        return Range(uncheckedBounds: (lower: self.startIndex, upper: self.endIndex))
    }
}

extension String {
    var fullRange3:Range<String.Index> { return startIndex..<endIndex }
}
// Usage
//let swiftRange = "abc".fullRange
//or
//let nsRange = "abc".fullRange.toRange

//And when you need NSRange from String in Swift 4:
//NSRange(string.startIndex.encodedOffset ..< string.endIndex.encodedOffset)
