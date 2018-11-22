//
//  TodayViewController.swift
//  Widget
//
//  Created by Paul on 08.10.2017.
//  Copyright © 2017 Paul. All rights reserved.
//
// TO_DO Smart RowHight
import UIKit
import NotificationCenter

class TodayViewController: UIViewController, NCWidgetProviding, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    
    var words = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        extensionContext?.widgetLargestAvailableDisplayMode = .expanded
        
        if let widgetActiveDisplayMode = extensionContext?.widgetActiveDisplayMode {
            if let widgetSize = extensionContext?.widgetMaximumSize(for: widgetActiveDisplayMode) {
                if widgetActiveDisplayMode == .compact {
                    tableView.rowHeight = widgetSize.height / 2 //Use Mod here and font size
                    print("Widget size: \(widgetSize)")
                }
            }
        }
        
        
    }

    
    
    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        
        if let defaults = UserDefaults(suiteName: "group.club.laconic.LearnWords") {
            if let savedWords = defaults.stringArray(forKey: "Words") {
                print("Loaded words: \(savedWords)")
                //            if let savedWords = defaults.object(forKey: "Words") as? [String] {
                words = savedWords
            } else {
                print("Failed to load user defaults from: group.club.laconic.LearnWords")
            }
        }
        
        if activeDisplayMode == .compact {
            preferredContentSize = CGSize(width: 0, height: 110)
        } else {
            preferredContentSize = CGSize(width: 0, height: 440) //This should be calculated
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return words.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Word", for: indexPath)
        
        let word = words[indexPath.row]
        let split = word.components(separatedBy: "::")
        
        cell.textLabel?.text = split[0]
        cell.detailTextLabel?.text = ""
        
        cell.selectedBackgroundView = UIView()
        cell.selectedBackgroundView?.backgroundColor = UIColor(white: 1, alpha: 0.2)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if let cell = tableView.cellForRow(at: indexPath) {
            if cell.detailTextLabel?.text == "" {
                let word = words[indexPath.row]
                let split = word.components(separatedBy: "::")
                cell.detailTextLabel?.text = split[1]
            } else {
                cell.detailTextLabel?.text = ""
            }
        }
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        // Perform any setup necessary in order to update the view.
        
        if let defaults = UserDefaults(suiteName: "group.club.laconic.LearnWords") {
            if let savedWords = defaults.stringArray(forKey: "Words") {
                print(savedWords)
                //            if let savedWords = defaults.object(forKey: "Words") as? [String] {
                words = savedWords
                completionHandler(NCUpdateResult.newData)
            }
        } else {
            print("No user defaults")
            completionHandler(NCUpdateResult.failed)
        }
        
        // If an error is encountered, use NCUpdateResult.Failed
        // If there's no update required, use NCUpdateResult.NoData
        // If there's an update, use NCUpdateResult.NewData
        

    }
    
}
