//
//  UserDefaultsAppGroup.swift
//  LearnWords
//
//  Created by Paul Buktab on 4/25/25.
//  Copyright © 2025 Paul. All rights reserved.
//
import Foundation
import OSLog

/// Provides app group functionality for sharing data between app and extensions
public enum AppGroup {
    
    /// Returns the app group identifier used for shared containers
    public static var identifier: String {
        // Get current bundle ID
        guard let bundleID = Bundle.main.bundleIdentifier else {
            // Fallback if bundle ID can't be determined
            assertionFailure("Bundle identifier not found")
            return "group.com.example.app"
        }
        
        // Determine main app bundle ID by removing extension suffixes
        let mainAppID = mainAppBundleID(from: bundleID)
        return "group.\(mainAppID)"
    }
    
    /// UserDefaults keys to avoid string literals throughout the codebase
    public enum UserDefaultsKey: KeyValue {
        
        case importedText(String?), words([String])
        
        public var key: String {
            switch self {
            case .words: "Words" // Just for tests
            case .importedText: "ImportedText"
            }
        }
        
        public var value: Any? {
            switch self {
            case .importedText(let value): value
            case .words(let value): value
            }
        }
        // This could be improved
        //        public static var username: String {
//        get set implementation
//    }
//        public static let isDarkModeEnabled = "isDarkModeEnabled"
//        public static let lastUpdated = "lastUpdated"
        // Add more keys as needed
    }
    
    /// Returns a UserDefaults instance configured with the app group
    public static var userDefaults: UserDefaults? {
        return UserDefaults(suiteName: identifier)
    }
    
    // MARK: - Private Helpers
    
    /// Configuration for the app group detection
    private enum Configuration {
        /// Common extension suffixes known in iOS/macOS ecosystem
        static let knownExtensionSuffixes = [
            // Standard extensions
            ".widget",
            ".extension",
            ".share",
            ".notification",
            ".keyboard",
            ".intent",
            ".spotlight",
            ".clip",
            ".photo",
            ".service",
            ".action",
            ".finder",
            
            // Apple Watch extensions
            ".watchkitapp",
            ".watchkitextension",
            
            // Common words in extension names
            ".watchapp",
            ".stickerpack",
            ".stickers",
            ".messageextension",
            ".imessage",
            ".intentsui",
            
            // Additional iOS 14+ extensions
            ".appclip",
            ".widgetkit",
            ".quicklook",
            ".cloudkit",
            ".push",
            
            // macOS/catalyst extensions
            ".safari",
            ".safariextension",
            ".dock",
            ".prefpane",
            ".screensaver",
            ".automator",
            
            // Generic words that might indicate an extension
            ".ext",
            ".addon",
            ".plugin"
        ]
        
        /// Your app target extension, override if needed
        static let customExtensionDetectionClosure: ((String) -> Bool)? = nil
        
        /// Manual override for the main app bundle ID
        static let manualMainAppBundleID: String? = nil
        
        #if DEBUG
        /// Whether to show debug logs
        static let verboseLogs = true
        #else
        static let verboseLogs = false
        #endif
    }
    
    /// Extracts the main app bundle ID from any bundle ID (app or extension)
    private static func mainAppBundleID(from bundleID: String) -> String {
        // If manually configured, use that instead of detection logic
        if let manualID = Configuration.manualMainAppBundleID {
            return manualID
        }
        
        // Custom extension detection logic if provided
        if let customDetection = Configuration.customExtensionDetectionClosure, customDetection(bundleID) {
            logDebug("Detected extension via custom closure: \(bundleID)")
            // Extract base ID using heuristics
            let components = bundleID.components(separatedBy: ".")
            return components.dropLast().joined(separator: ".")
        }
        
        let components = bundleID.components(separatedBy: ".")
        
        // Method 1: Check against known extension suffixes
        for suffix in Configuration.knownExtensionSuffixes {
            if bundleID.hasSuffix(suffix) {
                let mainID = String(bundleID.dropLast(suffix.count))
                logDebug("Detected extension by suffix '\(suffix)': \(bundleID) → \(mainID)")
                return mainID
            }
        }
        
        // Method 2: Check specifically for exact "Extension" suffix
        // This is more reliable than checking for keywords within components
        if components.count > 1, let lastComponent = components.last {
            if lastComponent == "Extension" || lastComponent.hasSuffix("Extension") {
                let mainID = components.dropLast().joined(separator: ".")
                logDebug("Detected extension by 'Extension' suffix: \(bundleID) → \(mainID)")
                return mainID
            }
        }
        
        // Method 3: Check for extension metadata in the bundle
        // This is a reliable approach because it checks the actual bundle type
        
        // First, check for NSExtension key in Info.plist - this is definitive for extensions
        if Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil {
            if components.count > 1 {
                let mainID = components.dropLast().joined(separator: ".")
                logDebug("Detected extension by NSExtension key: \(bundleID) → \(mainID)")
                return mainID
            }
        }
        
        // Then check bundle type - extensions are typically XPC services
        let bundleType = Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String
        if bundleType == "XPC!" {
            // This is definitely an extension
            if components.count > 1 {
                let mainID = components.dropLast().joined(separator: ".")
                logDebug("Detected extension by bundle type 'XPC!': \(bundleID) → \(mainID)")
                return mainID
            }
        }
        
        // If no extension pattern found, assume it's already the main app bundle ID
        logDebug("No extension detected, using bundleID as is: \(bundleID)")
        return bundleID
    }
    
    /// Log debug information if enabled
    private static func logDebug(_ message: String) {
        #if DEBUG
        if Configuration.verboseLogs {
            print("[AppGroup] \(message)")
        }
        #endif
    }
}

public protocol KeyValue {

    var key: String { get }
    var value: Any? { get }

}

public extension UserDefaults {
    
    func set(_ keyValue: KeyValue) {
        setValue(keyValue.value, forKey: keyValue.key)
    }

    func set(_ keyValue: AppGroup.UserDefaultsKey) {
        setValue(keyValue.value, forKey: keyValue.key)
    }

}
