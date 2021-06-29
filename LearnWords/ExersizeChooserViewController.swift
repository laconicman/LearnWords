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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        numberOfWordsInSet.text = pluralizedWordCount(Storage.wordsAndStat.count)
    }



}
