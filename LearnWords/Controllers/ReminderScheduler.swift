//
//  ReminderScheduler.swift
//  LearnWords
//
//  Local reminders that words are waiting.
//
//  **Why this is not a daily alarm.** AnkiDroid — the closest thing to a reference
//  implementation — sets a plain daily alarm and computes the due count *when it fires*: a
//  `BroadcastReceiver` wakes, opens the collection, and only then decides whether to post,
//  staying silent when the count is under a threshold or the learner already studied today.
//  **iOS cannot do that.** A `UNNotificationRequest` has its content baked in at schedule
//  time and runs no code at delivery; only a *remote* push can be rewritten in flight. So
//  both of AnkiDroid's suppression paths have to move from fire time to schedule time,
//  which is what this type is.
//
//  The consequence is the design: instead of one repeating trigger that fires whether or
//  not there is work, a **rolling window of dated reminders, one per day on which the
//  schedule predicts work**, rebuilt from scratch whenever the app can see fresh state.
//  Days with nothing due get no request at all — the threshold check, moved earlier.
//
//  **Why a predicted count is honest.** Between two rebuilds a meaning's due date can only
//  arrive, never retreat: `dueAt` is fixed by the last answer, so nothing becomes *less*
//  due on its own. The count can therefore only be an under-estimate — unless the learner
//  practises, and that happens with the app open, which rebuilds the window. The one case
//  that can overshoot is another device doing the work, so `LWPersistence.storeDidChangeRemotely`
//  is a rebuild trigger too.
//
//  **Why the window ends.** Fourteen days, well under the 64-request cap iOS enforces
//  (the same class of limit that gave AnkiDroid its Samsung "too many alarms" crash). Once
//  a day is missed everything stays overdue, so a lapsed learner is reminded every day for
//  two weeks and then left alone. That is deliberate: an app that nags forever gets deleted.
//

import UIKit
import UserNotifications

final class ReminderScheduler {

    static let shared = ReminderScheduler()

    /// How far ahead reminders are scheduled. Days without predicted work are skipped, so
    /// this is a ceiling on requests, not a count of them.
    static let horizonInDays = 14

    /// Prefix for every request this type owns, so it can clear its own without touching
    /// anything else that might one day post a notification.
    private static let identifierPrefix = "review-reminder-"

    /// Routes a tapped reminder. `AppRoot` reads this rather than the raw URL so the two
    /// deep-link paths (share extension, reminder) stay in one place.
    static let practiceURL = URL(string: "learnWords://practice")!

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    // MARK: - Permission

    /// Asks for permission, and reports what the learner said.
    ///
    /// Called when the switch is turned on, never at launch: a permission sheet before the
    /// learner has asked for reminders is the request most likely to be denied, and a
    /// denial is close to permanent.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { debugLog("Notification authorization failed: \(error)") }
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// What the system currently allows. Four states, because they need four different
    /// things said about them.
    enum Standing: Equatable {
        /// Reminders will be delivered.
        case allowed
        /// Never asked. The switch may ask.
        case notAsked
        /// Refused, or later turned off in Settings. Only Settings can undo it, so the
        /// switch must not pretend otherwise.
        case blocked
        /// Authorized, but every way of showing a reminder is off — no alert, no sound, no
        /// Notification Center. Scheduling would succeed and nothing would ever appear,
        /// which is the most confusing outcome of the four and the one a bare
        /// `authorizationStatus` check misses.
        case silenced
    }

    /// Reads the live setting. **Never cached.**
    ///
    /// Apple's rule, verbatim: *"Always check your app's authorization status before
    /// scheduling local notifications. People can change your app's authorization settings
    /// at any time."*
    /// ([Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications))
    /// A status read once at launch is a guess by the time anything uses it — the learner
    /// may have been in Settings since.
    func standing(completion: @escaping (Standing) -> Void) {
        center.getNotificationSettings { settings in
            let standing: Standing
            switch settings.authorizationStatus {
            case .notDetermined:
                standing = .notAsked
            case .authorized, .provisional, .ephemeral:
                // Authorized is not the same as visible. A reminder with every presentation
                // channel disabled is scheduled, delivered, and seen by nobody.
                standing = [settings.alertSetting,
                            settings.soundSetting,
                            settings.notificationCenterSetting].contains(.enabled)
                    ? .allowed : .silenced
            default:
                standing = .blocked
            }
            DispatchQueue.main.async { completion(standing) }
        }
    }

    /// Whether reminders can actually be delivered. The switch being on is not enough.
    func isAuthorized(completion: @escaping (Bool) -> Void) {
        standing { completion($0 == .allowed || $0 == .silenced) }
    }

    /// Where to send someone whose reminders are blocked.
    ///
    /// `openNotificationSettingsURLString` lands on the app's *notification* settings
    /// rather than its general page — one fewer tap, and no hunting for the row. It is
    /// **iOS 16+** despite being documented alongside 15.4 API, so the floor keeps the
    /// general page and simply arrives one screen earlier.
    static var settingsURL: URL? {
        if #available(iOS 16.0, *) {
            return URL(string: UIApplication.openNotificationSettingsURLString)
        }
        return URL(string: UIApplication.openSettingsURLString)
    }

    // MARK: - Rebuilding the window

    /// Re-derives the window from the schedule, replacing what is pending.
    ///
    /// **Reconciles rather than clears and re-adds.** Every step runs inside one callback
    /// chain, and `add` with an existing identifier replaces that request rather than
    /// duplicating it, so there is never a moment with no reminders pending. Clearing
    /// first and adding afterwards looks equivalent and is not: the two completion
    /// handlers are independent, so the removal could land *after* the additions and
    /// delete the reminders it had just scheduled.
    ///
    /// Idempotent, which is what removes the whole class of duplicate-notification bugs
    /// AnkiDroid needed a delivery flag and a mutex to close: there is no state to get out
    /// of step, because the pending set is derived, never incremented.
    func rebuild(from lexicon: Lexicon, now: Date = Date()) {
        guard LWUserDefaults.standard.remindersEnabled else { return clear() }

        // Every step below is an async round trip to another process. Backgrounding — and
        // especially a CloudKit push that wakes the app for a moment — can suspend us
        // between them, leaving the reminders half-rebuilt until the next launch. A task
        // assertion buys the few hundred milliseconds needed to finish.
        var assertion: UIBackgroundTaskIdentifier = .invalid
        assertion = UIApplication.shared.beginBackgroundTask(withName: "Rebuild reminders") {
            UIApplication.shared.endBackgroundTask(assertion)
            assertion = .invalid
        }
        func done() {
            guard assertion != .invalid else { return }
            UIApplication.shared.endBackgroundTask(assertion)
            assertion = .invalid
        }

        isAuthorized { [weak self] authorized in
            guard let self else { return done() }
            guard authorized else { self.clear(); return done() }
            guard let schedule = try? ReviewSchedule(lexicon: lexicon, now: now) else { return done() }

            let wanted = self.requests(for: schedule, now: now)
            let keep = Set(wanted.map(\.identifier))

            self.center.getPendingNotificationRequests { pending in
                // Days that no longer have work, and yesterday's requests.
                let stale = pending.map(\.identifier)
                    .filter { $0.hasPrefix(Self.identifierPrefix) && !keep.contains($0) }
                if !stale.isEmpty {
                    self.center.removePendingNotificationRequests(withIdentifiers: stale)
                }
                let group = DispatchGroup()
                for request in wanted {
                    group.enter()
                    self.center.add(request) { error in
                        if let error { debugLog("Could not schedule a reminder: \(error)") }
                        group.leave()
                    }
                }
                group.notify(queue: .main, execute: done)
            }
        }
    }

    /// When the next reminder will fire, and how many are queued behind it.
    ///
    /// Exists because the feature was otherwise unfalsifiable: nothing arrived on the first
    /// device test, and there was no way to tell whether that was a bug or the correct
    /// answer — after a practice round nothing is due for a couple of days, so a correct
    /// schedule is an *empty* one. "No reminders scheduled" is information; silence is not.
    func pending(completion: @escaping (_ next: Date?, _ count: Int) -> Void) {
        center.getPendingNotificationRequests { requests in
            let mine = requests.filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
            let next = mine
                .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
                .min()
            DispatchQueue.main.async { completion(next, mine.count) }
        }
    }

    /// Removes every pending reminder. Called when the switch goes off, and before each
    /// rebuild.
    func clear() {
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            let mine = pending.map(\.identifier)
                .filter { $0.hasPrefix(Self.identifierPrefix) }
            guard !mine.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: mine)
        }
    }

    // MARK: - Deriving the requests

    /// One request per day in the horizon that has work waiting, at the learner's chosen
    /// hour. Internal rather than private so the derivation can be tested without a
    /// notification centre — the arithmetic is the part that can be wrong.
    func requests(for schedule: ReviewSchedule, now: Date) -> [UNNotificationRequest] {
        fireDates(from: now).compactMap { fireDate in
            // Counted at the moment it will *fire*, not at the end of that day: a word
            // that comes due at 19:30 must not be promised by a 19:00 reminder.
            let count = schedule.dueCount(by: fireDate)
            guard count > 0 else { return nil }   // AnkiDroid's threshold, moved earlier

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Time to practise", comment: "Reminder title")
            content.body = reminderBody(wordCount: count)
            content.sound = .default
            content.userInfo = ["url": Self.practiceURL.absoluteString]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                     from: fireDate)
            return UNNotificationRequest(
                identifier: Self.identifierPrefix + Self.dayKey(fireDate, calendar: calendar),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }
    }

    /// Every moment in the horizon at which a reminder could fire: the chosen time of day,
    /// on each of the next `horizonInDays` days, skipping any already past.
    private func fireDates(from now: Date) -> [Date] {
        let hour = LWUserDefaults.standard.reminderHour
        let minute = LWUserDefaults.standard.reminderMinute
        let today = calendar.startOfDay(for: now)

        return (0..<Self.horizonInDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fireDate = calendar.date(bySettingHour: hour, minute: minute,
                                               second: 0, of: day),
                  fireDate > now else { return nil }
            return fireDate
        }
    }

    private func reminderBody(wordCount: Int) -> String {
        String(format: NSLocalizedString("%@ waiting for you.",
                                         comment: "Reminder body; placeholder is a word count"),
               pluralizedWordCount(wordCount))
    }

    /// A stable per-day identifier, so a rebuild replaces rather than duplicates.
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
