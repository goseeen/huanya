import Foundation

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case water, eyes, stretch
    var id: String { rawValue }
    var title: String { switch self { case .water: return "喝水提醒"; case .eyes: return "护眼休息"; case .stretch: return "起身拉伸" } }
    var symbol: String { switch self { case .water: return "drop.fill"; case .eyes: return "eye"; case .stretch: return "figure.flexibility" } }
    var message: String { switch self { case .water: return "给自己倒杯水，慢慢喝几口。"; case .eyes: return "把视线从屏幕移开，看看远处，让眼睛歇一会儿。"; case .stretch: return "站起来，舒展肩颈，走动一小会儿。" } }
    var short: String { switch self { case .water: return "喝水"; case .eyes: return "护眼"; case .stretch: return "拉伸" } }
}

struct ReminderPlan: Codable, Equatable {
    var enabled: Bool = true
    var intervalMinutes: Int
    var durationSeconds: Int
}

struct HourlyWorkDetail {
    let hour: Int
    let seconds: Double
    let currentHour: Int

    var rangeLabel: String { String(format: "%02d:00–%02d:00", hour, hour + 1) }
    // A clock change may leave real records in a later hour. Keep those visible.
    var isFuture: Bool { hour > currentHour && seconds <= 0 }
    var summary: String {
        if isFuture { return "尚未到该时段" }
        if seconds > 0 && seconds < 60 { return "累计工作不足 1 分钟" }
        return "累计工作 \(Int(max(0, seconds) / 60)) 分钟"
    }

    static func hour(at x: Double, width: Double) -> Int? {
        guard x.isFinite, width.isFinite, width > 0, x >= 0, x <= width else { return nil }
        return min(23, Int(x / width * 24))
    }

    static func tooltipCenter(hour: Int, width: Double, tooltipWidth: Double) -> Double {
        let half = min(tooltipWidth, width) / 2
        return min(width - half, max(half, (Double(hour) + 0.5) / 24 * width))
    }
}

enum BreakDuration {
    static let range = 10...600
    static let presets = [10, 20, 30, 60, 120, 300, 600]

    static func parse(minutes: String, seconds: String) -> Int? {
        guard let minutes = Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              let seconds = Int(seconds.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...10).contains(minutes), (0...59).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        return range.contains(total) ? total : nil
    }

    static func label(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds % 60 == 0 { return "\(seconds / 60) 分钟" }
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}

struct BusyApplication: Codable, Equatable, Identifiable {
    var bundleIdentifier: String
    var name: String
    var id: String { bundleIdentifier }
}

enum StretchCard: Int, CaseIterable {
    case shoulders, wrists, walk
    var title: String { switch self { case .shoulders: return "肩膀放松"; case .wrists: return "手腕舒展"; case .walk: return "站立走动" } }
    var instruction: String {
        switch self {
        case .shoulders: return "站直，肩膀轻轻上提，再慢慢放下。自然呼吸，动作保持舒适。"
        case .wrists: return "松开鼠标，放松双手。轻轻张开手指，再缓缓收拢，转动手腕。"
        case .walk: return "离开座位，在身边慢慢走几步。抬头看看远处，留意周围空间。"
        }
    }
}

struct Preferences: Codable, Equatable {
    var water = ReminderPlan(intervalMinutes: 30, durationSeconds: 0)
    var eyes = ReminderPlan(intervalMinutes: 20, durationSeconds: 20)
    var stretch = ReminderPlan(intervalMinutes: 45, durationSeconds: 60)
    var waterML = 250
    var waterGoalML = 2000
    var breakGoal = 8
    var sound = true
    var floatingReminder = true
    var workHoursOnly = false
    var weekdaysOnly = false
    var startHour = 9
    var endHour = 18
    var idlePauseEnabled = true
    var idlePauseMinutes = 3
    var mergeReminders = true
    var mergeWindowSeconds = 120
    var prewarningEnabled = true
    var prewarningSeconds = 30
    var waterPresets = [150, 250, 350]
    var busyApplications: [BusyApplication] = []
    var showMenuCountdown = false
    var globalShortcutsEnabled = false
    var stretchCardsEnabled = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case water, eyes, stretch, waterML, waterGoalML, breakGoal, sound, floatingReminder
        case workHoursOnly, weekdaysOnly, startHour, endHour
        case idlePauseEnabled, idlePauseMinutes, mergeReminders, mergeWindowSeconds
        case prewarningEnabled, prewarningSeconds, waterPresets
        case busyApplications, showMenuCountdown, globalShortcutsEnabled, stretchCardsEnabled
    }

    // New options must not make existing 1.0.x settings unreadable.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        water = try c.decodeIfPresent(ReminderPlan.self, forKey: .water) ?? water
        eyes = try c.decodeIfPresent(ReminderPlan.self, forKey: .eyes) ?? eyes
        stretch = try c.decodeIfPresent(ReminderPlan.self, forKey: .stretch) ?? stretch
        waterML = try c.decodeIfPresent(Int.self, forKey: .waterML) ?? waterML
        waterGoalML = try c.decodeIfPresent(Int.self, forKey: .waterGoalML) ?? waterGoalML
        breakGoal = try c.decodeIfPresent(Int.self, forKey: .breakGoal) ?? breakGoal
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? sound
        floatingReminder = try c.decodeIfPresent(Bool.self, forKey: .floatingReminder) ?? floatingReminder
        workHoursOnly = try c.decodeIfPresent(Bool.self, forKey: .workHoursOnly) ?? workHoursOnly
        weekdaysOnly = try c.decodeIfPresent(Bool.self, forKey: .weekdaysOnly) ?? weekdaysOnly
        startHour = try c.decodeIfPresent(Int.self, forKey: .startHour) ?? startHour
        endHour = try c.decodeIfPresent(Int.self, forKey: .endHour) ?? endHour
        idlePauseEnabled = try c.decodeIfPresent(Bool.self, forKey: .idlePauseEnabled) ?? idlePauseEnabled
        idlePauseMinutes = try c.decodeIfPresent(Int.self, forKey: .idlePauseMinutes) ?? idlePauseMinutes
        mergeReminders = try c.decodeIfPresent(Bool.self, forKey: .mergeReminders) ?? mergeReminders
        mergeWindowSeconds = try c.decodeIfPresent(Int.self, forKey: .mergeWindowSeconds) ?? mergeWindowSeconds
        prewarningEnabled = try c.decodeIfPresent(Bool.self, forKey: .prewarningEnabled) ?? prewarningEnabled
        prewarningSeconds = try c.decodeIfPresent(Int.self, forKey: .prewarningSeconds) ?? prewarningSeconds
        waterPresets = try c.decodeIfPresent([Int].self, forKey: .waterPresets) ?? waterPresets
        busyApplications = try c.decodeIfPresent([BusyApplication].self, forKey: .busyApplications) ?? busyApplications
        showMenuCountdown = try c.decodeIfPresent(Bool.self, forKey: .showMenuCountdown) ?? showMenuCountdown
        globalShortcutsEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutsEnabled) ?? globalShortcutsEnabled
        stretchCardsEnabled = try c.decodeIfPresent(Bool.self, forKey: .stretchCardsEnabled) ?? stretchCardsEnabled
        validate()
    }

    subscript(_ kind: ReminderKind) -> ReminderPlan {
        get { switch kind { case .water: return water; case .eyes: return eyes; case .stretch: return stretch } }
        set { switch kind { case .water: water = newValue; case .eyes: eyes = newValue; case .stretch: stretch = newValue } }
    }

    func allows(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        if weekdaysOnly && (weekday == 1 || weekday == 7) { return false }
        guard workHoursOnly else { return true }
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return true }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }

    mutating func validate() {
        for kind in ReminderKind.allCases {
            var plan = self[kind]
            plan.intervalMinutes = min(180, max(1, plan.intervalMinutes))
            plan.durationSeconds = kind == .water ? 0 : min(BreakDuration.range.upperBound, max(BreakDuration.range.lowerBound, plan.durationSeconds))
            self[kind] = plan
        }
        waterML = min(1000, max(50, waterML))
        waterGoalML = min(6000, max(250, waterGoalML))
        breakGoal = min(30, max(1, breakGoal))
        startHour = min(23, max(0, startHour))
        endHour = min(23, max(0, endHour))
        idlePauseMinutes = min(30, max(1, idlePauseMinutes))
        mergeWindowSeconds = min(300, max(0, mergeWindowSeconds))
        prewarningSeconds = min(60, max(10, prewarningSeconds))
        let defaults = [150, 250, 350]
        waterPresets = (0..<3).map { index in min(1000, max(50, index < waterPresets.count ? waterPresets[index] : defaults[index])) }
        var identifiers = Set<String>()
        busyApplications = Array(busyApplications.filter { !$0.bundleIdentifier.isEmpty && identifiers.insert($0.bundleIdentifier).inserted }.prefix(30))
    }
}

struct DayRecord: Codable, Equatable {
    var waterML = 0
    var waterCount = 0
    var eyeBreaks = 0
    var stretches = 0
    var workSeconds: Double = 0
    var breakSeconds = 0
    var longestSittingSeconds: Double = 0
    var remindersDue = 0
    var remindersSnoozed = 0
    var remindersSkipped = 0
    var hourlyWorkSeconds = Array(repeating: 0.0, count: 24)
    var breakCount: Int { eyeBreaks + stretches }

    init(waterML: Int = 0, waterCount: Int = 0, eyeBreaks: Int = 0, stretches: Int = 0, workSeconds: Double = 0, breakSeconds: Int = 0, longestSittingSeconds: Double = 0) {
        self.waterML = waterML; self.waterCount = waterCount; self.eyeBreaks = eyeBreaks
        self.stretches = stretches; self.workSeconds = workSeconds; self.breakSeconds = breakSeconds
        self.longestSittingSeconds = longestSittingSeconds
    }
    private enum CodingKeys: String, CodingKey {
        case waterML, waterCount, eyeBreaks, stretches, workSeconds, breakSeconds, longestSittingSeconds
        case remindersDue, remindersSnoozed, remindersSkipped, hourlyWorkSeconds
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waterML = try c.decodeIfPresent(Int.self, forKey: .waterML) ?? 0
        waterCount = try c.decodeIfPresent(Int.self, forKey: .waterCount) ?? 0
        eyeBreaks = try c.decodeIfPresent(Int.self, forKey: .eyeBreaks) ?? 0
        stretches = try c.decodeIfPresent(Int.self, forKey: .stretches) ?? 0
        workSeconds = try c.decodeIfPresent(Double.self, forKey: .workSeconds) ?? 0
        breakSeconds = try c.decodeIfPresent(Int.self, forKey: .breakSeconds) ?? 0
        longestSittingSeconds = try c.decodeIfPresent(Double.self, forKey: .longestSittingSeconds) ?? 0
        remindersDue = try c.decodeIfPresent(Int.self, forKey: .remindersDue) ?? 0
        remindersSnoozed = try c.decodeIfPresent(Int.self, forKey: .remindersSnoozed) ?? 0
        remindersSkipped = try c.decodeIfPresent(Int.self, forKey: .remindersSkipped) ?? 0
        let hours = try c.decodeIfPresent([Double].self, forKey: .hourlyWorkSeconds) ?? []
        hourlyWorkSeconds = (0..<24).map { $0 < hours.count ? max(0, hours[$0]) : 0 }
    }
}

enum ReminderInteraction: String, Codable { case due, snoozed, skipped }
struct ReminderInteractionEvent: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var kind: ReminderKind
    var action: ReminderInteraction
}
struct WorkPeriod: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var seconds: Double { max(0, end.timeIntervalSince(start)) }
}

struct ActivityEvent: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var kind: ReminderKind
    var amount: Int
}

struct SavedState: Codable {
    var version = 1
    var preferences = Preferences()
    var days: [String: DayRecord] = [:]
    var events: [ActivityEvent] = []
    var reminderEvents: [ReminderInteractionEvent] = []
    var workPeriods: [WorkPeriod] = []
    init() {}
    private enum CodingKeys: String, CodingKey { case version, preferences, days, events, reminderEvents, workPeriods }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        days = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
        events = try c.decodeIfPresent([ActivityEvent].self, forKey: .events) ?? []
        reminderEvents = try c.decodeIfPresent([ReminderInteractionEvent].self, forKey: .reminderEvents) ?? []
        workPeriods = try c.decodeIfPresent([WorkPeriod].self, forKey: .workPeriods) ?? []
    }
}

func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

struct ReminderBatch: Equatable, Identifiable {
    let kinds: [ReminderKind]
    let dueAt: Date
    var id: String { kinds.map(\.rawValue).joined(separator: "-") + ".\(Int64(dueAt.timeIntervalSince1970 * 1000))" }
    var title: String { kinds.map(\.short).joined(separator: " · ") }
}

struct WaterUndo {
    let eventID: UUID
    let day: String
    let amount: Int
    let previousDeadline: Date?
    let previousNotBefore: Date?
}

struct ReminderEngine {
    var saved: SavedState
    private(set) var deadlines: [ReminderKind: Date] = [:]
    private(set) var sittingSeconds: Double = 0
    // Runtime-only estimate. Keep the stored longestSittingSeconds key for old data.
    private var usageDay: String
    private var lastInputDate: Date?
    private var lockBeganAt: Date?
    private var usageIsAway = false
    private var resetForCurrentAbsence = false
    private static let newUsageSessionAfter: TimeInterval = 5 * 60
    private(set) var lastTick: Date
    var paused = false
    var pausedUntil: Date?
    var sleeping = false
    var onBreak = false
    private(set) var busyUntil: Date?
    private(set) var foregroundBlocked = false
    private var foregroundPauseUpdatedAt: Date?
    private var currentWorkPeriodID: UUID?
    private(set) var idle = false
    private(set) var waterUndo: WaterUndo?
    private var notBefore: [ReminderKind: Date] = [:]

    init(saved: SavedState = SavedState(), now: Date = Date()) {
        self.saved = saved
        self.saved.preferences.validate()
        self.lastTick = now
        self.usageDay = dayKey(now)
        resetDeadlines(now: now)
    }

    func isActive(at now: Date) -> Bool {
        !paused && !sleeping && !idle && !foregroundBlocked && (busyUntil == nil || busyUntil! <= now) && saved.preferences.allows(now)
    }

    mutating func resetDeadlines(now: Date) {
        foregroundPauseUpdatedAt = foregroundBlocked ? now : nil
        notBefore = notBefore.filter { $0.value > now }
        for kind in ReminderKind.allCases {
            deadlines[kind] = max(now.addingTimeInterval(Double(saved.preferences[kind].intervalMinutes * 60)), notBefore[kind] ?? .distantPast)
        }
    }

    mutating func updatePreferences(_ preferences: Preferences, now: Date) {
        shiftForegroundDeadlines(to: now)
        var value = preferences
        value.validate()
        let previous = saved.preferences
        saved.preferences = value
        for kind in ReminderKind.allCases where previous[kind] != value[kind] {
            deadlines[kind] = now.addingTimeInterval(Double(value[kind].intervalMinutes * 60))
            notBefore[kind] = nil
        }
        if previous.workHoursOnly != value.workHoursOnly || previous.weekdaysOnly != value.weekdaysOnly || previous.startHour != value.startHour || previous.endHour != value.endHour {
            resetDeadlines(now: now)
        }
    }

    mutating func setPaused(_ value: Bool, until: Date? = nil, now: Date) {
        refreshUsageDay(at: now)
        paused = value
        pausedUntil = value ? until : nil
        lastTick = now
        currentWorkPeriodID = nil
        resetDeadlines(now: now)
    }

    mutating func setBusy(minutes: Int?, now: Date) {
        refreshUsageDay(at: now)
        busyUntil = minutes.map { now.addingTimeInterval(Double(min(180, max(1, $0)) * 60)) }
        currentWorkPeriodID = nil
        lastTick = now
        resetDeadlines(now: now)
    }
    @discardableResult
    mutating func setForegroundBlocked(_ blocked: Bool, now: Date) -> Bool {
        guard foregroundBlocked != blocked else { return false }
        let suspended = !(0...5).contains(now.timeIntervalSince(lastTick))
        if suspended {
            resetUsageSession(at: now)
            resetDeadlines(now: now)
        } else {
            shiftForegroundDeadlines(to: now)
        }
        refreshUsageDay(at: now)
        foregroundBlocked = blocked
        foregroundPauseUpdatedAt = blocked ? now : nil
        currentWorkPeriodID = nil
        lastTick = now
        // Other pause reasons retain their existing fresh-interval behavior.
        if paused || sleeping || idle || busyUntil != nil || !saved.preferences.allows(now) {
            resetDeadlines(now: now)
        }
        return true
    }

    private mutating func shiftForegroundDeadlines(to now: Date) {
        guard let previous = foregroundPauseUpdatedAt else { return }
        let elapsed = max(0, now.timeIntervalSince(previous))
        deadlines = deadlines.mapValues { $0.addingTimeInterval(elapsed) }
        // Keep explicit snoozes from being pulled forward by reminder merging.
        notBefore = notBefore.mapValues { $0.addingTimeInterval(elapsed) }
        if let undo = waterUndo {
            waterUndo = WaterUndo(eventID: undo.eventID, day: undo.day, amount: undo.amount,
                                  previousDeadline: undo.previousDeadline?.addingTimeInterval(elapsed),
                                  previousNotBefore: undo.previousNotBefore?.addingTimeInterval(elapsed))
        }
        foregroundPauseUpdatedAt = now
    }

    mutating func setSleeping(_ value: Bool, now: Date) {
        refreshUsageDay(at: now)
        sleeping = value
        currentWorkPeriodID = nil
        lastTick = now
        if !value { resetUsageSession(at: now); resetDeadlines(now: now) }
    }

    @discardableResult
    mutating func updateIdle(secondsSinceInput: Double, sessionLocked: Bool = false, now: Date) -> Bool {
        let elapsed = secondsSinceInput.isFinite ? max(0, secondsSinceInput) : 0
        updateUsageInactivity(secondsSinceInput: elapsed, sessionLocked: sessionLocked, now: now)
        let shouldPause = sessionLocked || (saved.preferences.idlePauseEnabled && elapsed >= Double(saved.preferences.idlePauseMinutes * 60))
        guard idle != shouldPause else { return false }
        idle = shouldPause
        refreshUsageDay(at: now)
        currentWorkPeriodID = nil
        lastTick = now
        resetDeadlines(now: now)
        // The estimate may start a new session; no completed break is inferred.
        return true
    }

    private mutating func resetUsageSession(at date: Date) {
        sittingSeconds = 0
        usageDay = dayKey(date)
    }

    private mutating func refreshUsageDay(at date: Date) {
        guard usageDay != dayKey(date) else { return }
        resetUsageSession(at: date)
        currentWorkPeriodID = nil
    }

    private mutating func updateUsageInactivity(secondsSinceInput: Double, sessionLocked: Bool, now: Date) {
        if sessionLocked && lockBeganAt == nil { lockBeganAt = now }
        let longLock = lockBeganAt.map { now.timeIntervalSince($0) >= Self.newUsageSessionAfter } ?? false
        // Input may arrive just before this tick. Retain the previous aggregate
        // sample so a return at the threshold cannot hide the long absence.
        let returnedAfterLongIdle = !sessionLocked && secondsSinceInput < Self.newUsageSessionAfter
            && (lastInputDate.map { now.timeIntervalSince($0) >= Self.newUsageSessionAfter } ?? false)
        let longAbsence = secondsSinceInput >= Self.newUsageSessionAfter || longLock || returnedAfterLongIdle
        if longAbsence && !resetForCurrentAbsence {
            resetUsageSession(at: now)
            currentWorkPeriodID = nil
        }
        usageIsAway = sessionLocked || secondsSinceInput >= Self.newUsageSessionAfter
        resetForCurrentAbsence = usageIsAway && (resetForCurrentAbsence || longAbsence)
        lastInputDate = now.addingTimeInterval(-secondsSinceInput)
        if !sessionLocked { lockBeganAt = nil }
    }

    func scheduledBatches(at now: Date) -> [ReminderBatch] {
        guard isActive(at: now), !onBreak else { return [] }
        var remaining = ReminderKind.allCases.filter { saved.preferences[$0].enabled && deadlines[$0] != nil }
        remaining.sort {
            if deadlines[$0] == deadlines[$1] { return ReminderKind.allCases.firstIndex(of: $0)! < ReminderKind.allCases.firstIndex(of: $1)! }
            return deadlines[$0]! < deadlines[$1]!
        }
        var result: [ReminderBatch] = []
        let window = saved.preferences.mergeReminders ? Double(saved.preferences.mergeWindowSeconds) : 0
        while let first = remaining.first, let anchor = deadlines[first] {
            let members = remaining.filter {
                deadlines[$0]! <= anchor.addingTimeInterval(window) && (notBefore[$0] ?? .distantPast) <= anchor
            }
            // Do not move a reminder across the edge of a configured work period.
            if saved.preferences.allows(anchor) {
                result.append(ReminderBatch(kinds: ReminderKind.allCases.filter { members.contains($0) }, dueAt: anchor))
            }
            remaining.removeAll { members.contains($0) }
        }
        return result
    }

    func prewarning(at now: Date) -> ReminderBatch? {
        guard saved.preferences.prewarningEnabled,
              let batch = scheduledBatches(at: now).first else { return nil }
        let seconds = batch.dueAt.timeIntervalSince(now)
        return seconds > 0 && seconds <= Double(saved.preferences.prewarningSeconds) ? batch : nil
    }

    mutating func advance(now: Date, countReminders: Bool = true, pendingKinds: Set<ReminderKind> = []) -> [ReminderKind] {
        if let until = busyUntil, now >= until { setBusy(minutes: nil, now: now) }
        if paused, let until = pausedUntil, now >= until { setPaused(false, now: now) }
        let elapsed = now.timeIntervalSince(lastTick)
        let previousTick = lastTick
        lastTick = now
        // Large gaps mean the machine slept or the process was suspended. Never count them.
        if elapsed > 5 || elapsed < 0 {
            currentWorkPeriodID = nil
            resetUsageSession(at: now)
            resetDeadlines(now: now)
            return []
        }
        guard isActive(at: now) else {
            refreshUsageDay(at: now)
            currentWorkPeriodID = nil
            if !saved.preferences.allows(now) { resetUsageSession(at: now) }
            if foregroundBlocked && !paused && !sleeping && !idle && busyUntil == nil && saved.preferences.allows(now) {
                shiftForegroundDeadlines(to: now)
            } else {
                resetDeadlines(now: now)
            }
            return []
        }
        if !onBreak && elapsed > 0 {
            let midnight = Calendar.current.startOfDay(for: now)
            if previousTick < midnight {
                addWork(seconds: midnight.timeIntervalSince(previousTick), start: previousTick)
                sittingSeconds = 0
                currentWorkPeriodID = nil
                addWork(seconds: now.timeIntervalSince(midnight), start: midnight)
            } else { addWork(seconds: elapsed, start: previousTick) }
        } else if onBreak {
            refreshUsageDay(at: now)
            currentWorkPeriodID = nil
        }
        let due = scheduledBatches(at: now).filter { $0.dueAt <= now }.flatMap(\.kinds).filter { !pendingKinds.contains($0) }
        for kind in due {
            if countReminders { recordInteraction(.due, kind: kind, now: now) }
            deadlines[kind] = now.addingTimeInterval(Double(saved.preferences[kind].intervalMinutes * 60))
            notBefore[kind] = nil
        }
        return due
    }

    private mutating func addWork(seconds: Double, start: Date) {
        guard seconds > 0 else { return }
        refreshUsageDay(at: start)
        if !usageIsAway { sittingSeconds += seconds }
        let key = dayKey(start)
        var day = saved.days[key] ?? DayRecord()
        day.workSeconds += seconds
        day.longestSittingSeconds = max(day.longestSittingSeconds, sittingSeconds)
        let end = start.addingTimeInterval(seconds)
        var cursor = start
        while cursor < end {
            let boundary = Calendar.current.dateInterval(of: .hour, for: cursor)?.end ?? end
            let finish = min(end, boundary)
            day.hourlyWorkSeconds[Calendar.current.component(.hour, from: cursor)] += finish.timeIntervalSince(cursor)
            cursor = finish
        }
        saved.days[key] = day
        if let id = currentWorkPeriodID, let index = saved.workPeriods.indices.last,
           saved.workPeriods[index].id == id, abs(saved.workPeriods[index].end.timeIntervalSince(start)) < 0.001 {
            saved.workPeriods[index].end = end
        } else {
            let period = WorkPeriod(start: start, end: end)
            currentWorkPeriodID = period.id
            saved.workPeriods.append(period)
            saved.workPeriods = Array(saved.workPeriods.suffix(1000))
        }
    }

    mutating func recordInteraction(_ action: ReminderInteraction, kind: ReminderKind, now: Date) {
        let key = dayKey(now)
        var day = saved.days[key] ?? DayRecord()
        switch action { case .due: day.remindersDue += 1; case .snoozed: day.remindersSnoozed += 1; case .skipped: day.remindersSkipped += 1 }
        saved.days[key] = day
        saved.reminderEvents.insert(ReminderInteractionEvent(date: now, kind: kind, action: action), at: 0)
        saved.reminderEvents = Array(saved.reminderEvents.prefix(1000))
    }
    mutating func skip(_ kind: ReminderKind, now: Date) {
        shiftForegroundDeadlines(to: now)
        recordInteraction(.skipped, kind: kind, now: now)
        deadlines[kind] = now.addingTimeInterval(Double(saved.preferences[kind].intervalMinutes * 60))
        notBefore[kind] = nil
    }

    mutating func snooze(_ kind: ReminderKind, now: Date) {
        shiftForegroundDeadlines(to: now)
        let date = now.addingTimeInterval(5 * 60)
        deadlines[kind] = date
        notBefore[kind] = date
    }
    mutating func stoodUp() { sittingSeconds = 0 }

    mutating func complete(_ kind: ReminderKind, now: Date, duration: Int? = nil, waterAmount: Int? = nil) {
        shiftForegroundDeadlines(to: now)
        var day = saved.days[dayKey(now)] ?? DayRecord()
        let amount: Int
        switch kind {
        case .water:
            amount = min(1000, max(50, waterAmount ?? saved.preferences.waterML))
            day.waterML += amount
            day.waterCount += 1
        case .eyes:
            amount = duration ?? saved.preferences.eyes.durationSeconds
            day.eyeBreaks += 1
            day.breakSeconds += amount
        case .stretch:
            amount = duration ?? saved.preferences.stretch.durationSeconds
            day.stretches += 1
            day.breakSeconds += amount
            sittingSeconds = 0
        }
        saved.days[dayKey(now)] = day
        let event = ActivityEvent(date: now, kind: kind, amount: amount)
        if kind == .water {
            waterUndo = WaterUndo(eventID: event.id, day: dayKey(now), amount: amount, previousDeadline: deadlines[.water], previousNotBefore: notBefore[.water])
        }
        saved.events.insert(event, at: 0)
        saved.events = Array(saved.events.prefix(1000))
        deadlines[kind] = now.addingTimeInterval(Double(saved.preferences[kind].intervalMinutes * 60))
        notBefore[kind] = nil
    }

    @discardableResult
    mutating func undoLastWater(now: Date) -> Int? {
        shiftForegroundDeadlines(to: now)
        guard let undo = waterUndo,
              let index = saved.events.firstIndex(where: { $0.id == undo.eventID }),
              var day = saved.days[undo.day] else { return nil }
        day.waterML = max(0, day.waterML - undo.amount)
        day.waterCount = max(0, day.waterCount - 1)
        saved.days[undo.day] = day
        saved.events.remove(at: index)
        waterUndo = nil
        deadlines[.water] = max(undo.previousDeadline ?? now, now.addingTimeInterval(30))
        notBefore[.water] = undo.previousNotBefore
        return undo.amount
    }

    func upcoming(at now: Date) -> (ReminderKind, Date)? {
        guard let batch = scheduledBatches(at: now).first, let kind = batch.kinds.first else { return nil }
        return (kind, batch.dueAt)
    }
}

struct StateStore {
    let url: URL
    static var standard: StateStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StateStore(url: root.appendingPathComponent("RiseUp/state.json"))
    }
    func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }
    func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
