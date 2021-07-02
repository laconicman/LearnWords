//
//  ExersizeChooserViewController.swift
//  LearnWords
//
//  Created by  Paul on 28.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import UIKit

class ExersizeChooserViewController: UIViewController {


    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBOutlet weak var numberOfWordsInSet: UILabel!
    @IBAction func includeLearnedWordsChanged(_ sender: UISwitch) {
        LWUserDefaults.standard.includeLearnedWords = sender.isOn
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        numberOfWordsInSet.text = NSLocalizedString("Total ", comment: "Label total words") + pluralizedWordCount(Storage.wordsAndStat.count) + ". " + NSLocalizedString("Learned ", comment: "Label learned words") + pluralizedWordCount(Storage.wordsAndStat.reduce(0, { result, wAs in
            if wAs.known == WordAndStat.maxKnownLevel { return result + 1 } else { return result }
        })) + "."
    }



}
