//
//  AppConstants.swift
//  LearnWords
//
//  Created by Paul Buktab on 4/25/25.
//  Copyright © 2025 Paul. All rights reserved.
//

import Foundation
// import OSLog // TODO: use in future instead of print

enum AppConstants {
    static let appGroup: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.example.MyApp"
        
        // Find the main app bundle ID by removing extension suffixes
        // This handles any extension naming pattern (widget, extension, share, etc.)
        let components = bundleID.components(separatedBy: ".")
//        if components.count > 2 && (
//            components.last == "widget" ||
//            components.last == "extension" ||
//            components.last == "share" ||
//            components.last?.contains("Extension") == true
//        ) {
            // Remove the last component (extension suffix)
            let baseID = components.dropLast().joined(separator: ".")
            print("baseID: \(baseID)")
            return "group.\(baseID)"
//        }

        // If no extension suffix found, use the bundle ID as is
//        return "group.\(bundleID)"
    }()
}
