//
//  File.swift
//  LearnWords
//
//  Created by Paul Buktab on 9/21/25.
//  Copyright © 2025 Paul. All rights reserved.
//

import UIKit

func gotoAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { //+ "root=General&path=Network"
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
