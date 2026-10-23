import Foundation

/// Advanced schedules use local wall-clock minutes. An overnight shift is split
/// explicitly across its two weekdays; legacy overnight settings remain supported.
struct WorkWindow: Codable, Equatable, Identifiable {
    var id = UUID()
    var start = 9 * 60
    var end = 12 * 60
    var label: String { "\(Self.clock(start))–\(Self.clock(end))" }
    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}
struct WeekdayRoutine: Codable, Equatable, Identifiable {
    var weekday: Int
    var enabled = true
    var windows = [WorkWindow(), WorkWindow(start: 13 * 60, end: 18 * 60)]
    var id: Int { weekday }
    var title: String { ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][min(6, max(0, weekday - 1))] }
    static var standard: [Self] { [2, 3, 4, 5, 6, 7, 1].map { Self(weekday: $0, enabled: (2...6).contains($0)) } }
    static func error(_ days: [Self]) -> String? {
        guard days.count == 7, Set(days.map(\.weekday)) == Set(1...7) else { return "每个星期需要完整且不重复的七天。" }
        for day in days where day.enabled {
            guard !day.windows.isEmpty, day.windows.count <= 4 else { return "\(day.title)请设置 1–4 个时段。" }
            let windows = day.windows.sorted { $0.start < $1.start }
            for (i, window) in windows.enumerated() {
                guard (0..<1440).contains(window.start), (1...1440).contains(window.end), window.start < window.end else { return "\(day.title)的结束时间须晚于开始时间；跨午夜请分到两天。" }
                if i > 0 && windows[i - 1].end > window.start { return "\(day.title)的时段有重叠，请调整后保存。" }
            }
        }
        return nil
    }
}
struct LongBreakRule: Codable, Equatable {
    var enabled = false
    var every = 4
    var durationSeconds = 600
    mutating func validate() { every = min(12, max(2, every)); durationSeconds = min(1800, max(60, durationSeconds)) }
}
struct PlannedBreak: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "午间走走"
    var enabled = true
    var minute = 12 * 60
    var weekdays = [2, 3, 4, 5, 6]
    var kind = ReminderKind.stretch
    var durationSeconds = 300
    var signature: String { "\(name)|\(minute)|\(weekdays.sorted().map(String.init).joined(separator: ","))|\(kind.rawValue)|\(durationSeconds)" }
    var error: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 30 { return "名称请填写 1–30 个字。" }
        if !(0..<1440).contains(minute) || !(10...1800).contains(durationSeconds) || kind == .water { return "请检查时间和时长（10 秒至 30 分钟）。" }
        if weekdays.isEmpty || !weekdays.allSatisfy({ (1...7).contains($0) }) { return "请至少选择一天。" }
        return nil
    }
    func occurrence(on date: Date, calendar: Calendar = .current) -> PlannedOccurrence? {
        guard enabled, weekdays.contains(calendar.component(.weekday, from: date)), error == nil,
              let due = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date) else { return nil }
        return PlannedOccurrence(id: "\(id.uuidString).\(dayKey(date, calendar: calendar))", ruleID: id, title: name, kind: kind, duration: durationSeconds, dueAt: due, ruleSignature: signature)
    }
}
struct PlannedOccurrence: Codable, Equatable, Identifiable {
    var id: String
    var ruleID: UUID
    var title: String
    var kind: ReminderKind
    var duration: Int
    var dueAt: Date
    var ruleSignature: String? = nil
    var resolved = false
}

enum ActivityOrigin: String, Codable { case confirmed }
struct ActivityRevision: Codable {
    var changedAt: Date
    var previousAmount: Int
    var wasVoided: Bool
}
enum TimingReason: String, Codable {
    case manualPause, manualResume, busyStart, busyEnd, foregroundStart, foregroundEnd
    case sleep, wake, idleStart, idleEnd, scheduleEnd, scheduleStart, clockGap, preferences, breakStart, breakEnd, naturalAway, newDay, awaySession, stoodUp
    var title: String {
        switch self {
        case .manualPause: return "手动暂停提醒"
        case .manualResume: return "恢复提醒，重新计算间隔"
        case .busyStart: return "进入忙碌模式"
        case .busyEnd: return "结束忙碌，重新计算间隔"
        case .foregroundStart: return "指定应用处于前台，保留剩余倒计时"
        case .foregroundEnd: return "离开指定应用，继续剩余倒计时"
        case .sleep: return "电脑进入睡眠"
        case .wake: return "电脑唤醒，开始新一轮计时"
        case .idleStart: return "空闲或锁屏，暂停提醒"
        case .idleEnd: return "返回电脑，重新计算间隔"
        case .scheduleEnd: return "提醒时段结束，暂停计时"
        case .scheduleStart: return "提醒时段开始，重新计算间隔"
        case .clockGap: return "检测到计时中断，重新计算间隔"
        case .preferences: return "提醒计划已修改"
        case .breakStart: return "开始休息，暂停工作计时"
        case .breakEnd: return "休息结束"
        case .naturalAway: return "自然离开电脑（估算）"
        case .newDay: return "新的一天，使用估算从零开始"
        case .awaySession: return "连续离开满 5 分钟，重置本轮使用估算"
        case .stoodUp: return "手动确认已起身，重置本轮使用估算"
        }
    }
}
struct TimingEvent: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var reason: TimingReason
    var seconds: Double? = nil
}

extension Preferences {
    var routineSummary: String {
        weeklyRoutineEnabled ? "按星期设置 · \(weeklyRoutine.filter(\.enabled).count) 天" : "\(weekdaysOnly ? "周一至周五" : "每天") · \(workHoursOnly ? "\(startHour):00–\(endHour):00" : "全天提醒")"
    }
}
extension ReminderEngine {
    func canNotify(at date: Date) -> Bool { !paused && !sleeping && !idle && !foregroundBlocked && (busyUntil == nil || busyUntil! <= date) }
    func plannedOccurrences(at now: Date) -> [PlannedOccurrence] {
        guard canNotify(at: now), !onBreak else { return [] }
        let signatures = Dictionary(uniqueKeysWithValues: saved.preferences.plannedBreaks.filter(\.enabled).map { ($0.id, $0.signature) })
        let current = saved.plannedHistory.filter { $0.ruleSignature != nil && $0.ruleSignature == signatures[$0.ruleID] }
        let known = Set(current.map(\.id))
        let queued = current.filter { !$0.resolved && $0.dueAt >= now.addingTimeInterval(-60) }
        var fresh: [PlannedOccurrence] = []
        for offset in 0...7 {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: now) else { continue }
            for rule in saved.preferences.plannedBreaks {
                if let occurrence = rule.occurrence(on: date), !known.contains(occurrence.id), occurrence.dueAt >= now.addingTimeInterval(-60) { fresh.append(occurrence) }
            }
        }
        return (queued + fresh).sorted { $0.dueAt < $1.dueAt }
    }
    func acceptsPlanned(_ occurrence: PlannedOccurrence, at now: Date, grace: TimeInterval = 60) -> Bool {
        guard occurrence.dueAt.timeIntervalSince(now) <= 60, now.timeIntervalSince(occurrence.dueAt) <= grace,
              let rule = saved.preferences.plannedBreaks.first(where: { $0.id == occurrence.ruleID && $0.enabled }),
              rule.signature == occurrence.ruleSignature, rule.name == occurrence.title, rule.kind == occurrence.kind, rule.durationSeconds == occurrence.duration else { return false }
        if let queued = saved.plannedHistory.last(where: { $0.id == occurrence.id && $0.ruleSignature == occurrence.ruleSignature }) {
            return !queued.resolved && queued == occurrence
        }
        guard let expected = rule.occurrence(on: occurrence.dueAt) else { return false }
        return expected == occurrence
    }
    mutating func recordPlannedDue(_ occurrence: PlannedOccurrence, now: Date) {
        guard now >= occurrence.dueAt else { return }
        let deliveryID = ReminderBatch(kinds: [occurrence.kind], dueAt: occurrence.dueAt, planned: occurrence).id
        guard !saved.reminderEvents.contains(where: { $0.action == .due && $0.plannedDeliveryID == deliveryID }) else { return }
        recordInteraction(.due, kind: occurrence.kind, now: now, plannedDeliveryID: deliveryID)
    }
    mutating func claimPlanned(_ occurrence: PlannedOccurrence, now: Date) {
        var claimed = occurrence; claimed.resolved = true
        if let index = saved.plannedHistory.firstIndex(where: { $0.id == occurrence.id }) { saved.plannedHistory[index] = claimed }
        else { saved.plannedHistory.append(claimed) }
        saved.plannedHistory = Array(saved.plannedHistory.suffix(1000))
    }
    mutating func snoozePlanned(_ occurrence: PlannedOccurrence, now: Date) {
        var queued = occurrence; queued.dueAt = now.addingTimeInterval(300); queued.resolved = false
        saved.plannedHistory.removeAll { $0.id == occurrence.id }
        saved.plannedHistory.append(queued)
        saved.plannedHistory = Array(saved.plannedHistory.suffix(1000))
    }
    mutating func note(_ reason: TimingReason, now: Date, seconds: Double? = nil) {
        saved.timingEvents.insert(TimingEvent(date: now, reason: reason, seconds: seconds), at: 0)
        saved.timingEvents = Array(saved.timingEvents.prefix(1000))
    }
    func isLongBreak(_ kind: ReminderKind) -> Bool {
        kind == .stretch && saved.preferences.longBreak.enabled && (saved.stretchCycle + 1) % saved.preferences.longBreak.every == 0
    }
    func restDuration(_ kind: ReminderKind) -> Int { isLongBreak(kind) ? saved.preferences.longBreak.durationSeconds : saved.preferences[kind].durationSeconds }

    /// Amend only the retained event's contribution, never rebuild aggregates from
    /// the capped event list. Historical corrections do not affect live deadlines.
    @discardableResult
    mutating func correctActivity(id: UUID, amount: Int?, now: Date) -> Bool {
        guard let index = saved.events.firstIndex(where: { $0.id == id }) else { return false }
        var event = saved.events[index]
        if let amount, !(event.kind == .water ? 50...1000 : 10...1800).contains(amount) { return false }
        let key = event.recordDay ?? dayKey(event.date)
        guard var day = saved.days[key] else { return false }
        let wasVoided = event.voidedAt != nil
        if !wasVoided {
            switch event.kind {
            case .water: guard day.waterCount > 0, day.waterML >= event.amount else { return false }; day.waterCount -= 1; day.waterML -= event.amount
            case .eyes: guard day.eyeBreaks > 0, day.breakSeconds >= event.amount else { return false }; day.eyeBreaks -= 1; day.breakSeconds -= event.amount
            case .stretch: guard day.stretches > 0, day.breakSeconds >= event.amount else { return false }; day.stretches -= 1; day.breakSeconds -= event.amount
            }
        }
        guard amount != nil || !wasVoided else { return false }
        event.revisions = Array(((event.revisions ?? []) + [ActivityRevision(changedAt: now, previousAmount: event.amount, wasVoided: wasVoided)]).suffix(100))
        event.voidedAt = amount == nil ? now : nil
        if let amount {
            event.amount = amount
            switch event.kind {
            case .water: day.waterML += amount; day.waterCount += 1
            case .eyes: day.eyeBreaks += 1; day.breakSeconds += amount
            case .stretch: day.stretches += 1; day.breakSeconds += amount
            }
        }
        event.recordDay = key
        saved.days[key] = day
        saved.events[index] = event
        if waterUndo?.eventID == id { invalidateWaterUndo() }
        return true
    }
}

enum ReviewPeriod: String, CaseIterable { case week = "周", month = "月" }
struct PeriodReview {
    let start: Date
    let end: Date
    let dates: [Date]
    let records: [DayRecord?]
    let previousRecords: [DayRecord?]
    let comparisonDays: Int
    let isCurrent: Bool
    let kind: ReviewPeriod
    init(kind: ReviewPeriod, offset: Int, now: Date, days: [String: DayRecord], calendar: Calendar = .current) {
        var cal = calendar; cal.firstWeekday = 2; cal.minimumDaysInFirstWeek = 4
        self.kind = kind
        let component: Calendar.Component = kind == .week ? .weekOfYear : .month
        let anchor = cal.date(byAdding: component, value: min(0, offset), to: now)!
        let interval = cal.dateInterval(of: component, for: anchor)!
        start = interval.start; end = interval.end; isCurrent = offset == 0
        let count = cal.dateComponents([.day], from: start, to: end).day!
        dates = (0..<count).map { cal.date(byAdding: .day, value: $0, to: interval.start)! }
        records = dates.map { $0 <= now ? days[dayKey($0, calendar: cal)] : nil }
        let previousStart = cal.date(byAdding: component, value: -1, to: start)!
        let previousEnd = cal.dateInterval(of: component, for: previousStart)!.end
        let previousCount = cal.dateComponents([.day], from: previousStart, to: previousEnd).day!
        // Compare complete days only, and equal numbers of calendar days for months.
        comparisonDays = min(previousCount, isCurrent ? max(0, cal.dateComponents([.day], from: start, to: cal.startOfDay(for: now)).day!) : count)
        previousRecords = (0..<comparisonDays).map { i in days[dayKey(cal.date(byAdding: .day, value: i, to: previousStart)!, calendar: cal)] }
    }
    var total: DayRecord { Self.sum(records) }
    private var pairedIndices: [Int] { (0..<comparisonDays).filter { records[$0] != nil && previousRecords[$0] != nil } }
    var matchedDays: Int { pairedIndices.count }
    var comparableTotal: DayRecord { Self.sum(pairedIndices.map { records[$0] }) }
    var previousTotal: DayRecord { Self.sum(pairedIndices.map { previousRecords[$0] }) }
    var recordedDays: Int { records.compactMap { $0 }.count }
    var canCompare: Bool { matchedDays > 0 }
    static func sum(_ records: [DayRecord?]) -> DayRecord {
        var result = DayRecord()
        for d in records.compactMap({ $0 }) { result.waterML += d.waterML; result.breakSeconds += d.breakSeconds; result.eyeBreaks += d.eyeBreaks; result.stretches += d.stretches; result.workSeconds += d.workSeconds }
        return result
    }
}
