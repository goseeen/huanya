import AppKit
import SwiftUI
import UserNotifications
import Combine

struct ActiveBreak {
    let kind: ReminderKind
    let endsAt: Date
    let duration: Int
}

@MainActor
final class AppModel: ObservableObject {
    @Published var engine: ReminderEngine
    @Published var now: Date
    @Published var page = "今日概览"
    @Published var notificationStatus = "尚未开启"
    @Published var notice: String?
    @Published private(set) var reminderKinds: [ReminderKind] = []
    @Published private(set) var prewarning: ReminderBatch?
    @Published private(set) var activeBreak: ActiveBreak?
    @Published private(set) var launchAtLoginStatus = LoginItemStatus.disabled
    @Published private(set) var foregroundApplication: BusyApplication?
    @Published private(set) var stretchCard = StretchCard.shoulders
    @Published var shortcutStatus = "已关闭"
    var configureShortcuts: ((Bool) -> String?)?
    private var nextStretchCard = 0
    private static let stretchCardInterval: TimeInterval = 20
    private var nextStretchCardSwitch: Date?
    private var lastStretchCardUpdate: Date?
    var presentReminder: (() -> Void)?
    var hideReminder: (() -> Void)?
    var presentPrewarning: (() -> Void)?
    var hidePrewarning: (() -> Void)?
    var showMainWindow: (() -> Void)?
    private var timer: Timer?
    private let store: StateStore
    private var canSave = true
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var inactiveSources = Set<String>()
    private var dismissedPrewarnings = Set<String>()
    private let clock: () -> Date
    let isPreview: Bool
    private let loginManager: LoginItemManaging
    private let allowLoginChanges: Bool
    private var scheduled: [String: Date] = [:]
    private(set) var notificationsAllowed = false

    init(preview: Bool = false, clock: @escaping () -> Date = Date.init, loginManager: LoginItemManaging? = nil) {
        self.isPreview = preview
        self.clock = clock
        self.allowLoginChanges = !preview || loginManager != nil
        self.loginManager = loginManager ?? (preview ? PreviewLoginItemManager() : SystemLoginItemManager())
        store = .standard
        var saved = SavedState()
        var loadError: String?
        if !preview {
            do { saved = try store.load() }
            catch { loadError = "本机数据读取失败。原文件已保留，本次不会覆盖。\(error.localizedDescription)" }
        }
        let initialNow = clock()
        now = initialNow
        engine = ReminderEngine(saved: saved, now: initialNow)
        if let error = loadError { canSave = false; notice = error }
        if preview {
            for offset in 0..<7 {
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: now)!
                engine.saved.days[dayKey(date)] = DayRecord(waterML: [1250,1750,1500,2000,1000,750,1500][offset], waterCount: 5, eyeBreaks: 4, stretches: 2, workSeconds: Double([12600,18900,16500,21000,10800,7200,17000][offset]), breakSeconds: 200, longestSittingSeconds: 2400)
                let key = dayKey(date)
                var remaining = engine.saved.days[key]!.workSeconds
                for hour in 9..<18 {
                    let amount = min(3600, remaining)
                    engine.saved.days[key]!.hourlyWorkSeconds[hour] = amount
                    remaining -= amount
                }
                engine.saved.days[key]!.remindersDue = 14 + offset
                engine.saved.days[key]!.remindersSnoozed = 3
                engine.saved.days[key]!.remindersSkipped = 1
            }
            let dayStart = Calendar.current.startOfDay(for: now)
            engine.saved.workPeriods = [WorkPeriod(start: dayStart.addingTimeInterval(9 * 3600 + 600), end: dayStart.addingTimeInterval(10 * 3600 + 300)), WorkPeriod(start: dayStart.addingTimeInterval(11 * 3600 + 900), end: dayStart.addingTimeInterval(11 * 3600 + 3000))]
            engine.saved.events = [ActivityEvent(date: now.addingTimeInterval(-360), kind: .water, amount: 250), ActivityEvent(date: now.addingTimeInterval(-1200), kind: .eyes, amount: 20), ActivityEvent(date: now.addingTimeInterval(-2700), kind: .stretch, amount: 60)]
        }
        refreshLoginStatus()
    }

    var currentReminder: ReminderKind? { activeBreak?.kind ?? reminderKinds.first }
    var preferences: Preferences { engine.saved.preferences }
    var today: DayRecord { engine.saved.days[dayKey(now)] ?? DayRecord() }
    var todayEvents: [ActivityEvent] { engine.saved.events.filter { Calendar.current.isDate($0.date, inSameDayAs: now) } }
    var canUndoWater: Bool { engine.waterUndo != nil }
    var reminderPanelHeight: CGFloat {
        let card = preferences.stretchCardsEnabled && reminderKinds.contains(.stretch)
        let ideal: CGFloat = reminderKinds.count > 1 ? CGFloat(230 + reminderKinds.count * 150 + (card ? 80 : 0)) : (currentReminder == .water ? 510 : card ? 630 : 480)
        return min(ideal, (NSScreen.main?.visibleFrame.height ?? 900) - 40)
    }
    var sessionLocked: Bool { !inactiveSources.isEmpty }
    var status: String {
        if engine.sleeping { return "电脑睡眠中" }
        if sessionLocked { return "锁屏 / 会话暂停" }
        if activeBreak != nil { return "正在休息" }
        if engine.paused { return "提醒已暂停" }
        if let until = engine.busyUntil, until > now { return "忙碌中 · 剩余 \(clockText(Int(ceil(until.timeIntervalSince(now)))))" }
        if engine.foregroundBlocked { return "\(foregroundApplication?.name ?? "指定应用")使用中 · 暂停" }
        if engine.idle { return "空闲中 · 自动暂停" }
        if !preferences.allows(now) { return "非提醒时段" }
        return "好状态，进行中"
    }
    var nextBatch: ReminderBatch? { engine.scheduledBatches(at: now).first }
    var countdown: String {
        guard let batch = nextBatch else { return "— —" }
        return clockText(max(0, Int(ceil(batch.dueAt.timeIntervalSince(now)))))
    }
    var nextKind: ReminderKind? { nextBatch?.kinds.first }
    var breakRemaining: Int { max(0, Int(ceil((activeBreak?.endsAt ?? now).timeIntervalSince(now)))) }
    var prewarningRemaining: Int { max(0, Int(ceil((prewarning?.dueAt ?? now).timeIntervalSince(now)))) }
    var hasManualPause: Bool { engine.paused || (engine.busyUntil.map { $0 > now } ?? false) }
    var menuBarText: String {
        if activeBreak != nil { return "休息 \(clockText(breakRemaining))" }
        if engine.paused { return "暂停" }
        if let until = engine.busyUntil, until > now { return "忙碌 \(clockText(Int(ceil(until.timeIntervalSince(now)))))" }
        if engine.foregroundBlocked { return "忙碌" }
        if engine.idle || engine.sleeping { return "暂停" }
        return nextBatch == nil ? "—" : countdown
    }
    var longWorkPeriods: [WorkPeriod] {
        engine.saved.workPeriods.filter { Calendar.current.isDate($0.start, inSameDayAs: now) && $0.seconds >= 20 * 60 }.sorted { $0.seconds > $1.seconds }
    }

    func start() {
        guard !isPreview else { return }
        refreshNotificationStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.15
        RunLoop.main.add(timer!, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.engine.setSleeping(true, now: self.clock())
                self.dismissReminder(snooze: true, recordInteraction: false)
                self.clearPrewarning()
                self.syncNotifications()
                self.save()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.engine.setSleeping(false, now: self.clock())
                self.tick()
                self.refreshNotificationStatus()
            }
        })
        for (name, key, inactive) in [
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
            (NSWorkspace.screensDidSleepNotification, "display", true),
            (NSWorkspace.screensDidWakeNotification, "display", false)
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSessionInactive(inactive, source: key) }
            })
        }
        // macOS lock notifications complement workspace display/session changes.
        for (name, inactive) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSessionInactive(inactive, source: "lock") }
            })
        }
        tick()
    }

    func setSessionInactive(_ inactive: Bool, source: String = "lock") {
        if inactive { inactiveSources.insert(source) } else { inactiveSources.remove(source) }
        tick()
    }

    func tick(idleSeconds: Double? = nil) {
        now = clock()
        if !isPreview { updateForegroundApplication(SystemActivity.frontmostApplication()) }
        let changed = engine.updateIdle(secondsSinceInput: idleSeconds ?? (isPreview ? 0 : SystemActivity.idleSeconds()), sessionLocked: sessionLocked, now: now)
        if changed {
            clearPrewarning()
            if engine.idle {
                // Keep an explicitly started break pending confirmation, but do not
                // count inactive time as a completed break or show stale reminders.
                reminderKinds = activeBreak.map { [$0.kind] } ?? []
                hideReminder?()
            } else if !reminderKinds.isEmpty && engine.isActive(at: now) {
                presentReminder?()
            }
        }
        let due = engine.advance(now: now, countReminders: preferences.floatingReminder || notificationsAllowed, pendingKinds: Set(reminderKinds))
        ticks += 1
        if ticks % 30 == 0 { save() }
        if ticks % 60 == 0 { refreshNotificationStatus(); refreshLoginStatus() }
        if !engine.isActive(at: now) {
            clearPrewarning()
            if activeBreak == nil && !reminderKinds.isEmpty { reminderKinds.removeAll(); hideReminder?() }
        } else if !due.isEmpty && preferences.floatingReminder {
            clearPrewarning()
            show(kinds: due, playSound: true)
        }
        updateStretchCardRotation()
        updatePrewarning()
        syncNotifications()
    }

    func editPreferences(_ change: (inout Preferences) -> Void) {
        var updated = preferences
        change(&updated)
        now = clock()
        let shortcutsChanged = updated.globalShortcutsEnabled != preferences.globalShortcutsEnabled
        let cardsChanged = updated.stretchCardsEnabled != preferences.stretchCardsEnabled
        engine.updatePreferences(updated, now: now)
        if cardsChanged {
            nextStretchCardSwitch = nil
            if preferences.stretchCardsEnabled { restartStretchCardRotation(at: now) }
        }
        updateForegroundApplication(foregroundApplication)
        if shortcutsChanged { applyShortcutPreference() }
        reminderKinds.removeAll { !engine.saved.preferences[$0].enabled && activeBreak?.kind != $0 }
        if reminderKinds.isEmpty { hideReminder?() }
        clearPrewarning()
        if !isPreview { tick() }
        save()
        syncNotifications()
    }

    func togglePause(minutes: Int? = nil) {
        if hasManualPause { resumeReminders(); return }
        let pause = !engine.paused
        dismissReminder(snooze: false)
        now = clock()
        engine.setPaused(pause, until: pause ? minutes.map { now.addingTimeInterval(Double($0 * 60)) } : nil, now: now)
        clearPrewarning()
        syncNotifications()
    }

    func startBusy(minutes: Int) {
        now = clock()
        dismissReminder(snooze: false)
        engine.setBusy(minutes: minutes, now: now)
        clearPrewarning()
        notice = "忙碌模式已开启，\(minutes) 分钟后自动恢复；手动暂停会保持。"
        syncNotifications()
    }
    func resumeReminders() {
        now = clock()
        engine.setBusy(minutes: nil, now: now)
        engine.setPaused(false, now: now)
        clearPrewarning()
        syncNotifications()
    }
    func endBusy() {
        now = clock()
        engine.setBusy(minutes: nil, now: now)
        clearPrewarning()
        syncNotifications()
    }
    func updateForegroundApplication(_ application: BusyApplication?) {
        foregroundApplication = application
        let blocked = application.map { app in preferences.busyApplications.contains { $0.bundleIdentifier == app.bundleIdentifier } } ?? false
        guard engine.setForegroundBlocked(blocked, now: clock()) else { return }
        clearPrewarning()
        if blocked {
            nextStretchCardSwitch = nil
            reminderKinds = activeBreak.map { [$0.kind] } ?? []
            hideReminder?()
        }
        else if activeBreak != nil && engine.isActive(at: clock()) { presentReminder?() }
        syncNotifications()
    }
    func chooseBusyApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择需要暂停提醒的应用"
        panel.prompt = "添加应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
        guard identifier != Bundle.main.bundleIdentifier && !identifier.hasPrefix("app.riseup.") else { notice = "缓芽自身无需加入暂停列表。"; return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        editPreferences { $0.busyApplications.append(BusyApplication(bundleIdentifier: identifier, name: name)) }
    }
    func applyShortcutPreference() {
        guard !isPreview else { shortcutStatus = "预览不会注册全局快捷键"; return }
        if let error = configureShortcuts?(preferences.globalShortcutsEnabled) { shortcutStatus = error }
        else { shortcutStatus = preferences.globalShortcutsEnabled ? "已开启" : "已关闭" }
    }
    func cycleStretchCard() {
        stretchCard = StretchCard(rawValue: (stretchCard.rawValue + 1) % StretchCard.allCases.count)!
        restartStretchCardRotation(at: clock())
    }
    private func restartStretchCardRotation(at date: Date) {
        nextStretchCardSwitch = date.addingTimeInterval(Self.stretchCardInterval)
        lastStretchCardUpdate = date
    }
    private func updateStretchCardRotation() {
        let date = now
        defer { lastStretchCardUpdate = date }
        guard preferences.stretchCardsEnabled, reminderKinds.contains(.stretch),
              !engine.idle, !engine.sleeping, !sessionLocked, !engine.foregroundBlocked,
              activeBreak.map({ $0.kind == .stretch && $0.endsAt > date }) ?? true else {
            nextStretchCardSwitch = nil
            return
        }
        // Hidden time and suspended processes must not skip through unseen cards.
        if let previous = lastStretchCardUpdate, !(0...5).contains(date.timeIntervalSince(previous)) {
            restartStretchCardRotation(at: date)
            return
        }
        guard let deadline = nextStretchCardSwitch,
              deadline.timeIntervalSince(date) <= Self.stretchCardInterval else {
            restartStretchCardRotation(at: date)
            return
        }
        if date >= deadline { cycleStretchCard() }
    }
    func quickRest() { trigger(.stretch); startBreak(.stretch) }

    func trigger(_ kind: ReminderKind) { trigger(kinds: [kind]) }
    func trigger(kinds: [ReminderKind]) {
        now = clock()
        clearPrewarning()
        show(kinds: kinds, playSound: false)
    }
    private func show(kinds: [ReminderKind], playSound: Bool) {
        let wasEmpty = reminderKinds.isEmpty
        if kinds.contains(.stretch) && !reminderKinds.contains(.stretch) {
            stretchCard = StretchCard(rawValue: nextStretchCard % StretchCard.allCases.count)!
            nextStretchCard += 1
            restartStretchCardRotation(at: now)
        }
        reminderKinds = ReminderKind.allCases.filter { reminderKinds.contains($0) || kinds.contains($0) }
        guard !reminderKinds.isEmpty else { return }
        if wasEmpty && playSound && preferences.sound && !isPreview { NSSound(named: "Glass")?.play() }
        presentReminder?()
    }

    func startBreak(_ selected: ReminderKind? = nil) {
        guard let kind = selected ?? currentReminder, reminderKinds.contains(kind), activeBreak == nil else { return }
        if kind == .water { logWater(); return }
        now = clock()
        let duration = preferences[kind].durationSeconds
        activeBreak = ActiveBreak(kind: kind, endsAt: now.addingTimeInterval(Double(duration)), duration: duration)
        if kind == .stretch { restartStretchCardRotation(at: now) }
        engine.onBreak = true
        clearPrewarning()
        syncNotifications()
    }

    func finishReminder(_ selected: ReminderKind? = nil) {
        guard let kind = selected ?? currentReminder, reminderKinds.contains(kind) else { return }
        if kind == .water { logWater(); return }
        guard let active = activeBreak, active.kind == kind, clock() >= active.endsAt else { return }
        now = clock()
        engine.complete(kind, now: now, duration: active.duration)
        activeBreak = nil
        engine.onBreak = false
        removeReminder(kind)
        notice = "这次\(kind.short)休息已记录，带着好状态继续。"
        save()
        syncNotifications()
    }

    func logWater(amount: Int? = nil) {
        now = clock()
        let quantity = min(1000, max(50, amount ?? preferences.waterML))
        engine.complete(.water, now: now, waterAmount: quantity)
        removeReminder(.water)
        clearPrewarning()
        notice = "已记录 \(quantity) ml 饮水。"
        save()
        syncNotifications()
    }
    func undoWater() {
        now = clock()
        guard let quantity = engine.undoLastWater(now: now) else { return }
        notice = "已撤销最近一杯 \(quantity) ml 饮水。"
        save()
        syncNotifications()
    }
    func stoodUp() { engine.stoodUp(); notice = "已重置本轮使用时长。"; save() }
    private func removeReminder(_ kind: ReminderKind) {
        if kind == .stretch { nextStretchCardSwitch = nil }
        reminderKinds.removeAll { $0 == kind }
        if reminderKinds.isEmpty { hideReminder?() }
        else if engine.isActive(at: clock()) { presentReminder?() }
    }
    func dismissReminder(snooze: Bool, recordInteraction: Bool = true) {
        if snooze { for kind in reminderKinds {
            engine.snooze(kind, now: clock())
            if recordInteraction { engine.recordInteraction(.snoozed, kind: kind, now: clock()) }
        } }
        reminderKinds.removeAll()
        nextStretchCardSwitch = nil
        activeBreak = nil
        engine.onBreak = false
        hideReminder?()
        clearPrewarning()
        save()
        syncNotifications()
    }
    func snooze(_ kind: ReminderKind) {
        guard reminderKinds.contains(kind) else { return }
        engine.snooze(kind, now: clock())
        engine.recordInteraction(.snoozed, kind: kind, now: clock())
        if activeBreak?.kind == kind { activeBreak = nil; engine.onBreak = false }
        removeReminder(kind)
        save()
        syncNotifications()
    }
    func snoozeCurrent() { dismissReminder(snooze: true) }
    func skipReminder(_ selected: ReminderKind? = nil) {
        now = clock()
        let kinds = selected.map { reminderKinds.contains($0) ? [$0] : [] } ?? reminderKinds
        for kind in kinds {
            engine.skip(kind, now: now)
            if activeBreak?.kind == kind { activeBreak = nil; engine.onBreak = false }
            removeReminder(kind)
        }
        clearPrewarning()
        save()
        syncNotifications()
    }

    private func updatePrewarning() {
        dismissedPrewarnings.formIntersection(Set(engine.scheduledBatches(at: now).map(\.id)))
        guard preferences.floatingReminder, reminderKinds.isEmpty,
              let batch = engine.prewarning(at: now), !dismissedPrewarnings.contains(batch.id) else { clearPrewarning(); return }
        let changed = prewarning?.id != batch.id
        prewarning = batch
        if changed { presentPrewarning?() }
    }
    func dismissPrewarning() {
        if let id = prewarning?.id { dismissedPrewarnings.insert(id) }
        clearPrewarning()
    }
    func takePrewarningNow() {
        guard let batch = prewarning else { return }
        dismissedPrewarnings.insert(batch.id)
        trigger(kinds: batch.kinds)
    }
    private func clearPrewarning() {
        guard prewarning != nil else { return }
        prewarning = nil
        hidePrewarning?()
    }

    func refreshLoginStatus() { launchAtLoginStatus = loginManager.status }
    func setLaunchAtLogin(_ enabled: Bool) {
        guard allowLoginChanges else { notice = "预览不会更改系统登录项；安装到应用程序后可开启。"; return }
        do {
            if enabled && !loginManager.status.isSelected { try loginManager.register() }
            if !enabled && loginManager.status != .disabled { try loginManager.unregister() }
        } catch { notice = "登录时启动设置未能完成：\(error.localizedDescription)" }
        refreshLoginStatus()
        if launchAtLoginStatus == .requiresApproval { notice = "请在系统登录项设置中允许缓芽自动启动。" }
    }
    func openLoginSettings() { if !isPreview { loginManager.openSettings() } }

    func requestNotifications() {
        guard !isPreview else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.notice = "通知未能开启：\(error.localizedDescription)" }
                self?.refreshNotificationStatus()
            }
        }
    }
    func refreshNotificationStatus() {
        guard !isPreview else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                guard let self else { return }
                let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                self.notificationsAllowed = allowed
                self.notificationStatus = allowed ? "已允许" : (settings.authorizationStatus == .denied ? "系统已关闭" : "尚未开启")
                self.syncNotifications()
            }
        }
    }

    // Build requests from the same groups used by the desktop popup so the two
    // reminder modes agree about timing and membership.
    func notificationRequests(at date: Date) -> [UNNotificationRequest] {
        guard !preferences.floatingReminder, reminderKinds.isEmpty else { return [] }
        var requests: [UNNotificationRequest] = []
        for batch in engine.scheduledBatches(at: date) {
            for warning in [false, true] {
                if warning && !preferences.prewarningEnabled { continue }
                let delivery = warning ? batch.dueAt.addingTimeInterval(-Double(preferences.prewarningSeconds)) : batch.dueAt
                if warning && delivery <= date { continue }
                let content = UNMutableNotificationContent()
                content.title = warning ? "缓芽 · 稍后休息一下" : "缓芽 · \(batch.title)"
                content.body = warning ? "\(preferences.prewarningSeconds) 秒后提醒\(batch.title)，可以准备收尾了。" : (batch.kinds.count > 1 ? "这几项提醒时间接近，放在一起了。点开后分别确认。" : batch.kinds[0].message)
                content.categoryIdentifier = warning ? "prewarning" : (batch.kinds == [.water] ? "water" : "rest")
                content.userInfo = ["kinds": batch.kinds.map(\.rawValue), "prewarning": warning]
                if !warning && preferences.sound { content.sound = .default }
                let soundID = warning || !preferences.sound ? "quiet" : "sound"
                let id = "riseup.\(warning ? "warning" : "break").\(batch.id).\(soundID)"
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delivery.timeIntervalSince(date)), repeats: false)
                requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
        return requests
    }

    func syncNotifications() {
        guard !isPreview else { return }
        let date = clock()
        let center = UNUserNotificationCenter.current()
        let requests = notificationsAllowed ? notificationRequests(at: date) : []
        let desired = Set(requests.map(\.identifier))
        let inactive = !engine.isActive(at: date) || engine.onBreak || preferences.floatingReminder || !reminderKinds.isEmpty || !notificationsAllowed
        for (id, delivery) in scheduled where !desired.contains(id) {
            // Let the daemon finish delivering an item that just became due.
            if inactive || delivery > date || date.timeIntervalSince(delivery) > 5 {
                center.removePendingNotificationRequests(withIdentifiers: [id])
            }
            scheduled[id] = nil
        }
        for request in requests where scheduled[request.identifier] == nil {
            let identifier = request.identifier
            let interval = (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 1
            scheduled[request.identifier] = date.addingTimeInterval(interval)
            center.add(request) { [weak self] error in
                if let error { Task { @MainActor in
                    self?.scheduled[identifier] = nil
                    self?.notice = "系统通知安排失败：\(error.localizedDescription)"
                } }
            }
        }
    }

    func handleNotification(kinds: [ReminderKind], action: String, isPrewarning: Bool = false) {
        guard engine.isActive(at: clock()) else { return }
        let enabled = kinds.filter { preferences[$0].enabled }
        guard !enabled.isEmpty else { return }
        if action == "snooze" {
            for kind in enabled {
                engine.snooze(kind, now: clock())
                engine.recordInteraction(.snoozed, kind: kind, now: clock())
            }
            save(); syncNotifications(); return
        }
        if action == "water" && enabled == [.water] { logWater(); return }
        trigger(kinds: enabled)
        if action == "rest" && enabled.count == 1 && !isPrewarning { startBreak(enabled[0]) }
    }

    func save() {
        guard canSave, !isPreview else { return }
        do { try store.save(engine.saved) }
        catch { notice = "数据保存失败：\(error.localizedDescription)" }
    }
    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "缓芽-统计.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "\u{FEFF}日期,饮水毫升,喝水次数,护眼次数,拉伸次数,工作分钟,休息秒数,最长一轮使用估算分钟（含旧版历史估算）,到期提醒项目,延后项目,主动跳过项目" + (0..<24).map { ",\($0)时工作分钟" }.joined() + "\n"
        for key in engine.saved.days.keys.sorted() {
            let d = engine.saved.days[key]!
            csv += "\(key),\(d.waterML),\(d.waterCount),\(d.eyeBreaks),\(d.stretches),\(Int(d.workSeconds / 60)),\(d.breakSeconds),\(Int(d.longestSittingSeconds / 60)),\(d.remindersDue),\(d.remindersSnoozed),\(d.remindersSkipped)" + d.hourlyWorkSeconds.map { ",\(Int($0 / 60))" }.joined() + "\n"
        }
        do { try csv.write(to: url, atomically: true, encoding: .utf8); notice = "统计已导出。" }
        catch { notice = "导出失败：\(error.localizedDescription)" }
    }
}

func clockText(_ seconds: Int) -> String { String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
func minutesText(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
}
