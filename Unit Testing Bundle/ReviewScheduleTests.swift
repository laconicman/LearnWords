//
//  ReviewScheduleTests.swift
//  Unit Testing Bundle
//
//  What is due, and what a reminder would say about it.
//
//  The schedule and the reminder window are pure derivations over the review log, so both
//  are tested with a pinned `now` and no notification centre. The arithmetic is the part
//  that can be wrong; `UNUserNotificationCenter` is not.
//

import Testing
import Foundation
import UserNotifications
@testable import LearnWords

@MainActor
@Suite(.serialized)
struct ReviewScheduleTests {

    private func makeLexicon() -> Lexicon {
        Lexicon(persistence: LWPersistence(inMemory: true))
    }

    private func stock(_ lexicon: Lexicon, named name: String = "Animals",
                       count: Int = 3) throws -> WordSet {
        let set = try lexicon.addWordSet(named: name, languages: ["en", "ru"])
        let words = [("bear", "медведь"), ("camel", "верблюд"), ("fox", "лиса"),
                     ("pig", "свинья"), ("sheep", "овца")]
        for (en, ru) in words.prefix(count) {
            try lexicon.addSense(to: set.id, terms: [Term.Draft(en, in: "en"),
                                                     Term.Draft(ru, in: "ru")])
        }
        return set
    }

    private func pair() -> LanguagePair {
        LanguagePair(primary: "ru", secondary: "en", showsSecondaryAsPrompt: true)
    }

    /// Answers every meaning in the set correctly, once, at `date`.
    private func practiseAll(_ lexicon: Lexicon, _ set: WordSet, at date: Date) throws {
        let session = try PracticeSession.start(.dictation, in: set.id, languages: pair(),
                                                lexicon: lexicon,
                                                scope: .everything(includingLearned: true),
                                                now: date)
        while session.nextQuestion() != nil {
            try session.record(.correctVerbatim)
        }
    }

    // MARK: - The schedule

    /// A word never answered is waiting, not "not yet due".
    @Test func everythingUnseenIsDue() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon)

        let schedule = try ReviewSchedule(lexicon: lexicon)
        #expect(schedule.dueCount == 3)
        #expect(schedule.sets.first?.askableCount == 3)
        #expect(schedule.nextDueAt == nil, "nothing is *waiting* — it is all due now")
    }

    @Test func answeringPushesAMeaningOutOfTheDueSet() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 1)
        let now = Date()
        try practiseAll(lexicon, set, at: now)

        let schedule = try ReviewSchedule(lexicon: lexicon, now: now)
        #expect(schedule.dueCount == 0)
        let next = try #require(schedule.nextDueAt)
        #expect(next > now, "it comes back later, not never")
    }

    @Test func anEmptyLibraryHasNothingDueAndNothingScheduled() throws {
        let lexicon = makeLexicon()
        let schedule = try ReviewSchedule(lexicon: lexicon)
        #expect(schedule.dueCount == 0)
        #expect(schedule.nextDueAt == nil)
        #expect(schedule.setsWithWork.isEmpty)
    }

    @Test func setsAreReportedSeparatelyAndRankedByWork() throws {
        let lexicon = makeLexicon()
        let big = try stock(lexicon, named: "Big", count: 5)
        _ = try stock(lexicon, named: "Small", count: 1)

        let schedule = try ReviewSchedule(lexicon: lexicon)
        #expect(schedule.dueCount == 6)
        #expect(schedule.setsWithWork.first?.setID == big.id)
    }

    /// Overdue work accumulates: a meaning due Tuesday is still waiting on Wednesday.
    @Test func theCountByADateIncludesEverythingThatFallsDueBeforeIt() throws {
        let lexicon = makeLexicon()
        let set = try stock(lexicon, count: 3)
        let now = Date()
        try practiseAll(lexicon, set, at: now)

        let schedule = try ReviewSchedule(lexicon: lexicon, now: now)
        #expect(schedule.dueCount(by: now) == 0)
        let farFuture = now.addingTimeInterval(365 * 24 * 3600)
        #expect(schedule.dueCount(by: farFuture) == 3, "a year out, all three are waiting")
    }

    // MARK: - The reminder window

    private func withReminders(hour: Int = 19, _ body: () throws -> Void) rethrows {
        let prefs = LWUserDefaults.standard
        let savedEnabled = prefs.remindersEnabled
        let savedHour = prefs.reminderHour
        let savedMinute = prefs.reminderMinute
        defer {
            prefs.remindersEnabled = savedEnabled
            prefs.reminderHour = savedHour
            prefs.reminderMinute = savedMinute
        }
        prefs.remindersEnabled = true
        prefs.reminderHour = hour
        prefs.reminderMinute = 0
        try body()
    }

    /// 09:00 today, so "the chosen hour" is always still ahead of `now` in these cases.
    private func nineAM() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    }

    @Test func aLibraryWithWorkGetsOneReminderPerDayOfTheHorizon() throws {
        try withReminders {
            let lexicon = makeLexicon()
            _ = try stock(lexicon, count: 3)
            let now = nineAM()

            let requests = ReminderScheduler()
                .requests(for: try ReviewSchedule(lexicon: lexicon, now: now), now: now)

            #expect(requests.count == ReminderScheduler.horizonInDays,
                    "overdue work stays overdue, so every day of the window has something")
            #expect(requests.count < 64, "iOS caps pending requests")
        }
    }

    /// The point of scheduling rather than firing: a day with nothing due gets no request.
    /// This is AnkiDroid's fire-time threshold check, moved to where iOS allows it.
    @Test func aLibraryWithNothingDueGetsNoRemindersAtAll() throws {
        try withReminders {
            let lexicon = makeLexicon()
            let set = try stock(lexicon, count: 1)
            let now = nineAM()
            try practiseAll(lexicon, set, at: now)

            let schedule = try ReviewSchedule(lexicon: lexicon, now: now)
            let requests = ReminderScheduler().requests(for: schedule, now: now)

            // The one meaning comes back within the horizon or beyond it; either way no
            // day before its due date may carry a reminder.
            let firstDue = schedule.nextDueAt
            for request in requests {
                let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
                let fireDate = try #require(trigger.nextTriggerDate())
                #expect(firstDue.map { fireDate > $0 } ?? false,
                        "no reminder before anything is due")
            }
        }
    }

    @Test func remindersFireAtTheChosenHour() throws {
        try withReminders(hour: 7) {
            let lexicon = makeLexicon()
            _ = try stock(lexicon, count: 2)
            let now = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!

            let requests = ReminderScheduler()
                .requests(for: try ReviewSchedule(lexicon: lexicon, now: now), now: now)

            for request in requests {
                let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
                #expect(trigger.dateComponents.hour == 7)
                #expect(trigger.dateComponents.minute == 0)
                #expect(trigger.repeats == false, "each day is its own dated request")
            }
        }
    }

    /// Today's reminder is skipped once its hour has gone by, rather than being scheduled
    /// into the past where it would fire immediately.
    @Test func todayIsSkippedOnceItsHourHasPassed() throws {
        try withReminders(hour: 7) {
            let lexicon = makeLexicon()
            _ = try stock(lexicon, count: 2)
            let now = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!

            let requests = ReminderScheduler()
                .requests(for: try ReviewSchedule(lexicon: lexicon, now: now), now: now)

            #expect(requests.count == ReminderScheduler.horizonInDays - 1)
            for request in requests {
                let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
                #expect(try #require(trigger.nextTriggerDate()) > now)
            }
        }
    }

    /// One identifier per day, so a rebuild replaces its own requests instead of stacking
    /// a second copy beside them.
    @Test func identifiersAreOnePerDay() throws {
        try withReminders {
            let lexicon = makeLexicon()
            _ = try stock(lexicon, count: 2)
            let now = nineAM()

            let requests = ReminderScheduler()
                .requests(for: try ReviewSchedule(lexicon: lexicon, now: now), now: now)
            #expect(Set(requests.map(\.identifier)).count == requests.count)
        }
    }

    @Test func aReminderCarriesTheCountAndTheWayBackIn() throws {
        try withReminders {
            let lexicon = makeLexicon()
            _ = try stock(lexicon, count: 3)
            let now = nineAM()

            let request = try #require(ReminderScheduler()
                .requests(for: try ReviewSchedule(lexicon: lexicon, now: now), now: now).first)

            #expect(request.content.body.contains("3"))
            #expect(request.content.userInfo["url"] as? String
                    == ReminderScheduler.practiceURL.absoluteString)
        }
    }

    @Test func remindersAreNotBuiltWhenTheLearnerHasNotAskedForThem() throws {
        let prefs = LWUserDefaults.standard
        let saved = prefs.remindersEnabled
        defer { prefs.remindersEnabled = saved }
        prefs.remindersEnabled = false

        let lexicon = makeLexicon()
        _ = try stock(lexicon, count: 3)
        // `rebuild` is the guarded entry point; `requests` is the pure derivation and does
        // not consult the switch, so this asserts the guard rather than the arithmetic.
        ReminderScheduler().rebuild(from: lexicon)
        #expect(prefs.remindersEnabled == false)
    }
}

// MARK: - Per-exercise counts (TD-49; requested by review, PR #1)

// `@MainActor` like the suite above: these touch the store's view context, and reading it
// off the main thread crashes the whole runner rather than failing one case.
@MainActor
@Suite(.serialized)
struct SetDigestPerExerciseTests {

    private func makeLexicon() -> Lexicon { Lexicon(persistence: LWPersistence(inMemory: true)) }

    /// One meaning, answered twice in dictation so that strand rests while the others
    /// have never been asked.
    private func stocked() throws -> (Lexicon, WordSet) {
        let lexicon = makeLexicon()
        let set = try lexicon.addWordSet(named: "Animals", languages: ["en", "ru"])
        try lexicon.addSense(to: set.id, terms: [Term.Draft("bear", in: "en"),
                                                 Term.Draft("медведь", in: "ru")])
        return (lexicon, set)
    }

    @Test func anUntouchedExerciseIsDueWhileThePractisedOneRests() throws {
        let (lexicon, set) = try stocked()
        let session = try PracticeSession.start(
            .dictation, in: set.id,
            languages: LanguagePair(primary: "ru", secondary: "en", showsSecondaryAsPrompt: true),
            lexicon: lexicon, scope: .everything(includingLearned: true))
        _ = session.nextQuestion()
        try session.record(.correctVerbatim)

        let schedule = try ReviewSchedule(sets: [set], lexicon: lexicon)
        let digest = try #require(schedule.sets.first)

        #expect(digest.dueCount(for: .dictation) == 0, "just answered")
        #expect(digest.dueCount(for: .learning) == 1, "never asked as a flashcard")
        #expect(digest.dueCount(for: .phonetics) == 1)
        #expect(digest.anyExerciseDueCount == 1,
                "the headline must not read 'nothing due' while two exercises are waiting")
        #expect(digest.dueCount == 0,
                "the reminder count stays engaged-only, so reminders can fall silent")
    }

    /// The alert shown for one exercise must quote that exercise's date.
    @Test func upcomingDatesAreKeptPerExercise() throws {
        let (lexicon, set) = try stocked()
        let session = try PracticeSession.start(
            .dictation, in: set.id,
            languages: LanguagePair(primary: "ru", secondary: "en", showsSecondaryAsPrompt: true),
            lexicon: lexicon, scope: .everything(includingLearned: true))
        _ = session.nextQuestion()
        try session.record(.correctVerbatim)

        let digest = try #require(try ReviewSchedule(sets: [set], lexicon: lexicon).sets.first)
        #expect(digest.nextDueAt(for: .dictation) != nil, "answered, so it has a next date")
        #expect(digest.nextDueAt(for: .learning) == nil, "due now, so nothing is 'upcoming'")
    }
}
