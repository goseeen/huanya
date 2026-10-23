import Foundation

@main
struct PlanningTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }; count += 1
    }
    static func date(_ text: String) -> Date { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.date(from: text)! }
    static func tick(_ e: inout ReminderEngine, start: Date, seconds: Int, idle: Double? = nil) {
        for second in 1...seconds { let now = start.addingTimeInterval(Double(second)); if let idle { _ = e.updateIdle(secondsSinceInput: idle + Double(second), now: now) }; _ = e.advance(now: now) }
    }
    static func main() throws {
        let monday = date("2026-10-19 09:00:00")
        var p = Preferences(); p.weeklyRoutineEnabled = true
        check(p.allows(monday), "Morning opens inclusive")
        check(p.allows(date("2026-10-19 11:59:59")), "Morning before noon")
        check(!p.allows(date("2026-10-19 12:00:00")), "Noon excluded")
        check(!p.allows(date("2026-10-19 12:59:59")), "Lunch excluded")
        check(p.allows(date("2026-10-19 13:00:00")), "Afternoon resumes")
        check(!p.allows(date("2026-10-19 18:00:00")), "End excluded")
        check(!p.allows(date("2026-10-24 10:00:00")), "Weekend closed")
        p.weeklyRoutine[1].windows = [WorkWindow(start: 10 * 60, end: 15 * 60)]
        check(!p.allows(date("2026-10-20 09:00:00")) && p.allows(date("2026-10-20 12:30:00")), "Tuesday has independent routine")
        var bad = WeekdayRoutine.standard; bad[0].windows.append(WorkWindow(start: 11 * 60, end: 14 * 60))
        check(WeekdayRoutine.error(bad) != nil, "Overlap rejected")
        bad = WeekdayRoutine.standard; bad[0].windows = [WorkWindow(start: 22 * 60, end: 3 * 60)]
        check(WeekdayRoutine.error(bad) != nil, "Overnight must be explicitly split")
        bad[0].windows = [WorkWindow(start: 22 * 60, end: 1440)]
        check(WeekdayRoutine.error(bad) == nil, "24:00 is valid end")
        bad[0].windows = [WorkWindow(start: 9 * 60, end: 12 * 60), WorkWindow(start: 12 * 60, end: 15 * 60)]
        check(WeekdayRoutine.error(bad) == nil, "Adjacent windows allowed")
        bad.removeLast(); check(WeekdayRoutine.error(bad) != nil, "Missing weekdays rejected")
        var state = SavedState(); state.preferences = p
        var e = ReminderEngine(saved: state, now: date("2026-10-19 11:59:59"))
        _ = e.advance(now: date("2026-10-19 12:00:00"))
        check(e.saved.days.isEmpty, "Lunch boundary not counted as work")
        e = ReminderEngine(saved: state, now: date("2026-10-19 12:59:59"))
        _ = e.advance(now: date("2026-10-19 13:00:00"))
        check(e.deadlines[.eyes] == date("2026-10-19 13:20:00"), "Afternoon fresh interval")
        check(e.saved.timingEvents.first?.reason == .scheduleStart, "Schedule transition explained")
        // Long breaks advance by actual confirmation only, and persist across launches.
        e = ReminderEngine(now: monday)
        p = e.saved.preferences; p.longBreak.enabled = true; p.longBreak.every = 3; p.longBreak.durationSeconds = 900
        e.updatePreferences(p, now: monday)
        e.skip(.stretch, now: monday); e.recordInteraction(.due, kind: .stretch, now: monday)
        check(!e.isLongBreak(.stretch) && e.saved.stretchCycle == 0, "Skipped/due reminders do not advance cycle")
        e.complete(.stretch, now: monday)
        check(!e.isLongBreak(.stretch), "Second stretch remains regular")
        e.complete(.stretch, now: monday)
        check(e.isLongBreak(.stretch) && e.restDuration(.stretch) == 900, "Third stretch is long")
        check(!e.isLongBreak(.eyes), "Eye rest unaffected")
        e = ReminderEngine(saved: try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(e.saved)), now: monday)
        check(e.isLongBreak(.stretch), "Cycle survives reload")
        e.complete(.stretch, now: monday, duration: 900)
        check(e.saved.stretchCycle == 0 && e.saved.days[dayKey(monday)]?.stretches == 3, "Long break counts once and begins new cycle")
        e.complete(.stretch, now: monday, duration: 300, label: "午间走走", advancesCycle: false)
        check(e.saved.stretchCycle == 0, "Fixed planned rest does not advance interval cycle")
        // Fixed breaks work during lunch, use stable per-day IDs, and never catch up old days.
        let plan = PlannedBreak()
        state = SavedState(); state.preferences.weeklyRoutineEnabled = true; state.preferences.plannedBreaks = [plan]
        let noon = date("2026-10-19 12:00:00")
        e = ReminderEngine(saved: state, now: noon)
        let occurrence = e.plannedOccurrences(at: noon).first!
        check(occurrence.dueAt == noon && e.scheduledBatches(at: noon).first?.planned?.id == occurrence.id, "Lunch fixed reminder independent of work window")
        check(e.advance(now: noon).isEmpty, "Fixed reminders do not leak into periodic due list")
        e.claimPlanned(occurrence, now: noon)
        check(!e.plannedOccurrences(at: noon).contains { $0.id == occurrence.id }, "Claim once")
        e = ReminderEngine(saved: e.saved, now: noon)
        check(!e.plannedOccurrences(at: noon).contains { $0.id == occurrence.id }, "No duplicate after relaunch")
        e.snoozePlanned(occurrence, now: noon)
        check(e.plannedOccurrences(at: noon).first?.dueAt == noon.addingTimeInterval(300), "Snooze preserves planned duration and identity")
        state = e.saved; e = ReminderEngine(saved: state, now: noon.addingTimeInterval(300))
        check(e.plannedOccurrences(at: e.lastTick).first?.title == plan.name, "Snooze persists across relaunch")
        e.setPaused(true, now: noon); check(e.plannedOccurrences(at: noon).isEmpty, "Manual pause suppresses fixed reminder")
        e.setPaused(false, now: noon.addingTimeInterval(601)); check(e.plannedOccurrences(at: e.lastTick).first?.id != occurrence.id, "Stale snooze not caught up")
        e.setForegroundBlocked(true, now: e.lastTick); check(e.scheduledBatches(at: e.lastTick).isEmpty, "Foreground app suppresses fixed reminder too")
        e = ReminderEngine(saved: state, now: noon); e.setSleeping(true, now: noon); check(e.plannedOccurrences(at: noon).isEmpty, "Sleep suppresses fixed reminders")
        e = ReminderEngine(saved: state, now: noon); _ = e.updateIdle(secondsSinceInput: 200, now: noon); check(e.plannedOccurrences(at: noon).isEmpty, "Idle suppresses fixed reminders")
        e = ReminderEngine(saved: state, now: noon); e.saved.preferences.plannedBreaks = []; check(e.plannedOccurrences(at: noon).isEmpty, "Deleted rule removes snoozed occurrence")
        check(plan.occurrence(on: date("2026-10-25 12:00:00")) == nil, "No Sunday fixed reminder")
        check(plan.occurrence(on: noon)?.id != plan.occurrence(on: date("2026-10-20 12:00:00"))?.id, "Each local day unique")
        state = SavedState(); state.preferences.plannedBreaks = [plan]
        e = ReminderEngine(saved: state, now: noon)
        e.snoozePlanned(occurrence, now: noon)
        e.saved.preferences.plannedBreaks[0].minute = 14 * 60
        check(!e.acceptsPlanned(occurrence, at: noon) && e.plannedOccurrences(at: noon).first?.dueAt == date("2026-10-19 14:00:00"), "Editing fixed time invalidates old snooze and follows new schedule")
        e = ReminderEngine(saved: state, now: noon); e.setBusy(minutes: 1, now: noon)
        check(!e.scheduledBatches(at: noon.addingTimeInterval(61)).isEmpty, "Future schedule query uses requested time for busy expiry")
        e = ReminderEngine(saved: state, now: noon)
        e.recordPlannedDue(occurrence, now: noon.addingTimeInterval(-1))
        check(e.saved.reminderEvents.isEmpty, "Prewarning take-now does not claim a due interaction early")
        e.recordPlannedDue(occurrence, now: noon); e.recordPlannedDue(occurrence, now: noon)
        e = ReminderEngine(saved: e.saved, now: noon)
        e.recordPlannedDue(occurrence, now: noon)
        check(e.saved.days[dayKey(noon)]?.remindersDue == 1, "Fixed delivery counted once even after reload and notification click")
        // Amendment keeps older aggregates, never moves deadlines, and is reversible.
        e = ReminderEngine(now: monday); e.complete(.water, now: monday, waterAmount: 250)
        let water = e.saved.events[0]; let deadlines = e.deadlines
        e.saved.days[dayKey(monday)]!.waterML += 500; e.saved.days[dayKey(monday)]!.waterCount += 2
        check(e.correctActivity(id: water.id, amount: 350, now: monday), "Amend water")
        check(e.saved.days[dayKey(monday)]!.waterML == 850 && e.saved.days[dayKey(monday)]!.waterCount == 3, "Older aggregate contributions preserved")
        check(e.deadlines == deadlines && e.waterUndo == nil, "Correction does not change timers; invalidates incompatible quick undo")
        check(e.correctActivity(id: water.id, amount: nil, now: monday), "Void retained event")
        check(e.saved.days[dayKey(monday)]!.waterML == 500 && e.saved.events[0].voidedAt != nil, "Void subtracts current contribution")
        check(!e.correctActivity(id: water.id, amount: nil, now: monday), "Cannot double-subtract")
        check(e.correctActivity(id: water.id, amount: 150, now: monday), "Restore amended value")
        check(e.saved.days[dayKey(monday)]!.waterML == 650 && e.saved.events[0].revisions?.count == 3, "Restoration and audit trail")
        let snapshot = try JSONEncoder().encode(e.saved)
        check(!e.correctActivity(id: water.id, amount: 1001, now: monday), "Invalid quantity rejected")
        check(e.saved.days[dayKey(monday)]!.waterML == 650, "Rejected edit no aggregate mutation")
        e.complete(.eyes, now: monday, duration: 20); let eyes = e.saved.events[0]
        check(e.correctActivity(id: eyes.id, amount: 180, now: monday), "Correct rest duration")
        check(e.saved.days[dayKey(monday)]!.eyeBreaks == 1 && e.saved.days[dayKey(monday)]!.breakSeconds == 180, "One rest retained with adjusted duration")
        e.saved.days[dayKey(monday)]!.breakSeconds = 0
        check(!e.correctActivity(id: eyes.id, amount: nil, now: monday), "Inconsistent old aggregate fails without data loss")
        let reloaded = try JSONDecoder().decode(SavedState.self, from: snapshot)
        check(reloaded.events[0].revisions?.count == 3 && reloaded.events[0].origin == .confirmed, "Audit and source persist")
        var stable = ReminderEngine(now: monday)
        stable.complete(.water, now: monday, waterAmount: 250)
        let stableID = stable.saved.events[0].id
        stable.saved.events[0].recordDay = "2026-10-18"
        stable.saved.days["2026-10-18"] = stable.saved.days.removeValue(forKey: dayKey(monday))
        check(stable.correctActivity(id: stableID, amount: 350, now: monday), "Correction uses original stored day after timezone changes")
        check(stable.saved.days["2026-10-18"]?.waterML == 350 && stable.saved.days[dayKey(monday)] == nil, "Historical correction cannot move contribution to a different day")
        let originalDeadline = stable.deadlines[.water]
        stable.saved.events[0].recordDay = "1999-01-01"
        check(!stable.correctActivity(id: stableID, amount: nil, now: monday) && stable.deadlines[.water] == originalDeadline, "Unknown original aggregate rejects correction safely")
        // Legacy data remains readable, with honest unknown provenance.
        let legacy = try JSONDecoder().decode(SavedState.self, from: Data("{\"version\":1,\"events\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"date\":0,\"kind\":\"water\",\"amount\":250}]}".utf8))
        check(!legacy.preferences.weeklyRoutineEnabled && !legacy.preferences.longBreak.enabled && legacy.preferences.plannedBreaks.isEmpty, "New features opt-in for old state")
        check(legacy.events[0].origin == nil && legacy.events[0].voidedAt == nil, "Legacy source not fabricated")
        // Natural absences are conservative observed segments, never completed rests.
        e = ReminderEngine(now: monday); _ = e.updateIdle(secondsSinceInput: 181, now: monday)
        tick(&e, start: monday, seconds: 90, idle: 181)
        _ = e.updateIdle(secondsSinceInput: 0, now: monday.addingTimeInterval(91))
        check(e.saved.timingEvents.filter { $0.reason == .naturalAway }.count == 1, "One return creates one natural absence")
        check(e.saved.events.isEmpty && e.saved.days.values.allSatisfy { $0.breakCount == 0 }, "Absence never creates confirmed rest")
        _ = e.updateIdle(secondsSinceInput: 0, now: monday.addingTimeInterval(92)); check(e.saved.timingEvents.filter { $0.reason == .naturalAway }.count == 1, "Return not repeatedly recorded")
        e = ReminderEngine(now: monday); _ = e.updateIdle(secondsSinceInput: 181, now: monday)
        _ = e.updateIdle(secondsSinceInput: 0, now: monday.addingTimeInterval(3600)); check(!e.saved.timingEvents.contains { $0.reason == .naturalAway }, "Unobserved gap never inferred as natural rest")
        e = ReminderEngine(now: monday); _ = e.updateIdle(secondsSinceInput: 181, now: monday); e.setSleeping(true, now: monday); e.setSleeping(false, now: monday.addingTimeInterval(3600))
        _ = e.updateIdle(secondsSinceInput: 0, now: monday.addingTimeInterval(3601)); check(!e.saved.timingEvents.contains { $0.reason == .naturalAway }, "Sleep excluded from natural absence")
        e = ReminderEngine(now: monday); e.setForegroundBlocked(true, now: monday); for _ in 0..<20 { e.setForegroundBlocked(true, now: monday) }; e.setForegroundBlocked(false, now: monday)
        check(e.saved.timingEvents.map(\.reason) == [.foregroundEnd, .foregroundStart], "Reason history logs transitions, not every sample")
        // Period calculations use Monday weeks, actual month lengths, paired complete days.
        var days: [String:DayRecord] = ["2026-10-19": DayRecord(waterML: 500), "2026-10-12": DayRecord(waterML: 250), "2026-10-20": DayRecord(waterML: 1000), "2026-10-23": DayRecord(waterML: 2000)]
        let friday = date("2026-10-23 11:00:00")
        var review = PeriodReview(kind: .week, offset: 0, now: friday, days: days)
        check(dayKey(review.start) == "2026-10-19" && review.dates.count == 7, "Week starts Monday")
        check(review.total.waterML == 3500 && review.matchedDays == 1 && review.comparableTotal.waterML == 500 && review.previousTotal.waterML == 250, "Current total includes today; comparison uses only paired complete days")
        review = PeriodReview(kind: .week, offset: 0, now: monday, days: days); check(!review.canCompare, "First day has no complete-day comparison")
        review = PeriodReview(kind: .month, offset: 0, now: date("2028-02-29 11:00:00"), days: days); check(review.dates.count == 29 && review.comparisonDays == 28, "Leap month and current day excluded from comparison")
        days["2026-02-28"] = DayRecord(waterML: 100)
        review = PeriodReview(kind: .month, offset: -1, now: date("2026-04-15 11:00:00"), days: days); check(review.dates.count == 31 && review.comparisonDays == 28, "Unequal months compare matching calendar days")
        review = PeriodReview(kind: .month, offset: 0, now: friday, days: [:]); check(review.recordedDays == 0 && !review.canCompare, "Missing data distinct from zero")
        // Persist the complete new schema without touching the standard user store.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("huanya-planning-tests-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StateStore(url: url); state.preferences = p; state.preferences.plannedBreaks = [plan]; state.timingEvents = e.saved.timingEvents
        try store.save(state); let restored = try store.load()
        check(restored.preferences == state.preferences && restored.plannedHistory == state.plannedHistory, "New plans and occurrence history round-trip")
        print("PASS: \(count) planning/review assertions — routines, lunch boundaries, long breaks, fixed reminders, corrections, absence provenance, weekly/monthly comparisons, migration")
    }
}
