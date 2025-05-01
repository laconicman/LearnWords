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
        // !!!: For now only bundleIdentifiers that contain 3 or 4 sections are supported
        let bundleID = Bundle.main.bundleIdentifier ?? "com.example.MyApp"
        
        // Find the main app bundle ID by removing extension suffixes
        // This handles any extension naming pattern (widget, extension, share, etc.)
        let components = bundleID.components(separatedBy: ".")
        
        if components.count > 3 { // && (
//            components.last == "widget" ||
//            components.last == "extension" ||
//            components.last == "share" ||
//            components.last?.contains("Extension") == true
//        ) {
            // Remove the last component (extension suffix)
            let baseID = components.dropLast().joined(separator: ".")
            print("baseID: \(baseID)")
            return "group.\(baseID)"
        } else if components.count == 3  {
            
            // If no extension suffix found, use the bundle ID as is
            return "group.\(bundleID)"
        } else {
            assertionFailure("Unsupported `Bundle.main.bundleIdentifier`")
            return "group.\(bundleID)"
        }
    }()
}
