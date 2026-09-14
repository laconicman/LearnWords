//
//  WordWidget.swift
//  WordWidget
//
//  Created by Paul Buktab on 7/18/26.
//  Copyright © 2026 Paul. All rights reserved.
//
//  WidgetKit home-screen widget: shows words from the selected set, read from the shared
//  App-Group Core Data store via `Lexicon`. The app's only widget since the legacy Today
//  extension was deleted with the iOS 12 floor (docs/TechDebt.md, TD-4).
//
//  The widget **reads only**. It never seeds and never writes: an extension that created
//  data would race the app for the same store to no purpose.
//

import WidgetKit
import SwiftUI

struct WordsEntry: TimelineEntry {

    /// One line of the widget. Flattened here rather than carrying a `Sense`: the widget
    /// shows text, and a snapshot type keeps the store out of the SwiftUI views.
    struct Row: Hashable {
        let word: String
        let meaning: String
    }

    let date: Date
    let setName: String
    let words: [Row]

    static let sample = WordsEntry(
        date: Date(),
        setName: "Sample Set",
        words: [
            Row(word: "bear", meaning: "медведь"),
            Row(word: "fox", meaning: "лиса, лисица"),
            Row(word: "sheep", meaning: "овца"),
            Row(word: "rabbit", meaning: "кролик"),
        ]
    )
}

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> WordsEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (WordsEntry) -> Void) {
        completion(context.isPreview ? .sample : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordsEntry>) -> Void) {
        let entry = loadEntry()
        // Rotate the shown words periodically; the data itself changes only when the app
        // saves, so a slow refresh cadence is enough.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Reads the selected set from the shared App-Group store (the same data the app
    /// uses), shuffled so each refresh shows new words.
    ///
    /// Synonyms are joined rather than given a row each — four rows of screen are better
    /// spent on four meanings.
    private func loadEntry() -> WordsEntry {
        let library = Library.shared
        guard let set = library.selectedSet,
              let senses = try? library.lexicon.senses(in: set.id) else {
            return WordsEntry(date: Date(), setName: "", words: [])
        }
        let pair = LanguagePair.forSet(set)
        let rows = senses.compactMap { sense -> WordsEntry.Row? in
            let words = sense.terms(in: pair.secondary).map(\.text)
            let meanings = sense.terms(in: pair.primary).map(\.text)
            guard !words.isEmpty, !meanings.isEmpty else { return nil }
            return WordsEntry.Row(word: words.joined(separator: ", "),
                                  meaning: meanings.joined(separator: ", "))
        }
        return WordsEntry(date: Date(), setName: set.name, words: rows.shuffled())
    }
}

struct WordWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: WordsEntry

    private var maxRows: Int { family == .systemSmall ? 3 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.setName)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.orange)
                .lineLimit(1)

            if entry.words.isEmpty {
                Spacer(minLength: 0)
                Text("Open LearnWords to add words")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.words.prefix(maxRows), id: \.self) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.word)
                            .font(.footnote.weight(.medium))
                        Spacer(minLength: 8)
                        Text(row.meaning)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct WordWidget: Widget {
    let kind: String = "WordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                WordWidgetEntryView(entry: entry)
                    .containerBackground(.background, for: .widget)
            } else {
                WordWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(UIColor.systemBackground))
            }
        }
        .configurationDisplayName("Word Set")
        .description("Words from your current set.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
