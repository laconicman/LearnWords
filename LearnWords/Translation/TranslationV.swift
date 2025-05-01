/*
import Foundation
import Translation
// import SwiftUI
// VM from Apple translation sample

@available(iOS 18.0, *)
@Observable
final class TranslationViewModel {
    
    static let shared = TranslationViewModel()
    
    private var configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: LWUserDefaults.standard.languageToStudyPreference ?? "en"),
        target: Locale.Language(identifier: LWUserDefaults.standard.nativeLanguagePreference ?? "ru")
    )
    
    var translatedText = ""
//    var dummyView = Text("Hello, world!").translationTask(TranslationSession.Configuration(
//        source: Locale.Language(identifier: LWUserDefaults.standard.languageToStudyPreference ?? "en"),
//        target: Locale.Language(identifier: LWUserDefaults.standard.nativeLanguagePreference ?? "ru"))) { session in
//        await translate(text: text, using: session)
//    }
//    var translations = [String: String]()
    var isTranslationSupported: Bool?

    // German food items ("Salad", "Fries", and "Soup")
    var foodItems = ["Salat 🥗", "Fritten 🍟", "Suppe 🍜"]

    func reset() {
        foodItems = ["Salat 🥗", "Fritten 🍟", "Suppe 🍜"]
        isTranslationSupported = nil
    }

    var availableLanguages: [AvailableLanguage] = []
    
    private let availability = LanguageAvailability()

    private init() {
        prepareSupportedLanguages()
    }

    func prepareSupportedLanguages() {
        Task { @MainActor in
            let supportedLanguages = await availability.supportedLanguages
            availableLanguages = supportedLanguages.map {
                AvailableLanguage(locale: $0)
            }.sorted()
        }
    }
}

// MARK: - Single string of text

@available(iOS 18.0, *)
extension TranslationViewModel {
    func translate(text: String, using session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(text)
            translatedText = response.targetText
//            translations[text] = response.targetText
        } catch {
            // Handle any errors.
        }
    }
    
//    func t(text: String) {
//        let t = Text("Hello, world!").translationTask(configuration) { [weak self] session in
//            await self?.translate(text: text, using: session)
//        }
//    }
}

// MARK: - Batch of strings

@available(iOS 18.0, *)
extension TranslationViewModel {
    func translateAllAtOnce(using session: TranslationSession) async {
        Task { @MainActor in
            let requests: [TranslationSession.Request] = foodItems.map {
                // Map each item into a request.
                TranslationSession.Request(sourceText: $0)
            }

            do {
                try await session.prepareTranslation()
                let responses = try await session.translations(from: requests)
                foodItems = responses.map {
                    // Update each item with the translated result.
                    $0.targetText
                }
            } catch {
                // Handle any errors.
            }
        }
    }
}

// MARK: - Batch of strings as a sequence

@available(iOS 18.0, *)
extension TranslationViewModel {
    func translateSequence(using session: TranslationSession) async {
        Task { @MainActor in
            let requests: [TranslationSession.Request] = foodItems.enumerated().map { (index, string) in
                // Assign each request a client identifier.
                    .init(sourceText: string, clientIdentifier: "\(index)")
            }

            do {
                try await session.prepareTranslation()
                for try await response in session.translate(batch: requests) {
                    // Use the returned client identifier (the index) to map the request to the response.
                    guard let index = Int(response.clientIdentifier ?? "") else { continue }
                    foodItems[index] = response.targetText
                }
            } catch {
                // Handle any errors.
            }
        }
    }
}

// MARK: - Language availability

@available(iOS 18.0, *)
extension TranslationViewModel {
    func checkLanguageSupport(from source: Locale.Language, to target: Locale.Language) async {
        let status = await availability.status(from: source, to: target)

        switch status {
        case .installed, .supported:
            isTranslationSupported = true
        case .unsupported:
            isTranslationSupported = false
        @unknown default:
            print("Not supported")
        }
    }

}
*/
