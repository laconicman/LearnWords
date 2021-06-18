//
//  WordSetsTableViewController.swift
//  LearnWords
//
//  Created by  Paul on 18.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import UIKit

class WordSetsTableViewController: UITableViewController {
    
    
    // MARK: - IBActions
    
    @IBAction func addNewWord(_ sender: UIBarButtonItem) {
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
            Storage.wordSets.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
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
