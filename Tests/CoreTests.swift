import Foundation

@main
struct CoreTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        count += 1
    }
    static func advance(_ engine: inout ReminderEngine, from start: Date, seconds: Int) -> [ReminderKind] {
        var due: [ReminderKind] = []
        for second in 1...seconds { due += engine.advance(now: start.addingTimeInterval(Double(second))) }
        return due
    }
    static func local(_ value: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.date(from: value)!
    }
    static func main() throws {
        let start = local("2026-10-15 10:00:00")
        var saved = SavedState()
        saved.preferences.mergeReminders = false
        saved.preferences.water.intervalMinutes = 1
        saved.preferences.eyes.intervalMinutes = 2
        saved.preferences.stretch.intervalMinutes = 3
        var e = ReminderEngine(saved: saved, now: start)
        check(e.upcoming(at: start)?.0 == .water, "Earliest reminder")
        check(advance(&e, from: start, seconds: 59).isEmpty, "No early reminder")
        let due = e.advance(now: start.addingTimeInterval(60))
        check(due == [.water], "Water due at exact interval")
        check(e.saved.days[dayKey(start)]?.workSeconds == 60, "Work time accumulated")
        check(e.sittingSeconds == 60, "Sitting accumulated")
        check(e.deadlines[.water] == start.addingTimeInterval(120), "Next deadline moved")
        check(e.advance(now: start.addingTimeInterval(60)).isEmpty, "No duplicate reminder")

        e.complete(.water, now: start.addingTimeInterval(60))
        check(e.saved.days[dayKey(start)]?.waterML == 250, "Water amount recorded")
        check(e.saved.days[dayKey(start)]?.waterCount == 1, "Water count recorded")
        check(e.saved.events.count == 1, "Activity event recorded")
        check(e.sittingSeconds == 60, "Water does not reset sitting")
        e.complete(.eyes, now: start.addingTimeInterval(60), duration: 20)
        check(e.saved.days[dayKey(start)]?.eyeBreaks == 1, "Eye break recorded")
        check(e.saved.days[dayKey(start)]?.breakSeconds == 20, "Break duration recorded")
        check(e.sittingSeconds == 60, "Eye break does not imply standing")
        e.complete(.stretch, now: start.addingTimeInterval(60), duration: 60)
        check(e.sittingSeconds == 0, "Stretch resets sitting")
        check(e.saved.days[dayKey(start)]?.breakCount == 2, "Break count combines eyes and stretch")
        check(e.saved.days[dayKey(start)]?.breakSeconds == 80, "Break seconds combined")
        check(e.saved.days[dayKey(start)]?.longestSittingSeconds == 60, "Longest sitting retained")

        var disabled = saved.preferences
        disabled.water.enabled = false
        e.updatePreferences(disabled, now: start.addingTimeInterval(60))
        check(e.upcoming(at: start.addingTimeInterval(60))?.0 != .water, "Disabled reminders excluded")
        e.snooze(.eyes, now: start)
        check(e.deadlines[.eyes] == start.addingTimeInterval(300), "Snooze five minutes")

        e = ReminderEngine(saved: saved, now: start)
        e.setPaused(true, until: start.addingTimeInterval(30), now: start)
        check(e.upcoming(at: start) == nil, "Pause has no upcoming reminder")
        check(advance(&e, from: start, seconds: 29).isEmpty, "Pause does not remind")
        check(e.saved.days.isEmpty, "Pause does not count work")
        _ = e.advance(now: start.addingTimeInterval(30))
        check(!e.paused, "Timed pause resumes")
        check(e.deadlines[.water] == start.addingTimeInterval(90), "Resume gets full interval")

        e = ReminderEngine(saved: saved, now: start)
        _ = advance(&e, from: start, seconds: 10)
        let beforeSleep = e.saved.days[dayKey(start)]!.workSeconds
        check(e.advance(now: start.addingTimeInterval(3600)).isEmpty, "Long suspension does not flood reminders")
        check(e.saved.days[dayKey(start)]?.workSeconds == beforeSleep, "Sleep gap not counted")
        check(e.sittingSeconds == 0, "Sleep gap resets sitting")
        e.setSleeping(true, now: start.addingTimeInterval(3600))
        check(e.upcoming(at: start.addingTimeInterval(3600)) == nil, "Sleeping not active")
        e.setSleeping(false, now: start.addingTimeInterval(7200))
        check(e.deadlines[.water] == start.addingTimeInterval(7260), "Wake restarts interval")

        e = ReminderEngine(saved: saved, now: start)
        e.onBreak = true
        check(advance(&e, from: start, seconds: 120).isEmpty, "No interruptions during break")
        check(e.saved.days.isEmpty, "Break time is not work time")
        e.onBreak = false
        e.stoodUp()
        check(e.sittingSeconds == 0, "Manual standing resets")

        var prefs = Preferences()
        prefs.workHoursOnly = true
        check(prefs.allows(local("2026-10-15 09:00:00")), "Start time included")
        check(!prefs.allows(local("2026-10-15 18:00:00")), "End time excluded")
        check(!prefs.allows(local("2026-10-15 08:59:59")), "Before work excluded")
        prefs.weekdaysOnly = true
        check(!prefs.allows(local("2026-10-17 10:00:00")), "Weekend excluded")
        check(prefs.allows(start), "Weekday allowed")
        prefs.weekdaysOnly = false; prefs.startHour = 22; prefs.endHour = 6
        check(prefs.allows(local("2026-10-15 23:00:00")), "Overnight evening")
        check(prefs.allows(local("2026-10-16 05:00:00")), "Overnight morning")
        check(!prefs.allows(start), "Overnight midday excluded")
        prefs.startHour = 9; prefs.endHour = 9
        check(prefs.allows(local("2026-10-15 03:00:00")), "Same hours means full day")

        var quiet = saved
        quiet.preferences.workHoursOnly = true
        let night = local("2026-10-15 21:00:00")
        e = ReminderEngine(saved: quiet, now: night)
        check(advance(&e, from: night, seconds: 120).isEmpty, "No reminders outside work hours")
        check(e.saved.days.isEmpty, "Outside hours not counted")

        let midnight = local("2026-10-16 00:00:00")
        e = ReminderEngine(now: midnight.addingTimeInterval(-1))
        _ = e.advance(now: midnight.addingTimeInterval(1))
        check(e.saved.days["2026-10-15"]?.workSeconds == 1, "Midnight splits previous day")
        check(e.saved.days["2026-10-16"]?.workSeconds == 1, "Midnight splits new day")
        e.complete(.water, now: midnight)
        check(e.saved.days["2026-10-16"]?.waterML == 250, "Water assigned to completion day")

        prefs.water.intervalMinutes = -1; prefs.eyes.durationSeconds = 99999; prefs.waterGoalML = 0
        prefs.validate()
        check(prefs.water.intervalMinutes == 1, "Invalid interval clamped")
        check(prefs.eyes.durationSeconds == 600, "Invalid duration clamped")
        check(prefs.waterGoalML == 250, "Zero goal prevented")

        check(BreakDuration.parse(minutes: "3", seconds: "0") == 180, "Custom three-minute duration is accepted")
        check(BreakDuration.parse(minutes: "3", seconds: "5") == 185, "Custom duration preserves seconds")
        check(BreakDuration.parse(minutes: "0", seconds: "10") == 10, "Minimum custom duration is accepted")
        check(BreakDuration.parse(minutes: "10", seconds: "0") == 600, "Maximum custom duration is accepted")
        for input in [("", "0"), ("three", "0"), ("3.5", "0"), ("-1", "30"), ("0", "9"), ("3", "60"), ("10", "1"), (String(repeating: "9", count: 100), "0")] {
            check(BreakDuration.parse(minutes: input.0, seconds: input.1) == nil, "Invalid custom duration is rejected: \(input)")
        }
        check(BreakDuration.label(180) == "3 分钟" && BreakDuration.label(185) == "3 分 5 秒", "Custom duration labels retain minutes and seconds")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("riseup-tests-\(UUID().uuidString)")
        let store = StateStore(url: temp.appendingPathComponent("state.json"))
        let empty = try store.load()
        check(empty.days.isEmpty, "Missing state loads defaults")
        e.saved.preferences.eyes.durationSeconds = 180
        e.saved.preferences.stretch.durationSeconds = 185
        try store.save(e.saved)
        let loaded = try store.load()
        check(loaded.days == e.saved.days, "Day records persist")
        check(loaded.preferences == e.saved.preferences, "Preferences persist")
        check(loaded.preferences.eyes.durationSeconds == 180 && loaded.preferences.stretch.durationSeconds == 185, "Both custom durations survive saving and loading without rounding to presets")
        check(loaded.events.count == 1, "Events persist")
        try Data("corrupt".utf8).write(to: store.url)
        do { _ = try store.load(); fatalError("Corruption must throw") } catch { count += 1 }
        try FileManager.default.removeItem(at: temp)
        try firstBatchTests(start: start)
        try secondBatchTests(start: start)
        foregroundPauseTests(start: start)
        try usageSessionTests()
        hourlyChartTests()
        print("PASS: \(count) assertions — scheduling, migration, idle, grouped reminders, prewarnings, water undo, persistence")
    }

    static func hourlyChartTests() {
        let work = HourlyWorkDetail(hour: 9, seconds: 3120, currentHour: 10)
        check(work.rangeLabel == "09:00–10:00" && work.summary == "累计工作 52 分钟", "Hour tooltip shows padded range and actual work minutes")
        check(HourlyWorkDetail(hour: 0, seconds: 0, currentHour: 10).summary == "累计工作 0 分钟", "Past empty hours show zero rather than future status")
        check(HourlyWorkDetail(hour: 10, seconds: 0, currentHour: 10).summary == "累计工作 0 分钟", "Current empty hour is already reached")
        check(HourlyWorkDetail(hour: 10, seconds: 35, currentHour: 10).summary == "累计工作不足 1 分钟", "Partial minute is not presented as no work")
        let future = HourlyWorkDetail(hour: 23, seconds: 0, currentHour: 10)
        check(future.rangeLabel == "23:00–24:00" && future.summary == "尚未到该时段", "Last future hour uses 24:00 end label")
        check(HourlyWorkDetail(hour: 23, seconds: 120, currentHour: 10).summary == "累计工作 2 分钟", "Clock changes never hide already recorded work in later hours")
        for width in [360.0, 740.0, 1200.0] {
            check(HourlyWorkDetail.hour(at: 0, width: width) == 0 && HourlyWorkDetail.hour(at: width, width: width) == 23, "Chart hit area includes both edges at width \(width)")
            check(HourlyWorkDetail.hour(at: width * 9.5 / 24, width: width) == 9, "Hour mapping follows resized chart at width \(width)")
            check(HourlyWorkDetail.hour(at: width * 10 / 24, width: width) == 10, "A column boundary has no noninteractive gap at width \(width)")
            check(HourlyWorkDetail.tooltipCenter(hour: 0, width: width, tooltipWidth: 176) == 88, "First tooltip stays within left edge at width \(width)")
            check(HourlyWorkDetail.tooltipCenter(hour: 23, width: width, tooltipWidth: 176) == width - 88, "Last tooltip stays within right edge at width \(width)")
        }
        check(HourlyWorkDetail.hour(at: -1, width: 740) == nil && HourlyWorkDetail.hour(at: 741, width: 740) == nil, "Pointer outside chart cannot select an hour")
        check(HourlyWorkDetail.hour(at: 0, width: 0) == nil && HourlyWorkDetail.hour(at: .nan, width: 740) == nil, "Invalid layout or pointer values are ignored")
    }

    static func foregroundPauseTests(start: Date) {
        var saved = SavedState()
        saved.preferences.mergeReminders = false
        saved.preferences.water.intervalMinutes = 1
        saved.preferences.eyes.intervalMinutes = 2
        saved.preferences.stretch.intervalMinutes = 3
        var e = ReminderEngine(saved: saved, now: start)
        _ = advance(&e, from: start, seconds: 20)
        e.setForegroundBlocked(true, now: start.addingTimeInterval(20))
        check(advance(&e, from: start.addingTimeInterval(20), seconds: 600).isEmpty, "No reminders during a long foreground pause")
        check(e.saved.days[dayKey(start)]?.workSeconds == 20, "Foreground pause excludes work time")
        e.setForegroundBlocked(false, now: start.addingTimeInterval(620))
        check(e.deadlines[.water] == start.addingTimeInterval(660), "Foreground pause retains water's remaining forty seconds")
        check(e.deadlines[.eyes] == start.addingTimeInterval(720) && e.deadlines[.stretch] == start.addingTimeInterval(780), "Each plan retains its own remaining interval")
        check(advance(&e, from: start.addingTimeInterval(620), seconds: 39).isEmpty, "Resume does not fire early")
        check(e.advance(now: start.addingTimeInterval(660)) == [.water], "Resume fires exactly at remaining time")
        e.setForegroundBlocked(true, now: start.addingTimeInterval(660))
        _ = advance(&e, from: start.addingTimeInterval(660), seconds: 10)
        check(!e.setForegroundBlocked(true, now: start.addingTimeInterval(670)), "Switching between configured apps keeps the same pause")
        _ = advance(&e, from: start.addingTimeInterval(670), seconds: 10)
        e.setForegroundBlocked(false, now: start.addingTimeInterval(680))
        check(e.deadlines[.eyes] == start.addingTimeInterval(740), "Consecutive configured apps do not restart or consume the interval")

        e = ReminderEngine(saved: saved, now: start)
        _ = advance(&e, from: start, seconds: 10)
        e.snooze(.water, now: start.addingTimeInterval(10))
        e.setForegroundBlocked(true, now: start.addingTimeInterval(10))
        _ = advance(&e, from: start.addingTimeInterval(10), seconds: 60)
        var preferences = e.saved.preferences
        preferences.mergeReminders = true
        preferences.mergeWindowSeconds = 120
        preferences.eyes.intervalMinutes = 4
        e.updatePreferences(preferences, now: start.addingTimeInterval(70))
        e.setForegroundBlocked(false, now: start.addingTimeInterval(70))
        let batches = e.scheduledBatches(at: start.addingTimeInterval(70))
        check(e.deadlines[.water] == start.addingTimeInterval(370), "Explicit snooze retains its entire remaining delay")
        check(!batches.first!.kinds.contains(.water), "Merging cannot pull a paused snooze forward")
        check(e.deadlines[.eyes] == start.addingTimeInterval(310), "Changing a plan while paused replaces only that plan's interval")
        check(e.deadlines[.stretch] == start.addingTimeInterval(240), "Editing preferences preserves unchanged plans")

        for reason in ["manual", "busy", "idle", "sleep"] {
            e = ReminderEngine(saved: saved, now: start)
            _ = advance(&e, from: start, seconds: 20)
            e.setForegroundBlocked(true, now: start.addingTimeInterval(20))
            switch reason {
            case "manual": e.setPaused(true, now: start.addingTimeInterval(20))
            case "busy": e.setBusy(minutes: 1, now: start.addingTimeInterval(20))
            case "idle": e.updateIdle(secondsSinceInput: 600, now: start.addingTimeInterval(20))
            default: e.setSleeping(true, now: start.addingTimeInterval(20))
            }
            _ = advance(&e, from: start.addingTimeInterval(20), seconds: 60)
            switch reason {
            case "manual": e.setPaused(false, now: start.addingTimeInterval(80))
            case "busy": break
            case "idle": e.updateIdle(secondsSinceInput: 0, now: start.addingTimeInterval(80))
            default: e.setSleeping(false, now: start.addingTimeInterval(80))
            }
            _ = advance(&e, from: start.addingTimeInterval(80), seconds: 10)
            e.setForegroundBlocked(false, now: start.addingTimeInterval(90))
            check(e.deadlines[.water] == start.addingTimeInterval(150), "\(reason) overlap keeps its fresh interval instead of resurrecting an old countdown")
        }

        e = ReminderEngine(saved: saved, now: start)
        _ = advance(&e, from: start, seconds: 20)
        e.setForegroundBlocked(true, now: start.addingTimeInterval(20))
        _ = e.advance(now: start.addingTimeInterval(600))
        e.setForegroundBlocked(false, now: start.addingTimeInterval(600))
        check(e.deadlines[.water] == start.addingTimeInterval(660), "Process suspension keeps the existing fresh-interval rule")
        e = ReminderEngine(saved: saved, now: start)
        _ = advance(&e, from: start, seconds: 20)
        e.setForegroundBlocked(true, now: start.addingTimeInterval(20))
        e.setForegroundBlocked(false, now: start.addingTimeInterval(600))
        check(e.deadlines[.water] == start.addingTimeInterval(660), "A foreground transition after suspension cannot revive a stale interval")

        e = ReminderEngine(saved: saved, now: start)
        _ = advance(&e, from: start, seconds: 20)
        e.setForegroundBlocked(true, now: start.addingTimeInterval(20))
        _ = advance(&e, from: start.addingTimeInterval(20), seconds: 10)
        e.complete(.water, now: start.addingTimeInterval(30))
        _ = advance(&e, from: start.addingTimeInterval(30), seconds: 10)
        check(e.undoLastWater(now: start.addingTimeInterval(40)) == 250, "Water undo remains available during foreground pause")
        e.setForegroundBlocked(false, now: start.addingTimeInterval(40))
        check(e.deadlines[.water] == start.addingTimeInterval(80), "Water undo restores the paused deadline without consuming hidden time")
    }

    static func firstBatchTests(start: Date) throws {
        var state = SavedState()
        state.preferences.waterML = 400
        state.days[dayKey(start)] = DayRecord(waterML: 500, waterCount: 2)
        state.events = [ActivityEvent(date: start, kind: .water, amount: 250)]
        let data = try JSONEncoder().encode(state)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var preferences = legacy["preferences"] as! [String: Any]
        for key in ["idlePauseEnabled", "idlePauseMinutes", "mergeReminders", "mergeWindowSeconds", "prewarningEnabled", "prewarningSeconds", "waterPresets"] { preferences[key] = nil }
        legacy["preferences"] = preferences
        let migrated = try JSONDecoder().decode(SavedState.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(migrated.preferences.waterML == 400, "Old cup size survives migration")
        check(migrated.days == state.days && migrated.events.count == 1, "Old statistics and events survive migration")
        check(migrated.preferences.idlePauseMinutes == 3 && migrated.preferences.idlePauseEnabled, "New idle defaults loaded")
        check(migrated.preferences.waterPresets == [150, 250, 350], "New cup presets loaded")
        check(migrated.preferences.mergeReminders && migrated.preferences.prewarningSeconds == 30, "New reminder defaults loaded")
        let roundTrip = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(migrated))
        check(roundTrip.preferences == migrated.preferences, "All new options round trip")

        state = SavedState()
        state.preferences.mergeReminders = false
        var e = ReminderEngine(saved: state, now: start)
        _ = advance(&e, from: start, seconds: 10)
        check(e.updateIdle(secondsSinceInput: 180, now: start.addingTimeInterval(11)), "Idle enters at configured threshold")
        check(e.idle && e.upcoming(at: start.addingTimeInterval(11)) == nil, "Idle suppresses reminders")
        _ = advance(&e, from: start.addingTimeInterval(11), seconds: 4)
        check(e.saved.days[dayKey(start)]?.workSeconds == 10, "Idle adds no work time")
        check(e.sittingSeconds == 10, "A short idle pause preserves the current usage estimate")
        check(e.saved.events.isEmpty, "Idle does not create completed breaks")
        check(e.updateIdle(secondsSinceInput: 0, now: start.addingTimeInterval(16)), "Activity resumes from idle")
        check(e.deadlines[.eyes] == start.addingTimeInterval(16 + 1200), "Return starts a full reminder interval")
        _ = e.advance(now: start.addingTimeInterval(17))
        check(e.saved.days[dayKey(start)]?.workSeconds == 11, "Work resumes without the idle gap")
        e.setPaused(true, now: start.addingTimeInterval(17))
        _ = e.updateIdle(secondsSinceInput: 180, now: start.addingTimeInterval(18))
        _ = e.updateIdle(secondsSinceInput: 0, now: start.addingTimeInterval(19))
        check(e.paused && !e.isActive(at: start.addingTimeInterval(19)), "Returning from idle preserves manual pause")
        var disabled = e.saved.preferences
        disabled.idlePauseEnabled = false
        e.updatePreferences(disabled, now: start.addingTimeInterval(20))
        _ = e.updateIdle(secondsSinceInput: 9999, now: start.addingTimeInterval(20))
        check(!e.idle, "Idle detection can be disabled")
        _ = e.updateIdle(secondsSinceInput: 0, sessionLocked: true, now: start.addingTimeInterval(21))
        check(e.idle, "Lock still pauses when idle detection is disabled")
        _ = e.updateIdle(secondsSinceInput: 0, sessionLocked: false, now: start.addingTimeInterval(22))
        check(!e.idle && e.paused, "Unlock does not undo manual pause")

        state = SavedState()
        state.preferences.water.intervalMinutes = 1
        state.preferences.eyes.intervalMinutes = 2
        state.preferences.stretch.intervalMinutes = 3
        e = ReminderEngine(saved: state, now: start)
        let batches = e.scheduledBatches(at: start)
        check(batches.count == 1 && batches[0].kinds == ReminderKind.allCases, "Nearby reminders form one batch")
        check(batches[0].dueAt == start.addingTimeInterval(60), "Merged batch uses earliest due time")
        check(e.prewarning(at: start.addingTimeInterval(29)) == nil, "No early prewarning")
        check(e.prewarning(at: start.addingTimeInterval(30))?.kinds == ReminderKind.allCases, "Prewarning includes the full batch")
        check(e.prewarning(at: start.addingTimeInterval(60)) == nil, "No warning after deadline")
        let due = advance(&e, from: start, seconds: 60)
        check(due == ReminderKind.allCases, "Merged reminder delivered exactly once")
        check(e.advance(now: start.addingTimeInterval(60)).isEmpty, "Merged reminder not repeated on same tick")
        check(e.saved.events.isEmpty, "Showing a batch never marks it completed")
        state.preferences.mergeReminders = false
        e = ReminderEngine(saved: state, now: start)
        check(e.scheduledBatches(at: start).count == 3, "Merge toggle restores independent deadlines")
        state.preferences.mergeReminders = true
        state.preferences.eyes.intervalMinutes = 3
        state.preferences.stretch.intervalMinutes = 5
        e = ReminderEngine(saved: state, now: start)
        check(e.scheduledBatches(at: start).first?.kinds == [.water, .eyes], "Merge window is anchored, not chained")
        state.preferences.water.intervalMinutes = 4
        state.preferences.stretch.enabled = false
        e = ReminderEngine(saved: state, now: start)
        e.snooze(.eyes, now: start)
        check(e.scheduledBatches(at: start).first?.kinds == [.water], "Snoozed item cannot be pulled forward into a batch")
        check(e.scheduledBatches(at: start).last?.dueAt == start.addingTimeInterval(300), "Snoozed item retains five minutes")
        _ = e.updateIdle(secondsSinceInput: 180, now: start.addingTimeInterval(1))
        _ = e.updateIdle(secondsSinceInput: 0, now: start.addingTimeInterval(2))
        check(e.deadlines[.eyes]! >= start.addingTimeInterval(300), "Idle resume never shortens an explicit snooze")
        e.setPaused(true, now: start)
        check(e.prewarning(at: start.addingTimeInterval(220)) == nil, "Manual pause suppresses prewarnings")

        e = ReminderEngine(now: start)
        let oldDeadline = e.deadlines[.water]
        e.complete(.water, now: start.addingTimeInterval(1), waterAmount: 150)
        e.complete(.eyes, now: start.addingTimeInterval(2), duration: 20)
        check(e.saved.days[dayKey(start)]?.waterML == 150, "Quick cup records selected amount")
        var newCup = e.saved.preferences
        newCup.waterML = 500
        e.updatePreferences(newCup, now: start.addingTimeInterval(3))
        check(e.undoLastWater(now: start.addingTimeInterval(4)) == 150, "Undo uses recorded amount, not current cup size")
        check(e.saved.days[dayKey(start)]?.waterML == 0 && e.saved.days[dayKey(start)]?.waterCount == 0, "Undo updates amount and count")
        check(e.saved.events.count == 1 && e.saved.events[0].kind == .eyes, "Undo removes only its matching water event")
        check(e.deadlines[.water] == oldDeadline, "Undo restores the previous future reminder")
        check(e.undoLastWater(now: start.addingTimeInterval(5)) == nil, "Undo is one level, cannot repeatedly subtract")
        e.complete(.water, now: start.addingTimeInterval(6), waterAmount: 150)
        e.complete(.water, now: start.addingTimeInterval(7), waterAmount: 350)
        _ = e.undoLastWater(now: start.addingTimeInterval(8))
        check(e.saved.days[dayKey(start)]?.waterML == 150, "Undo preserves earlier cups")
        let midnight = local("2026-10-16 00:00:00")
        e = ReminderEngine(now: midnight.addingTimeInterval(-2))
        e.complete(.water, now: midnight.addingTimeInterval(-1), waterAmount: 350)
        _ = e.undoLastWater(now: midnight.addingTimeInterval(1))
        check(e.saved.days["2026-10-15"]?.waterML == 0, "Cross-midnight undo updates the original day")
        check(e.saved.days["2026-10-16"] == nil, "Cross-midnight undo does not alter the new day")

        var invalid = Preferences()
        invalid.waterPresets = [-1, 9999]
        invalid.idlePauseMinutes = 0
        invalid.mergeWindowSeconds = 9999
        invalid.prewarningSeconds = 0
        invalid.validate()
        check(invalid.waterPresets == [50, 1000, 350], "Preset validation preserves exactly three safe quantities")
        check(invalid.idlePauseMinutes == 1 && invalid.mergeWindowSeconds == 300 && invalid.prewarningSeconds == 10, "New timing values are bounded")
    }

    static func secondBatchTests(start: Date) throws {
        let legacyJSON = """
        {"version":1,"preferences":{"waterML":350},"days":{"2026-10-15":{"waterML":700,"waterCount":2,"eyeBreaks":3,"stretches":1,"workSeconds":3600,"breakSeconds":120,"longestSittingSeconds":1800}},"events":[]}
        """
        let legacy = try JSONDecoder().decode(SavedState.self, from: Data(legacyJSON.utf8))
        check(legacy.days["2026-10-15"]?.waterML == 700 && legacy.preferences.waterML == 350, "Original released data remains intact")
        check(legacy.days["2026-10-15"]?.workSeconds == 3600, "Legacy work history survives new statistics")
        check(legacy.days["2026-10-15"]?.hourlyWorkSeconds == Array(repeating: 0, count: 24), "Legacy hourly distribution is not fabricated")
        check(legacy.reminderEvents.isEmpty && legacy.workPeriods.isEmpty, "New detail records start empty")
        check(!legacy.preferences.globalShortcutsEnabled && !legacy.preferences.showMenuCountdown && legacy.preferences.busyApplications.isEmpty, "New system features remain opt-in")

        var state = SavedState()
        state.preferences.water.intervalMinutes = 1
        state.preferences.eyes.enabled = false
        state.preferences.stretch.enabled = false
        var e = ReminderEngine(saved: state, now: start)
        _ = advance(&e, from: start, seconds: 5)
        e.setBusy(minutes: 30, now: start.addingTimeInterval(5))
        check(e.scheduledBatches(at: start.addingTimeInterval(5)).isEmpty, "Busy mode suppresses all reminder batches")
        check(advance(&e, from: start.addingTimeInterval(5), seconds: 1799).isEmpty, "Busy mode stays quiet for full duration")
        check(e.saved.days[dayKey(start)]?.workSeconds == 5, "Busy time is excluded from work")
        _ = e.advance(now: start.addingTimeInterval(1805))
        check(e.busyUntil == nil && e.isActive(at: start.addingTimeInterval(1805)), "Thirty-minute busy timer automatically ends")
        check(e.deadlines[.water] == start.addingTimeInterval(1865), "Busy expiry starts a fresh interval")
        check(advance(&e, from: start.addingTimeInterval(1805), seconds: 60) == [.water], "First reminder occurs after a full fresh interval")
        check(e.saved.days[dayKey(start)]?.remindersDue == 1, "Automatic reminder due is recorded once")
        e.setPaused(true, now: start.addingTimeInterval(1865))
        e.setBusy(minutes: 1, now: start.addingTimeInterval(1865))
        _ = advance(&e, from: start.addingTimeInterval(1865), seconds: 60)
        check(e.paused && e.busyUntil == nil && !e.isActive(at: start.addingTimeInterval(1925)), "Busy expiry preserves manual pause")
        e.setPaused(false, now: start.addingTimeInterval(1925))
        _ = e.setForegroundBlocked(true, now: start.addingTimeInterval(1925))
        e.setBusy(minutes: 1, now: start.addingTimeInterval(1925))
        _ = advance(&e, from: start.addingTimeInterval(1925), seconds: 60)
        check(e.foregroundBlocked && !e.isActive(at: start.addingTimeInterval(1985)), "Busy expiry preserves application pause")
        _ = e.setForegroundBlocked(false, now: start.addingTimeInterval(1985))
        check(e.deadlines[.water] == start.addingTimeInterval(2045), "Busy expiry provides a fresh interval while the app pause remains in effect")
        let deadline = e.deadlines[.water]
        check(!e.setForegroundBlocked(false, now: start.addingTimeInterval(1986)) && e.deadlines[.water] == deadline, "Repeated app observations never reset deadlines")
        e.snooze(.water, now: start.addingTimeInterval(1986))
        _ = e.setForegroundBlocked(true, now: start.addingTimeInterval(1987))
        _ = e.setForegroundBlocked(false, now: start.addingTimeInterval(1988))
        check(e.deadlines[.water]! >= start.addingTimeInterval(2286), "App switches preserve explicit five-minute snooze")
        e.skip(.water, now: start.addingTimeInterval(1988))
        check(e.deadlines[.water] == start.addingTimeInterval(2048), "Skip schedules the next normal interval")
        check(e.saved.days[dayKey(start)]?.remindersSkipped == 1 && e.saved.days[dayKey(start)]?.waterML == 0, "Skip is tracked without implying completion")

        let hour = local("2026-10-15 10:59:59")
        e = ReminderEngine(now: hour)
        _ = e.advance(now: hour.addingTimeInterval(2))
        let day = e.saved.days[dayKey(hour)]!
        check(day.hourlyWorkSeconds[10] == 1 && day.hourlyWorkSeconds[11] == 1, "Tick crossing hour boundary splits exactly")
        check(day.hourlyWorkSeconds.reduce(0,+) == day.workSeconds, "Hourly work totals match recorded work")
        check(e.saved.workPeriods.count == 1 && e.saved.workPeriods[0].seconds == 2, "Continuous work period spans hour boundary")
        e.setPaused(true, now: hour.addingTimeInterval(2))
        _ = e.advance(now: hour.addingTimeInterval(3))
        e.setPaused(false, now: hour.addingTimeInterval(3))
        _ = e.advance(now: hour.addingTimeInterval(4))
        check(e.saved.workPeriods.count == 2 && e.saved.workPeriods[1].seconds == 1, "Pause splits continuous periods without adding paused time")
        e.onBreak = true
        _ = e.advance(now: hour.addingTimeInterval(5))
        e.onBreak = false
        _ = e.advance(now: hour.addingTimeInterval(6))
        check(e.saved.workPeriods.count == 3, "A break splits continuous work")
        _ = e.updateIdle(secondsSinceInput: 180, now: hour.addingTimeInterval(7))
        _ = e.advance(now: hour.addingTimeInterval(8))
        _ = e.updateIdle(secondsSinceInput: 0, now: hour.addingTimeInterval(9))
        _ = e.advance(now: hour.addingTimeInterval(10))
        check(e.saved.workPeriods.count == 4, "Idle interruption splits continuous work")
        let before = e.saved.days[dayKey(hour)]!.workSeconds
        _ = e.advance(now: hour.addingTimeInterval(1000))
        check(e.saved.days[dayKey(hour)]!.workSeconds == before, "Suspension never creates a long work period")
        _ = e.advance(now: hour.addingTimeInterval(1001))
        check(e.saved.workPeriods.count == 5, "Suspension ends the previous work period")

        let midnight = local("2026-10-16 00:00:00")
        e = ReminderEngine(now: midnight.addingTimeInterval(-1))
        _ = e.advance(now: midnight.addingTimeInterval(1))
        check(e.saved.days["2026-10-15"]?.hourlyWorkSeconds[23] == 1 && e.saved.days["2026-10-16"]?.hourlyWorkSeconds[0] == 1, "Midnight hourly work stays on original days")
        check(e.saved.workPeriods.count == 2 && e.saved.workPeriods.allSatisfy { $0.seconds == 1 }, "Midnight splits continuous detail by date")
        e.recordInteraction(.snoozed, kind: .eyes, now: midnight.addingTimeInterval(-1))
        e.recordInteraction(.snoozed, kind: .eyes, now: midnight)
        check(e.saved.days["2026-10-15"]?.remindersSnoozed == 1 && e.saved.days["2026-10-16"]?.remindersSnoozed == 1, "Repeated snoozes are attributed to their action dates")
        e.saved.preferences.busyApplications = [BusyApplication(bundleIdentifier: "test.app", name: "Test"), BusyApplication(bundleIdentifier: "test.app", name: "Duplicate")]
        e.saved.preferences.validate()
        check(e.saved.preferences.busyApplications.count == 1, "Application pause rules are deduplicated")
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(e.saved))
        check(restored.days == e.saved.days && restored.reminderEvents.count == 2 && restored.workPeriods.count == 2, "New statistics and rules round trip with existing data")
        let restarted = ReminderEngine(saved: restored, now: midnight)
        check(restarted.busyUntil == nil && !restarted.foregroundBlocked, "Temporary busy state does not stick across relaunch")
        for index in 0..<1010 { e.recordInteraction(.snoozed, kind: .water, now: midnight.addingTimeInterval(Double(index))) }
        check(e.saved.reminderEvents.count == 1000 && e.saved.days[dayKey(midnight)]?.remindersSnoozed == 1011, "Detail cap preserves aggregate statistics")
    }

    static func usageSessionTests() throws {
        let start = local("2026-10-15 10:00:00")
        var e = ReminderEngine(now: start)
        func sample(_ engine: inout ReminderEngine, date: Date, idle: Double = 0, locked: Bool = false) {
            _ = engine.updateIdle(secondsSinceInput: idle, sessionLocked: locked, now: date)
            _ = engine.advance(now: date)
        }
        for second in 1...60 { sample(&e, date: start.addingTimeInterval(Double(second))) }
        check(e.sittingSeconds == 60, "Active use accumulates a usage round")
        e.complete(.water, now: start.addingTimeInterval(60), waterAmount: 350)
        let records = e.saved.events.map(\.id)
        for second in 1...299 { sample(&e, date: start.addingTimeInterval(Double(60 + second)), idle: Double(second)) }
        let beforeReturn = e.sittingSeconds
        let work = e.saved.days[dayKey(start)]!.workSeconds
        check(e.idle && beforeReturn > 60, "Short idle time pauses according to existing idle preference")
        sample(&e, date: start.addingTimeInterval(359), idle: 0)
        check(!e.idle && e.sittingSeconds == beforeReturn, "Returning before five minutes preserves this round")
        check(e.saved.days[dayKey(start)]!.workSeconds == work, "Idle return does not add time spent away")

        for second in 1...300 { sample(&e, date: start.addingTimeInterval(Double(359 + second)), idle: Double(second)) }
        check(e.sittingSeconds == 0, "Five minutes without input ends the usage round")
        let before = e.saved.days[dayKey(start)]!
        sample(&e, date: start.addingTimeInterval(660))
        check(e.sittingSeconds == 0 && !e.idle, "Long-idle return starts at zero")
        sample(&e, date: start.addingTimeInterval(661))
        check(e.sittingSeconds == 1, "New round counts only time after returning")
        check(e.saved.days[dayKey(start)]!.waterML == 350 && e.saved.events.map(\.id) == records && e.saved.days[dayKey(start)]!.breakCount == 0, "Automatic reset never records water, standing, or completed breaks")
        check(e.saved.days[dayKey(start)]!.longestSittingSeconds == before.longestSittingSeconds, "Automatic reset preserves the historical maximum")

        e = ReminderEngine(now: start)
        for second in 1...10 { sample(&e, date: start.addingTimeInterval(Double(second))) }
        for second in 1...299 { sample(&e, date: start.addingTimeInterval(Double(10 + second)), idle: Double(second)) }
        sample(&e, date: start.addingTimeInterval(310), idle: 0)
        check(e.sittingSeconds == 0, "Input just before the five-minute tick cannot hide the long absence")

        e = ReminderEngine(now: start)
        for second in 1...10 { sample(&e, date: start.addingTimeInterval(Double(second))) }
        sample(&e, date: start.addingTimeInterval(10), locked: true)
        for second in 1...299 { sample(&e, date: start.addingTimeInterval(Double(10 + second)), locked: true) }
        sample(&e, date: start.addingTimeInterval(309), locked: false)
        check(e.sittingSeconds == 10 && !e.idle, "Short lock preserves the round even with inputs on lock screen")
        sample(&e, date: start.addingTimeInterval(310), locked: true)
        for second in 1...300 { sample(&e, date: start.addingTimeInterval(Double(310 + second)), locked: true) }
        sample(&e, date: start.addingTimeInterval(611), locked: false)
        check(e.sittingSeconds == 0 && e.saved.days[dayKey(start)]?.breakCount == 0, "Long lock starts a new round without implying a completed break")

        var prefs = Preferences()
        prefs.idlePauseEnabled = false
        e = ReminderEngine(now: start)
        e.updatePreferences(prefs, now: start)
        for second in 1...10 { sample(&e, date: start.addingTimeInterval(Double(second))) }
        for second in 1...310 { sample(&e, date: start.addingTimeInterval(Double(10 + second)), idle: Double(second)) }
        check(!e.idle && e.sittingSeconds == 0, "Usage reset works even when reminder idle pause is disabled")
        check(e.saved.days[dayKey(start)]?.workSeconds == 320, "Disabling idle pause still retains the user's work counting preference")
        sample(&e, date: start.addingTimeInterval(321))
        sample(&e, date: start.addingTimeInterval(322))
        check(e.sittingSeconds <= 2, "Long inactivity is excluded from the new usage round")
        prefs.idlePauseEnabled = true
        prefs.idlePauseMinutes = 30
        e = ReminderEngine(now: start)
        e.updatePreferences(prefs, now: start)
        for second in 1...305 { sample(&e, date: start.addingTimeInterval(Double(second)), idle: Double(second)) }
        check(!e.idle && e.sittingSeconds == 0, "Usage round threshold stays five minutes with a longer reminder pause threshold")

        let midnight = local("2026-10-16 00:00:00")
        let evening = midnight.addingTimeInterval(-20)
        e = ReminderEngine(now: evening)
        for second in 1...10 { sample(&e, date: evening.addingTimeInterval(Double(second))) }
        sample(&e, date: midnight.addingTimeInterval(-10), locked: true)
        for second in 1...11 { sample(&e, date: midnight.addingTimeInterval(Double(second - 10)), locked: true) }
        check(e.sittingSeconds == 0 && e.saved.days["2026-10-16"] == nil, "Midnight during a short lock clears only the current estimate")
        sample(&e, date: midnight.addingTimeInterval(2), locked: false)
        sample(&e, date: midnight.addingTimeInterval(3))
        check(e.sittingSeconds == 1 && e.saved.days["2026-10-16"]?.longestSittingSeconds == 1, "Unlock after midnight cannot carry yesterday's counter into today's record")
        check(e.saved.days["2026-10-15"]?.workSeconds == 10, "Yesterday's record survives the new round")

        e = ReminderEngine(now: evening)
        for second in 1...10 { sample(&e, date: evening.addingTimeInterval(Double(second))) }
        _ = e.updateIdle(secondsSinceInput: 180, now: midnight.addingTimeInterval(-1))
        _ = e.updateIdle(secondsSinceInput: 0, now: midnight.addingTimeInterval(1))
        _ = e.advance(now: midnight.addingTimeInterval(1))
        check(e.sittingSeconds == 0, "Idle transition that rewrites lastTick at midnight still clears yesterday's round")
        _ = e.advance(now: midnight.addingTimeInterval(2))
        check(e.saved.days["2026-10-16"]?.workSeconds == 1 && e.saved.days["2026-10-16"]?.longestSittingSeconds == 1, "First morning minute cannot inherit yesterday's forty-four-minute estimate")

        e = ReminderEngine(now: evening)
        _ = advance(&e, from: evening, seconds: 10)
        e.setPaused(true, now: midnight.addingTimeInterval(-10))
        _ = e.advance(now: midnight.addingTimeInterval(1))
        check(e.sittingSeconds == 0 && e.paused, "Crossing midnight clears usage while retaining manual pause")
        e.setPaused(false, now: midnight.addingTimeInterval(2))
        _ = e.advance(now: midnight.addingTimeInterval(3))
        e.setSleeping(true, now: midnight.addingTimeInterval(3))
        e.setSleeping(false, now: midnight.addingTimeInterval(4))
        check(e.sittingSeconds == 0, "Even a short true system sleep starts a new round on wake")
        _ = e.advance(now: midnight.addingTimeInterval(5))
        check(e.sittingSeconds == 1, "Wake time does not include sleep duration")
        let saved = e.saved
        let restarted = ReminderEngine(saved: saved, now: midnight.addingTimeInterval(6))
        check(restarted.sittingSeconds == 0 && restarted.saved.days == saved.days, "Relaunch clears the runtime estimate and preserves all saved history")
        let roundTrip = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(saved))
        check(roundTrip.days == saved.days, "Existing statistics storage remains compatible")
    }
}
