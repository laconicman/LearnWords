//
//  APNSEnvironment.swift
//  LearnWords
//
//  Created by Paul Buktab on 7/27/26.
//  Copyright © 2026 Paul. All rights reserved.
//

import UIKit
import OSLog // or `os.log`?

@available(iOS 14.0, *)
extension Bundle {
    static var apnsEnvironment: APNSEnvironment {
#if DEBUG
        return .sandbox
#else
        return embeddedProvisioningAPSEnvironment ?? .production
#endif
    }
    //    static var isSandboxEnvironment: Bool {
    //        #if DEBUG
    //        return true
    //        #else
    //        if let receiptURL = Self.main.appStoreReceiptURL {
    //            return receiptURL.lastPathComponent == "sandboxReceipt"
    //        }
    //        return false
    //        #endif
    //    }
    private static var embeddedProvisioningAPSEnvironment: APNSEnvironment? {
        guard let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else {
            return nil
        }
        guard let profileData = NSData(contentsOfFile: profilePath) else {
            return nil
        }
        guard let profileString = NSString(data: profileData as Data, encoding: String.Encoding.ascii.rawValue) else {
            return nil
        }
        let scanner = Scanner(string: profileString as String)
        guard scanner.scanUpToString("<?xml") != nil else { return nil }
        guard let extractedPlist = scanner.scanUpToString("</plist>") else { return nil }
        let plistString = extractedPlist + "</plist>"
        guard let plistData = plistString.data(using: .utf8) else { return nil }
        do {
            if let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
               let entitlements = plist["Entitlements"] as? [String: Any],
               let apsEnvironment = entitlements["aps-environment"] as? String {
                return apsEnvironment != "production" ?  .sandbox : .production
            }
        } catch {
            Logger.application.error("\(#function, privacy: .public) Error parsing provisioning profile: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    enum APNSEnvironment: CustomDebugStringConvertible {
        case sandbox, production

        var debugDescription: String {
            switch self {
            case .sandbox: "sandbox"
            case .production: "production"
            }
        }
    }
}
