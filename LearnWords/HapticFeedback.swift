//
//  HapticFeedback.swift
//  LearnWords
//
//  Created by  Paul on 17.06.2021.
//  Copyright © 2021 Paul. All rights reserved.
//

import Foundation
import UIKit

func haptic(feedback: UINotificationFeedbackGenerator.FeedbackType) {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(feedback)
}
