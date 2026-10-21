import Foundation
import UserNotifications
import AppKit

@MainActor
final class MockLoginManager: LoginItemManaging {
    var status: LoginItemStatus = .disabled
    var result: LoginItemStatus = .enabled
    var fail = false
    var registrations = 0
    var removals = 0
    func register() throws {
        registrations += 1
        if fail { throw NSError(domain: "RiseUpTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test registration failure"]) }
        status = result
    }
    func unregister() throws { removals += 1; status = .disabled }
    func openSettings() {}
}

@main
@MainActor
struct AppModelTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        count += 1
    }
    static func main() {
        let start = Date(timeIntervalSince1970: 1792029600)
        var time = start
        let login = MockLoginManager()
        let model = AppModel(preview: true, clock: { time }, loginManager: login)
        check(login.registrations == 0 && !model.launchAtLoginStatus.isSelected, "Launch at login stays opt-in")
        model.setLaunchAtLogin(true)
        check(login.registrations == 1 && model.launchAtLoginStatus == .enabled, "Opt-in registers through system adapter")
        model.setLaunchAtLogin(false)
        check(login.removals == 1 && model.launchAtLoginStatus == .disabled, "Opt-out unregisters")
        login.result = .requiresApproval
        model.setLaunchAtLogin(true)
        check(model.launchAtLoginStatus == .requiresApproval && model.notice != nil, "Pending system approval is shown accurately")
        model.setLaunchAtLogin(false)
        login.fail = true
        model.setLaunchAtLogin(true)
        check(model.launchAtLoginStatus == .disabled, "Registration failure does not falsely show enabled")
        login.status = .enabled
        model.refreshLoginStatus()
        check(model.launchAtLoginStatus == .enabled, "System changes are reflected")
        let preview = AppModel(preview: true)
        preview.setLaunchAtLogin(true)
        check(preview.launchAtLoginStatus == .disabled, "Visual preview never alters real login items")

        var state = SavedState()
        state.preferences.water.intervalMinutes = 1
        state.preferences.eyes.intervalMinutes = 2
        state.preferences.stretch.intervalMinutes = 3
        state.preferences.eyes.durationSeconds = 10
        state.preferences.stretch.durationSeconds = 10
        model.engine = ReminderEngine(saved: state, now: time)
        var warnings = 0
        var popups = 0
        model.presentPrewarning = { warnings += 1 }
        model.presentReminder = { popups += 1 }
        for second in 1...29 { time = start.addingTimeInterval(Double(second)); model.tick(idleSeconds: 0) }
        check(model.prewarning == nil && warnings == 0, "No premature warning")
        time = start.addingTimeInterval(30); model.tick(idleSeconds: 0)
        check(model.prewarning?.kinds == ReminderKind.allCases && warnings == 1, "One advance warning for a grouped reminder")
        time = start.addingTimeInterval(31); model.tick(idleSeconds: 0)
        check(warnings == 1, "Prewarning does not re-open every tick")
        model.dismissPrewarning()
        time = start.addingTimeInterval(32); model.tick(idleSeconds: 0)
        check(model.prewarning == nil, "Closing a warning keeps it closed for that deadline")
        for second in 33...60 { time = start.addingTimeInterval(Double(second)); model.tick(idleSeconds: 0) }
        check(model.reminderKinds == ReminderKind.allCases && popups == 1, "All grouped items use one popup")
        check(model.today.breakCount == 0 && model.today.waterML == 0, "Popup appearance never counts completion")
        model.logWater(amount: 150)
        check(model.today.waterML == 150 && model.reminderKinds == [.eyes, .stretch], "Water confirmation leaves other reminders pending")
        model.startBreak(.eyes)
        model.finishReminder(.eyes)
        check(model.today.eyeBreaks == 0, "Early confirmation rejected")
        model.startBreak(.stretch)
        check(model.activeBreak?.kind == .eyes, "A second break cannot double-count overlapping time")
        for second in 61...70 { time = start.addingTimeInterval(Double(second)); model.tick(idleSeconds: 0) }
        model.finishReminder(.eyes)
        check(model.today.eyeBreaks == 1 && model.today.stretches == 0, "Completing eyes does not complete stretch")
        check(model.reminderKinds == [.stretch], "Remaining item stays in the same popup")
        model.startBreak(.stretch)
        for second in 71...80 { time = start.addingTimeInterval(Double(second)); model.tick(idleSeconds: 0) }
        model.finishReminder(.stretch)
        check(model.today.breakCount == 2 && model.today.breakSeconds == 20, "Separate timed confirmations record exact durations")
        check(model.reminderKinds.isEmpty && !model.engine.onBreak, "Panel clears after all confirmations")
        model.editPreferences { $0.waterML = 500 }
        model.undoWater()
        check(model.today.waterML == 0 && model.today.waterCount == 0 && !model.canUndoWater, "UI undo removes the selected cup, once")

        model.trigger(kinds: [.water, .eyes, .stretch])
        model.snooze(.water)
        check(model.reminderKinds == [.eyes, .stretch], "Per-item snooze leaves other items visible")
        model.snoozeCurrent()
        check(model.reminderKinds.isEmpty && !model.engine.onBreak, "All-item snooze closes the group")

        time = start.addingTimeInterval(100)
        model.engine = ReminderEngine(saved: state, now: time)
        model.tick(idleSeconds: 180)
        check(model.engine.idle && model.nextBatch == nil && model.prewarning == nil, "Idle suppresses reminders and warnings")
        time = time.addingTimeInterval(1); model.tick(idleSeconds: 0)
        check(!model.engine.idle && model.countdown == "01:00", "Returning starts a fresh earliest interval")
        model.togglePause()
        model.tick(idleSeconds: 180)
        model.tick(idleSeconds: 0)
        check(model.engine.paused, "Activity does not cancel a deliberate pause")
        model.togglePause()
        model.setSessionInactive(true)
        check(model.engine.idle && model.sessionLocked, "Screen lock pauses immediately")
        model.setSessionInactive(false)
        check(!model.engine.idle && !model.sessionLocked, "Screen unlock resumes")

        model.editPreferences { $0.floatingReminder = false; $0.waterML = 500 }
        var requests = model.notificationRequests(at: time)
        check(requests.count == 2, "System mode schedules one merged reminder and one prewarning")
        let warning = requests.first { $0.content.userInfo["prewarning"] as? Bool == true }!
        let actual = requests.first { $0.content.userInfo["prewarning"] as? Bool == false }!
        check((warning.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 30, "System prewarning has the expected lead time")
        check(warning.content.sound == nil && actual.content.sound != nil, "Prewarning is silent; reminder follows sound preference")
        check((actual.content.userInfo["kinds"] as? [String])?.count == 3, "System notification preserves group membership")
        model.editPreferences { $0.sound = false }
        let muted = model.notificationRequests(at: time).first { $0.content.userInfo["prewarning"] as? Bool == false }!
        check(muted.content.sound == nil && muted.identifier != actual.identifier, "Changing sound replaces an already scheduled notification")
        model.editPreferences { $0.prewarningEnabled = false }
        check(model.notificationRequests(at: time).count == 1, "Prewarning can be turned off")
        model.tick(idleSeconds: 180)
        requests = model.notificationRequests(at: time)
        check(requests.isEmpty, "Idle cancels all system notification plans")
        model.tick(idleSeconds: 0)
        model.handleNotification(kinds: [.water, .eyes], action: "rest")
        check(model.reminderKinds == [.water, .eyes] && model.activeBreak == nil, "Grouped notification opens separate confirmation controls")
        model.dismissReminder(snooze: false)
        model.handleNotification(kinds: [.water], action: "water")
        check(model.today.waterML == 500, "System water action records the configured default amount")

        let idle = SystemActivity.idleSeconds()
        check(idle.isFinite && idle >= 0, "Native aggregate idle-time API returns a valid reading")
        check(!SystemActivity.isLoginLaunch(nil), "A normal launch is not mistaken for login launch")
        let loginEvent = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        loginEvent.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        check(SystemActivity.isLoginLaunch(loginEvent), "Login AppleEvent starts in the background")
        secondBatchTests(start: start)
        stretchRotationTests(start: start)
        customDurationTests(start: start)
        usageSessionTests()
        print("PASS: \(count) integration assertions — grouped UI, prewarnings, inactivity, notifications, busy mode, foreground apps, interactions, cards, menu status, shortcuts")
    }

    static func customDurationTests(start: Date) {
        for kind in [ReminderKind.eyes, .stretch] {
            var time = start
            let model = AppModel(preview: true, clock: { time })
            model.engine = ReminderEngine(saved: SavedState(), now: time)
            model.editPreferences { $0[kind].durationSeconds = 180 }
            model.trigger(kind)
            model.startBreak(kind)
            check(model.activeBreak?.duration == 180 && model.breakRemaining == 180, "Custom \(kind) break starts at three minutes")
            for second in 1...179 {
                time = start.addingTimeInterval(Double(second))
                model.tick(idleSeconds: 0)
                if second == 30 { model.editPreferences { $0[kind].durationSeconds = 60 } }
            }
            check(model.breakRemaining == 1, "Changing next duration does not shorten an active \(kind) break")
            model.finishReminder(kind)
            check(model.today.breakCount == 0, "Custom \(kind) break cannot be completed early")
            time = start.addingTimeInterval(180)
            model.tick(idleSeconds: 0)
            check(model.breakRemaining == 0 && model.today.breakCount == 0, "Custom \(kind) countdown waits for confirmation")
            model.finishReminder(kind)
            check(model.today.breakCount == 1 && model.today.breakSeconds == 180, "Custom \(kind) completion records the full original duration")
            check(model.engine.saved.events.last?.amount == 180, "Custom \(kind) activity retains its exact duration")
        }
    }

    static func secondBatchTests(start: Date) {
        var time = start
        let model = AppModel(preview: true, clock: { time })
        var state = SavedState()
        state.preferences.water.intervalMinutes = 1
        state.preferences.eyes.enabled = false
        state.preferences.stretch.enabled = false
        model.engine = ReminderEngine(saved: state, now: time)
        var popups = 0
        var hidden = 0
        model.presentReminder = { popups += 1 }
        model.hideReminder = { hidden += 1 }
        model.trigger(.water)
        model.startBusy(minutes: 30)
        check(model.reminderKinds.isEmpty && hidden > 0 && model.engine.busyUntil == start.addingTimeInterval(1800), "Busy button dismisses pending panel and sets exact thirty minutes")
        check(model.today.remindersSnoozed == 0 && model.today.remindersSkipped == 0, "Busy cancellation does not imply snooze or ignore")
        check(model.menuBarText == "忙碌 30:00" && model.nextBatch == nil, "Menu accurately shows busy countdown")
        for second in 1...1799 { time = start.addingTimeInterval(Double(second)); model.tick(idleSeconds: 0) }
        check(popups == 1 && model.today.workSeconds == 0, "Busy mode adds no work or popups")
        time = start.addingTimeInterval(1800); model.tick(idleSeconds: 0)
        check(!model.hasManualPause && model.countdown == "01:00" && model.menuBarText == "01:00", "Busy auto-resume updates countdown with full interval")
        for second in 1801...1860 { time = start.addingTimeInterval(Double(second)); model.tick(idleSeconds: 0) }
        check(model.reminderKinds == [.water] && model.today.remindersDue == 1, "Due stats recorded for actual eligible reminder")
        for second in 1861...1920 { time = start.addingTimeInterval(Double(second)); model.tick(idleSeconds: 0) }
        check(model.today.remindersDue == 1 && popups == 2, "Unanswered floating reminder is not counted repeatedly")
        model.snoozeCurrent()
        check(model.today.remindersSnoozed == 1 && model.reminderKinds.isEmpty, "Close/snooze records a deliberate snooze")
        model.snoozeCurrent()
        check(model.today.remindersSnoozed == 1, "Closing an already empty panel cannot count again")
        model.trigger(kinds: [.water, .eyes, .stretch])
        model.skipReminder(.eyes)
        check(model.reminderKinds == [.water, .stretch] && model.today.remindersSkipped == 1, "Per-item skip preserves other grouped reminders")
        model.skipReminder()
        check(model.reminderKinds.isEmpty && model.today.remindersSkipped == 3 && model.today.breakCount == 0, "Skip group counts each item without completing breaks")
        model.trigger(.water)
        let snoozes = model.today.remindersSnoozed
        model.dismissReminder(snooze: true, recordInteraction: false)
        check(model.today.remindersSnoozed == snoozes, "Sleep deferral is not recorded as a user snooze")

        model.togglePause()
        model.startBusy(minutes: 60)
        check(model.engine.paused && model.engine.busyUntil == time.addingTimeInterval(3600), "Sixty-minute busy timer preserves manual pause")
        model.endBusy()
        check(model.engine.paused && model.engine.busyUntil == nil, "End busy leaves independent manual pause intact")
        model.resumeReminders()
        model.engine = ReminderEngine(saved: model.engine.saved, now: time)
        let app = BusyApplication(bundleIdentifier: "test.presentation", name: "演示应用")
        model.editPreferences { $0.busyApplications = [app] }
        model.trigger(.water)
        model.updateForegroundApplication(app)
        check(model.engine.foregroundBlocked && model.reminderKinds.isEmpty && model.status.contains("演示应用"), "Selected foreground app quietly cancels pending panel")
        let before = model.today.workSeconds
        time = time.addingTimeInterval(1); model.tick(idleSeconds: 0)
        check(model.today.workSeconds == before && model.nextBatch == nil && model.menuBarText == "忙碌", "App pause stops work, notifications and countdown")
        model.startBusy(minutes: 30)
        model.endBusy()
        check(model.engine.foregroundBlocked && model.nextBatch == nil, "Ending timer does not bypass a foreground rule")
        model.updateForegroundApplication(BusyApplication(bundleIdentifier: "test.other", name: "Other"))
        check(!model.engine.foregroundBlocked && model.countdown == "01:00", "Leaving selected application starts a fresh interval")
        model.togglePause()
        model.updateForegroundApplication(app)
        model.updateForegroundApplication(nil)
        check(model.engine.paused, "App switching does not undo manual pause")
        model.resumeReminders()
        model.updateForegroundApplication(app)
        model.editPreferences { $0.busyApplications = [] }
        check(!model.engine.foregroundBlocked, "Removing current app rule resumes immediately")

        model.trigger(.stretch)
        let firstCard = model.stretchCard
        model.cycleStretchCard()
        check(model.stretchCard != firstCard && model.today.breakCount == 0, "Changing guide never completes a break")
        model.dismissReminder(snooze: false)
        model.trigger(.stretch)
        check(model.stretchCard.rawValue == (firstCard.rawValue + 1) % 3, "Successive stretch reminders rotate themes")
        model.quickRest()
        check(model.activeBreak?.kind == .stretch && model.menuBarText == "休息 01:00", "Quick rest starts real break countdown")
        model.cycleStretchCard()
        check(model.activeBreak?.duration == 60, "Changing guide preserves running timer")
        model.dismissReminder(snooze: false)
        model.editPreferences { $0.floatingReminder = false }
        model.updateForegroundApplication(app)
        model.editPreferences { $0.busyApplications = [app] }
        check(model.notificationRequests(at: time).isEmpty, "Foreground pause suppresses system requests too")
        model.editPreferences { $0.busyApplications = [] }
        model.startBusy(minutes: 30)
        check(model.notificationRequests(at: time).isEmpty, "Busy timer suppresses system requests")
        model.endBusy()
        check(!model.notificationRequests(at: time).isEmpty, "Ending busy rebuilds system plans")
        model.applyShortcutPreference()
        check(model.shortcutStatus.contains("预览"), "Preview mode never registers global shortcuts")
        model.engine = ReminderEngine(saved: state, now: time)
        for _ in 1...60 { time = time.addingTimeInterval(1); model.tick(idleSeconds: 0) }
        check(model.today.remindersDue == 1, "Floating automatic reminder eligibility tracked")
        model.dismissReminder(snooze: false)
        model.engine = ReminderEngine(saved: state, now: time)
        model.editPreferences { $0.floatingReminder = false }
        for _ in 1...60 { time = time.addingTimeInterval(1); model.tick(idleSeconds: 0) }
        check(model.today.remindersDue == 0, "Unauthorized system notifications do not inflate reminder counts")
    }

    static func usageSessionTests() {
        let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1792108800))
        var time = midnight.addingTimeInterval(-100)
        let model = AppModel(preview: true, clock: { time })
        model.engine = ReminderEngine(now: time)
        for _ in 0..<40 { time = time.addingTimeInterval(1); model.tick(idleSeconds: 0) }
        check(model.engine.sittingSeconds == 40, "Dashboard estimates this round from active use")
        model.setSessionInactive(true, source: "display")
        model.setSessionInactive(true, source: "lock")
        for _ in 0..<70 { time = time.addingTimeInterval(1); model.tick(idleSeconds: 0) }
        check(model.engine.sittingSeconds == 0 && model.sessionLocked, "New day clears dashboard even with multiple inactive sources")
        model.setSessionInactive(false, source: "display")
        check(model.engine.idle && model.sessionLocked, "Display wake alone does not override remaining lock")
        model.setSessionInactive(false, source: "lock")
        time = time.addingTimeInterval(1); model.tick(idleSeconds: 0)
        check(model.engine.sittingSeconds == 1 && model.today.workSeconds == 1 && model.today.longestSittingSeconds == 1, "Morning dashboard and daily total both start fresh after unlock")
        model.togglePause()
        model.setSessionInactive(true)
        for _ in 0..<301 { time = time.addingTimeInterval(1); model.tick(idleSeconds: 0) }
        model.setSessionInactive(false)
        check(model.engine.sittingSeconds == 0 && model.engine.paused, "Long lock resets dashboard while preserving manual pause")
        check(model.today.breakCount == 0 && model.today.waterCount == 0 && model.engine.saved.events.isEmpty, "No synthetic drink or completed break is added after return")
        model.resumeReminders()
        time = time.addingTimeInterval(1); model.tick(idleSeconds: 0)
        check(model.engine.sittingSeconds == 1, "Manual resume begins a fresh post-absence round")
        model.stoodUp()
        check(model.engine.sittingSeconds == 0 && model.notice == "已重置本轮使用时长。", "Standing action resets the renamed estimate")
    }

    static func stretchRotationTests(start: Date) {
        var time = start
        let model = AppModel(preview: true, clock: { time })
        var state = SavedState()
        state.preferences.water.enabled = false
        state.preferences.eyes.enabled = false
        state.preferences.stretch.intervalMinutes = 180
        state.preferences.stretch.durationSeconds = 120
        model.engine = ReminderEngine(saved: state, now: time)
        func advance(_ seconds: Int) {
            for _ in 0..<seconds { time = time.addingTimeInterval(1); model.tick(idleSeconds: 0) }
        }
        model.trigger(.stretch)
        let first = model.stretchCard
        advance(19)
        check(model.stretchCard == first, "Guide remains readable for nineteen seconds")
        advance(1)
        check(model.stretchCard.rawValue == (first.rawValue + 1) % 3, "Visible guide automatically rotates at twenty seconds")
        advance(5)
        model.cycleStretchCard()
        let manual = model.stretchCard
        advance(19)
        check(model.stretchCard == manual, "Manual arrow restarts a full twenty-second reading period")
        advance(1)
        check(model.stretchCard.rawValue == (manual.rawValue + 1) % 3, "Automatic rotation resumes after manual selection")
        check(model.today.breakCount == 0 && model.activeBreak == nil, "Guide rotation alone never starts or records a break")
        model.startBreak(.stretch)
        let active = model.activeBreak!
        let startCard = model.stretchCard
        advance(60)
        check(model.stretchCard == startCard, "Three automatic changes wrap through all themes during a break")
        check(model.activeBreak?.endsAt == active.endsAt && model.activeBreak?.duration == 120 && model.breakRemaining == 60, "Automatic card changes preserve the original countdown")
        advance(59)
        let last = model.stretchCard
        advance(21)
        check(model.stretchCard == last && model.breakRemaining == 0 && model.today.stretches == 0, "Rotation stops at timer completion without confirming the break")
        model.finishReminder(.stretch)
        check(model.today.stretches == 1 && model.today.breakSeconds == 120, "Only explicit confirmation records the original break duration")
        let closed = model.stretchCard
        advance(25)
        check(model.stretchCard == closed, "Closing the stretch panel stops rotation")

        model.trigger(.stretch)
        model.startBreak(.stretch)
        advance(10)
        let beforeLock = model.stretchCard
        model.setSessionInactive(true)
        advance(40)
        check(model.stretchCard == beforeLock, "Hidden lock-screen time does not rotate cards")
        model.setSessionInactive(false)
        advance(19)
        check(model.stretchCard == beforeLock, "Returning from lock gives a full reading period")
        advance(1)
        check(model.stretchCard != beforeLock, "Automatic rotation resumes after unlock")
        model.editPreferences { $0.stretchCardsEnabled = false }
        let disabled = model.stretchCard
        advance(25)
        check(model.stretchCard == disabled, "Disabling guide cards stops automatic rotation")
        model.editPreferences { $0.stretchCardsEnabled = true }
        advance(19)
        check(model.stretchCard == disabled, "Re-enabled guide does not switch early")
        advance(1)
        check(model.stretchCard != disabled, "Re-enabled guide resumes twenty-second rotation")
        model.dismissReminder(snooze: false)
        model.trigger(.stretch)
        let beforeGap = model.stretchCard
        time = time.addingTimeInterval(120)
        model.tick(idleSeconds: 0)
        check(model.stretchCard == beforeGap, "Process suspension does not skip unseen cards")
        advance(19)
        check(model.stretchCard == beforeGap, "After a suspension the current card gets a new full interval")
        advance(1)
        check(model.stretchCard != beforeGap, "Rotation resumes normally after suspended time")
        model.snoozeCurrent()
        let snoozed = model.stretchCard
        advance(30)
        check(model.stretchCard == snoozed, "Snoozed panels stop rotating")

        model.trigger(kinds: [.water, .stretch])
        let grouped = model.stretchCard
        advance(20)
        check(model.stretchCard != grouped && model.reminderKinds == [.water, .stretch], "Combined reminders also rotate without altering pending items")
        model.skipReminder(.stretch)
        let removed = model.stretchCard
        advance(25)
        check(model.stretchCard == removed && model.reminderKinds == [.water], "Removing stretch from a group stops its rotation")
    }
}
