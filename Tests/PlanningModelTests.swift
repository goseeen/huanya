import Foundation
import AppKit
import UserNotifications

@main @MainActor
struct PlanningModelTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { guard condition() else { fatalError("FAIL: \(message)") }; count += 1 }
    static func date(_ value: String) -> Date { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.date(from: value)! }
    static func main() throws {
        var time = date("2026-10-19 11:59:30")
        let model = AppModel(preview: true, clock: { time })
        model.engine = ReminderEngine(now: time)
        let plan = PlannedBreak()
        model.editPreferences { $0.weeklyRoutineEnabled = true; $0.plannedBreaks = [plan]; $0.eyes.enabled = false; $0.water.enabled = false; $0.stretch.enabled = false }
        model.tick(idleSeconds: 0)
        check(model.prewarning?.planned?.title == plan.name, "Fixed prewarning shown independently of periodic enabled flags")
        model.takePrewarningNow()
        check(model.activeBreak?.duration == 300 && model.activeBreak?.planned == true && model.reminderTitle(.stretch) == plan.name, "Fixed prewarning starts correct named duration directly")
        model.finishReminder(); check(model.today.breakCount == 0, "Early finish rejected")
        time = time.addingTimeInterval(300); model.finishReminder()
        check(model.today.stretches == 1 && model.today.breakSeconds == 300 && model.todayEvents.first?.label == plan.name && model.todayEvents.first?.origin == .confirmed, "Named completion has provenance and correct statistics")
        check(model.engine.saved.stretchCycle == 0, "Fixed rest does not advance long-rest cycle")
        check(model.plannedReminder == nil && model.activeBreak == nil, "Fixed context cleaned up after completion")
        // A scheduled reminder may fire at noon outside the weekly work window.
        time = date("2026-10-20 11:59:59"); model.engine = ReminderEngine(saved: model.engine.saved, now: time)
        time = time.addingTimeInterval(1); model.tick(idleSeconds: 0)
        check(model.plannedReminder?.title == plan.name && model.currentReminder == .stretch && !model.preferences.allows(time), "Noon floating reminder works in excluded lunch window")
        model.editPreferences { $0.waterML = 350 }
        check(model.currentReminder == .stretch, "Other preference edits retain planned rest with periodic stretch disabled")
        var presented = 0
        model.presentReminder = { presented += 1 }
        model.startBreak()
        model.setSessionInactive(true)
        let beforeUnlock = presented
        model.setSessionInactive(false)
        check(model.activeBreak?.planned == true && presented == beforeUnlock + 1, "Active fixed lunch rest reappears after unlock outside work schedule")
        model.snoozeCurrent()
        check(model.currentReminder == nil && model.plannedReminder == nil, "Snooze closes fixed context")
        for _ in 0..<299 { time = time.addingTimeInterval(1); model.tick(idleSeconds: 0) }
        check(model.currentReminder == nil, "No early fixed snooze")
        time = time.addingTimeInterval(1); model.tick(idleSeconds: 0)
        check(model.plannedReminder?.title == plan.name && model.reminderDuration(.stretch) == 300, "Snoozed fixed reminder preserves metadata")
        model.skipReminder()
        check(model.currentReminder == nil && model.engine.saved.stretchCycle == 0, "Skipped fixed rest neither confirms nor advances cycle")
        time = time.addingTimeInterval(1); model.tick(idleSeconds: 0)
        check(model.plannedReminder == nil, "Skipped occurrence not shown twice")
        // Inactivity clears a not-started plan and its UI context, not a confirmed active rest.
        time = date("2026-10-21 12:00:00"); model.engine = ReminderEngine(saved: model.engine.saved, now: time); model.tick(idleSeconds: 0)
        check(model.plannedReminder != nil, "Next day can offer same rule once")
        model.setSessionInactive(true)
        check(model.currentReminder == nil && model.plannedReminder == nil, "Lock clears unstarted context")
        model.setSessionInactive(false)
        model.trigger(.stretch)
        check(model.reminderTitle(.stretch) == ReminderKind.stretch.title, "Normal reminder does not inherit stale planned title")
        model.dismissReminder(snooze: false)
        // Fixed system notifications carry exactly the same plan identity/duration.
        time = date("2026-10-22 11:59:30"); model.engine = ReminderEngine(saved: model.engine.saved, now: time)
        model.editPreferences { $0.floatingReminder = false }
        let requests = model.notificationRequests(at: time)
        let normal = requests.first { ($0.content.userInfo["prewarning"] as? Bool) == false && $0.content.userInfo["planned"] != nil }!
        let warning = requests.first { ($0.content.userInfo["prewarning"] as? Bool) == true && $0.content.userInfo["planned"] != nil }
        check(warning == nil, "Already-current prewarning is not scheduled in the past")
        check(normal.content.title.contains(plan.name), "System title uses fixed plan name")
        let payload = normal.content.userInfo["planned"] as! String
        model.handleNotification(kinds: [.stretch], action: "rest", isPrewarning: true, plannedPayload: payload)
        check(model.activeBreak?.duration == plan.durationSeconds && model.activeBreak?.planned == true, "System action starts identical fixed rest")
        model.dismissReminder(snooze: false)
        model.handleNotification(kinds: [.stretch], action: "rest", plannedPayload: payload)
        check(model.activeBreak == nil, "Repeated notification action cannot re-offer claimed occurrence")
        // Stale notifications must not resurrect a changed or deleted plan.
        time = date("2026-10-23 11:59:00"); model.engine = ReminderEngine(saved: model.engine.saved, now: time)
        let future = model.notificationRequests(at: time).first { $0.content.userInfo["planned"] != nil }!
        let oldPayload = future.content.userInfo["planned"] as! String
        model.editPreferences { $0.plannedBreaks[0].durationSeconds = 600 }
        let revised = model.notificationRequests(at: time).first { $0.content.userInfo["planned"] != nil }!
        check(revised.identifier != future.identifier, "Editing fixed content replaces queued system request even when delivery time is unchanged")
        time = time.addingTimeInterval(60)
        model.handleNotification(kinds: [.stretch], action: "rest", plannedPayload: oldPayload)
        check(model.activeBreak == nil, "Changed-duration notification rejected")
        model.editPreferences { $0.plannedBreaks = [] }
        check(model.notificationRequests(at: time).allSatisfy { $0.content.userInfo["planned"] == nil }, "Deleted plan cancels future requests")
        // Long rests retain selected duration even if preferences change mid-rest.
        time = date("2026-10-23 14:00:00"); model.engine = ReminderEngine(now: time)
        model.editPreferences { $0.longBreak.enabled = true; $0.longBreak.every = 2; $0.longBreak.durationSeconds = 180 }
        model.trigger(.stretch); model.startBreak(); time = time.addingTimeInterval(60); model.finishReminder()
        check(model.engine.saved.stretchCycle == 1 && model.reminderDuration(.stretch) == 180, "After one confirmed stretch, second is long")
        model.trigger(.stretch); model.startBreak()
        check(model.activeBreak?.duration == 180 && model.activeBreak?.label == "起身长休息", "Long-rest title/duration consistent")
        model.editPreferences { $0.longBreak.durationSeconds = 900 }
        check(model.activeBreak?.duration == 180, "Running break duration is stable")
        time = time.addingTimeInterval(180); model.finishReminder()
        check(model.today.stretches == 2 && model.today.breakSeconds == 240, "Rest counted once at actual chosen duration")
        let event = model.todayEvents.first!
        let before = model.engine.deadlines
        check(model.correctRecord(event.id, amount: 120), "Model correction succeeds")
        check(model.today.breakSeconds == 180 && model.engine.deadlines == before, "Correction updates overview without resetting intervals")
        check(model.correctRecord(event.id, amount: nil) && model.todayEvents.count == 1, "Voided event hidden from dashboard")
        check(model.correctRecord(event.id, amount: 180) && model.todayEvents.count == 2, "Restored event returns to dashboard")
        // Observed reasons stay generic; the actual app name is never persisted.
        let app = BusyApplication(bundleIdentifier: "test.private.meeting", name: "Private Meeting Name")
        model.editPreferences { $0.busyApplications = [app] }
        model.updateForegroundApplication(app); model.updateForegroundApplication(nil)
        check(model.engine.saved.timingEvents.prefix(2).map(\.reason) == [.foregroundEnd, .foregroundStart], "Foreground transitions have generic explanations")
        let encodedReasons = String(data: try JSONEncoder().encode(model.engine.saved.timingEvents), encoding: .utf8)!
        check(!encodedReasons.contains(app.name) && !encodedReasons.contains(app.bundleIdentifier), "Timing history contains no application names or identifiers")
        print("PASS: \(count) planning model assertions — fixed floating/system notifications, prewarning, snooze, duplicate/stale rejection, long-rest confirmation, correction, generic history")
    }
}
