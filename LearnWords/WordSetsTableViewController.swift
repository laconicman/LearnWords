//
//  WordSetsTableViewController.swift
//  LearnWords
//
//  Created by  Paul on 18.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import UIKit
import MobileCoreServices

class WordSetsTableViewController: UITableViewController, UIDocumentPickerDelegate {
    
    
    // MARK: - IBActions
    
    @IBAction func importFromFile(_ sender: UIBarButtonItem) {
        let types: [String] = [kUTTypeText as String]
        let documentPicker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        self.present(documentPicker, animated: true, completion: nil)
    }
    


    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
    {
        guard let fileURL = urls.first else { return }
        debugLog("importing: \(fileURL)")
        do
        {
            var importedWords = [WordAndStat]()
            var importedWord = ""
            let importedString = try String(contentsOf: fileURL, encoding: .utf8)
            if  importedString.aproxWordCount > 1 {
                let dictionaryEntries = split(importedString, by: "\n" + ";" + "\u{2028}")
                importedWords = dictionaryEntries.compactMap( {
                    let e = split($0, by: "|:")
                    if e.first?.isEmpty ?? true || e.last?.isEmpty ?? true || e.count != 2 { return nil }
                    let pair = e[0].trimmingCharacters(in: .whitespaces) + "::" + e[1].trimmingCharacters(in: .whitespaces)
                    return WordAndStat(pair: pair.lowercased(), known: 0, unknown: 0, skiped: 0)
                })
                // TODO: Create a screen to verify and select `importedWords`. Check for duplicates
                importedWords = importedWords.filter({ (impW) -> Bool in
                    !Storage.wordsAndStat.contains { (storedW) -> Bool in // TODO: make temporary `Set`
                        impW.pair == storedW.pair
                    }
                })
                Storage.wordsAndStat.append(contentsOf: importedWords)
                Storage.saveWords(Storage.wordsAndStat)
            } else { // TODO: it later
                // import one word
//                importedWord = lemmas(from: importedString).first ?? ""
//                performSegue(withIdentifier: "AddWord", sender: self)
            }
        }
        catch
        {
            debugLog("Import failed: \(error)")
            let alert = UIAlertController(
                title: NSLocalizedString("IMPORT_FAIL_TITLE", comment: "Title for failed import"),
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    @IBAction func addNewWordSet(_ sender: UIBarButtonItem) {
        // create our alert controller
        let ac = UIAlertController(title: NSLocalizedString("Add new word set", comment: "AlertController title"), message: nil, preferredStyle: .alert)
        
        ac.addTextField { textField in
            textField.placeholder = NSLocalizedString("Name of set", comment: "")
        }
        
        // create an "Add Word" button that submits the user's input
        let submitAction = UIAlertAction(title: NSLocalizedString("Add", comment: "AlertAction title"), style: .default) { [unowned self, ac] (action: UIAlertAction!) in
            let nameOfSet = ac.textFields?[0].text ?? ""
            
            if let indexOfInsertedRow = Storage.insertWordSet(name: nameOfSet) {
                let newIndexPath = IndexPath(row: indexOfInsertedRow, section: 0)
                self.tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
        }
        ac.addAction(submitAction)
        ac.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "AlertAction title"), style: .cancel))
        present(ac, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

         //self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return Storage.wordSets.count
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "wordSetsCell", for: indexPath)
        cell.textLabel?.text = Storage.wordSets[indexPath.row]
        cell.accessoryType = (cell.textLabel?.text == Storage.currentWordSet) ? .checkmark : .none
        
        DispatchQueue.main.async {
            let wSet = Storage.getWordSet(name: Storage.wordSets[indexPath.row])
            cell.detailTextLabel?.text = "Total " + pluralizedWordCount(wSet.count) + ". Learned " + pluralizedWordCount(wSet.reduce(0, { result, wAs in
                if wAs.known == WordAndStat.maxKnownLevel { return result + 1 } else { return result }
            })) + "."
        }
        return cell
    }
    

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            Storage.removeWordSet(at: indexPath.row)
            
            tableView.deleteRows(at: [indexPath], with: .automatic)
            tableView.reloadData() // just for selection
        }
    }
    

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if tableView.cellForRow(at: indexPath) != nil {
            Storage.currentWordSet = Storage.wordSets[indexPath.row]
            tableView.reloadData()
        }
    }
    


    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
