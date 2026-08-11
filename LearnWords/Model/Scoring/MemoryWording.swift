//
//  MemoryWording.swift
//  LearnWords
//
//  Memory strength in plain words (TD-50).
//
//  **"Remembered for about 12 days" beats a percentage.** It is the quantity the horizon
//  slider is already denominated in, so the learner has met it before, and it is the one
//  number in the model that answers the question they actually ask — *will I still know
//  this next week?* (docs/MasteryAndProgressUI.md §2.2).
//
//  `DateComponentsFormatter` rather than hand-rolled arithmetic and pluralisation. It picks
//  the unit, declines the noun, and does it in every language the app ships — Russian needs
//  "день"/"дня"/"дней" and Spanish needs its own agreement, and none of that is worth
//  reimplementing behind a `%d`.
//
//  Pure: no store, no UIKit, and the clock is a parameter. A value type that consults
//  `Date()` answers a different question than the one it was asked.
//

import Foundation

enum MemoryWording {

    /// How long this will be remembered, approximately: "about 12 days".
    ///
    /// **Approximate on purpose.** Stability is a fitted parameter of a model of a person,
    /// not a measurement, and "12.4 days" claims a precision the number does not have.
    /// Below a day it is not worth a unit at all — the learner is being told it is fragile,
    /// which "less than a day" says and "0 days" does not.
    static func horizon(days: Double) -> String {
        guard days >= 1 else {
            return NSLocalizedString("Remembered for less than a day",
                                     comment: "Statistics; memory strength")
        }
        return String(format: NSLocalizedString("Remembered for about %@",
                                                comment: "Statistics; a duration"),
                      duration(days: days))
    }

    /// When this is next worth practising: "Due now", or "Due in about 3 days".
    static func due(_ date: Date?, now: Date = Date()) -> String {
        guard let date, date > now else {
            return NSLocalizedString("Due now", comment: "Statistics; a due date")
        }
        return String(format: NSLocalizedString("Due in about %@",
                                                comment: "Statistics; a duration"),
                      duration(days: date.timeIntervalSince(now) / 86_400))
    }

    /// One unit, chosen by magnitude — "12 days", "6 weeks", "6 months", "1 year".
    ///
    /// **The unit is picked here rather than by the formatter**, which given a free choice
    /// says "2 weeks" for twelve days. That is a 17% overstatement, and worse, it is
    /// incomparable with the horizon preference the learner has already met: that slider is
    /// denominated in *days* and floored at ten, so a memory in that range has to be spoken
    /// in days or the two numbers cannot be held side by side
    /// (docs/MasteryAndProgressUI.md §2.2, whose own example is "about 12 days").
    ///
    /// Above a month the reverse is true — "45 days" is precision nobody has — so the unit
    /// grows. One unit throughout: the second is noise at this precision and is always
    /// wrong by the time it is read.
    private static func duration(days: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits =
            days < 30 ? [.day]
            : days < 90 ? [.weekOfMonth]
            : days < 365 ? [.month]
            : [.year]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        let seconds = max(days, 1) * 86_400
        // The formatter is documented to return nil for inputs it cannot express; a bare
        // day count is a poor label but an honest one, and better than an empty row.
        return formatter.string(from: seconds)
            ?? String(format: NSLocalizedString("%d days", comment: "Statistics; a fallback"),
                      Int(days.rounded()))
    }
}
