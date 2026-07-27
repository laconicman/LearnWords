//
//  File.swift
//  LearnWords
//
//  Created by Paul Buktab on 7/27/26.
//  Copyright © 2026 Paul. All rights reserved.
//

import OSLog

@available(iOS 14.0, *)
public extension Logger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "undefined"
    static let startup = Logger(subsystem: subsystem, category: "startup")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let credentials = Logger(subsystem: subsystem, category: "credentials")
    static let application = Logger(subsystem: subsystem, category: "application")
    static let apns = Logger(subsystem: subsystem, category: "apns")
    static let callKit = Logger(subsystem: subsystem, category: "callKit")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let routing = Logger(subsystem: subsystem, category: "routing")
    static let assembly = Logger(subsystem: subsystem, category: "assembly")
    static let logger = Logger(subsystem: subsystem, category: "logger")
    static let network = Logger(subsystem: subsystem, category: "network")

    static let authorization = Logger(subsystem: subsystem, category: "authorization")
    static let userProfile = Logger(subsystem: subsystem, category: "userProfile")
    static let account = Logger(subsystem: subsystem, category: "account")

    static let coreData = Logger(subsystem: subsystem, category: "coreData")
}
