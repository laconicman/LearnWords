//
//  WordWidget.swift
//  WordWidget
//
//  Created by Paul Buktab on 7/18/26.
//  Copyright © 2026 Paul. All rights reserved.
//
//  WidgetKit home-screen widget (iOS 14+): shows words from the current set, read from the
//  shared App-Group store via `Storage`. iOS 12–13 are served by the legacy Today extension
//  (`Widget` target) instead — see docs/Design.md (TD-4).
//

import WidgetKit
import SwiftUI

struct WordsEntry: TimelineEntry {
    let date: Date
    let setName: String
    let words: [WordAndStat]

    static let sample = WordsEntry(
        date: Date(),
        setName: "Sample Set",
        words: [
            WordAndStat(firstWord: "bear", secondWord: "медведь", correct: [:], incorrect: [:], skiped: 0),
            WordAndStat(firstWord: "fox", secondWord: "лиса", correct: [:], incorrect: [:], skiped: 0),
            WordAndStat(firstWord: "sheep", secondWord: "овца", correct: [:], incorrect: [:], skiped: 0),
            WordAndStat(firstWord: "rabbit", secondWord: "кролик", correct: [:], incorrect: [:], skiped: 0),
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

    /// Reads the current word set from the shared App-Group store (same data the app
    /// and the legacy Today extension use), shuffled so each refresh shows new words.
    private func loadEntry() -> WordsEntry {
        let setName = Storage.currentWordSet
        let words = Storage.getWordSet(name: setName)
        return WordsEntry(date: Date(), setName: setName, words: words.shuffled())
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
                ForEach(entry.words.prefix(maxRows), id: \.firstWord) { word in
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.firstWord)
                            .font(.footnote.weight(.medium))
                        Spacer(minLength: 8)
                        Text(word.secondWord)
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
