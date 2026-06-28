//
//  ActionViewController.swift
//  ImportAsDictAction
//
//  Created by  Paul on 08.07.2020.
//  Copyright © 2020 Paul. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers
import OSLog

class ActionViewController: UIViewController {

    @IBOutlet weak var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Pull the shared text out of the extension context and stash it in the
        // App Group so the host app can pick it up on next launch.
        Task { await importSharedText() }
    }

    // MARK: - Import

    /// Finds the first plain-text attachment in the share input, shows it, and
    /// saves it to the shared App Group. Every failure path is logged so the
    /// import can never fail silently.
    private func importSharedText() async {
        guard let extensionContext else {
            Logger.shareImport.error("No extension context — nothing to import.")
            return
        }

        let plainText = UTType.plainText.identifier
        let items = (extensionContext.inputItems as? [NSExtensionItem]) ?? []

        for item in items {
            for provider in item.attachments ?? []
            where provider.hasItemConformingToTypeIdentifier(plainText) {
                do {
                    let loaded = try await provider.loadItem(forTypeIdentifier: plainText)
                    guard let text = Self.text(from: loaded) else {
                        Logger.shareImport.error("Plain-text attachment was not decodable: \(String(describing: loaded))")
                        continue
                    }
                    textView?.text = text
                    // TODO: parse `text` as a dictionary; for now we just store the raw text.
                    save(text)
                    return
                } catch {
                    Logger.shareImport.error("Failed to load shared item: \(error.localizedDescription)")
                }
            }
        }

        Logger.shareImport.notice("No plain-text attachment found in the share input.")
    }

    /// Best-effort decode of a loaded item into a `String`. Plain-text shares
    /// arrive as `String`/`NSString`, occasionally as UTF-8 `Data`.
    private static func text(from item: NSSecureCoding?) -> String? {
        switch item {
        case let string as String:
            return string
        case let data as Data:
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    /// Persists the imported text to the shared App Group. Logs loudly if the
    /// group container is unavailable so a misconfigured App Group is visible
    /// instead of a silent no-op.
    private func save(_ text: String) {
        guard let defaults = AppGroup.userDefaults else {
            Logger.shareImport.error("App Group UserDefaults unavailable for '\(AppGroup.identifier, privacy: .public)' — imported text NOT saved.")
            return
        }
        defaults.set(.importedText(text))
        Logger.shareImport.notice("Imported \(text.count) characters into App Group '\(AppGroup.identifier, privacy: .public)'.")
    }

    // MARK: - Actions

    @IBAction func done() {
        // Return any edited content to the host app.
        // This template doesn't do anything, so we just echo the passed in items.

        self.extensionContext!.completeRequest(returningItems: self.extensionContext!.inputItems, completionHandler: nil)
    }

    @IBAction func openApp(_ sender: Any) {
        // TODO: route to a specific screen once the share UX flow is designed.
        if let url = URL(string: "learnWords://shareaction") {
            let opened = openHostApp(url)
            Logger.shareImport.notice("Best-effort open of host app \(opened ? "succeeded" : "failed", privacy: .public).")
        }
        extensionContext?.completeRequest(returningItems: extensionContext?.inputItems, completionHandler: nil)
    }

    /// Best-effort launch of the containing app via its custom URL scheme.
    ///
    /// Apple provides **no** supported way for an action extension to open its
    /// host app — `NSExtensionContext.open(_:)` only works for Today/iMessage
    /// extensions. We walk the responder chain to `UIApplication` and invoke
    /// `open(_:options:completionHandler:)` on the main thread. That method is
    /// hidden from the extension-only API surface, so it's resolved dynamically
    /// at runtime. This is an unsupported hack that may break on a future iOS;
    /// the import itself does not depend on it.
    private func openHostApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias OpenURL = @convention(c) (UIApplication, Selector, NSURL, NSDictionary, Any?) -> Void
                let implementation = application.method(for: selector)
                let open = unsafeBitCast(implementation, to: OpenURL.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}

// MARK: - Logging

private extension Logger {

    /// Subsystem shared by this target's loggers — resolves at runtime to the
    /// extension's bundle identifier.
    static let subsystem = Bundle.main.bundleIdentifier ?? "club.laconic.LearnWords"

    /// Share-extension import flow: host app ⇄ ImportAsDictAction.
    static let shareImport = Logger(subsystem: subsystem, category: "ShareImport")
}
