//
//  File.swift
//  LearnWords
//
//  Created by Paul Buktab on 7/27/26.
//  Copyright © 2026 Paul. All rights reserved.
//

import Foundation

extension Bundle {
    static let mainIdentifier = main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String ?? "club.laconic.LearnWords"
    static let mainAppShortVersion = main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    static let mainAppVersionBuild = main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let mainAppIdentifierWithVersion = "\(mainIdentifier): \(mainAppShortVersion)"
    static let mainAppVersionWithBuild = "\(mainAppShortVersion).\(mainAppVersionBuild)"
    static let mainAppStoreVersion = "\(mainAppShortVersion) (\(mainAppVersionBuild))"
}
