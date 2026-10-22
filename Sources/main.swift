import AppKit
import SwiftUI
import UserNotifications
import Combine
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var model: AppModel!
    var mainWindow: NSWindow!
    var reminderWindow: NSPanel!
    var prewarningWindow: NSPanel!
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var activity: NSObjectProtocol?
    private let shortcuts = GlobalShortcutManager()
    private var statusObservation: AnyCancellable?
    private let captureIndex = CommandLine.arguments.firstIndex(of: "--capture")
    private var captureDirectory: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = captureIndex, CommandLine.arguments.count > index + 1 { captureDirectory = CommandLine.arguments[index + 1] }
        model = AppModel(preview: captureDirectory != nil)
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        if captureDirectory == nil { center.removeAllPendingNotificationRequests() }
        let snooze = UNNotificationAction(identifier: "snooze", title: "稍后 5 分钟", options: [])
        let water = UNNotificationAction(identifier: "water", title: "喝好了，记一杯", options: [])
        let rest = UNNotificationAction(identifier: "rest", title: "查看休息提醒", options: [.foreground])
        let startRest = UNNotificationAction(identifier: "rest", title: "现在休息", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "water", actions: [water, snooze], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "rest", actions: [rest, snooze], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "prewarning", actions: [startRest, snooze], intentIdentifiers: [], options: [])
        ])
        buildWindow()
        buildReminder()
        buildPrewarning()
        buildMenu()
        model.presentReminder = { [weak self] in self?.showReminder() }
        model.hideReminder = { [weak self] in self?.reminderWindow.orderOut(nil) }
        model.presentPrewarning = { [weak self] in self?.showPrewarning() }
        model.hidePrewarning = { [weak self] in self?.prewarningWindow.orderOut(nil) }
        model.showMainWindow = { [weak self] in self?.showMain() }
        shortcuts.onWater = { [weak self] in self?.model.logWater() }
        shortcuts.onRest = { [weak self] in self?.model.quickRest() }
        model.configureShortcuts = { [weak self] enabled in self?.shortcuts.configure(enabled: enabled) }
        model.applyShortcutPreference()
        statusObservation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        updateStatusItem()
        model.start()
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "按设定的间隔提供本地休息提醒")
        if let directory = captureDirectory {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            mainWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.capturePage(0, directory: directory) }
        } else if !SystemActivity.launchedAtLogin {
            showMain()
        }
    }

    func buildWindow() {
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1110, height: 810), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        mainWindow.title = "缓芽 · huǎn yá"
        mainWindow.titleVisibility = .hidden
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.backgroundColor = NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1)
        mainWindow.minSize = NSSize(width: 1020, height: 750)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.delegate = self
        let root = NSHostingView(rootView: RootView(model: model).ignoresSafeArea(.container, edges: .top).background(Palette.background))
        mainWindow.contentView = root
        mainWindow.center()
        mainWindow.setFrameAutosaveName("RiseUpMainWindow")
    }

    func buildReminder() {
        reminderWindow = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 450), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        reminderWindow.isFloatingPanel = true
        reminderWindow.level = .floating
        reminderWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        reminderWindow.hidesOnDeactivate = false
        reminderWindow.isReleasedWhenClosed = false
        reminderWindow.isOpaque = false
        reminderWindow.backgroundColor = .clear
        reminderWindow.hasShadow = true
        reminderWindow.isMovableByWindowBackground = true
        reminderWindow.contentView = NSHostingView(rootView: ReminderPopup(model: model))
    }

    func buildPrewarning() {
        prewarningWindow = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 112), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        prewarningWindow.level = .floating
        prewarningWindow.isFloatingPanel = true
        prewarningWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        prewarningWindow.hidesOnDeactivate = false
        prewarningWindow.isReleasedWhenClosed = false
        prewarningWindow.isOpaque = false
        prewarningWindow.backgroundColor = .clear
        prewarningWindow.hasShadow = true
        prewarningWindow.contentView = NSHostingView(rootView: PrewarningView(model: model))
    }
    func showPrewarning() {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        prewarningWindow.setFrameOrigin(NSPoint(x: frame.maxX - 384, y: frame.maxY - 136))
        prewarningWindow.orderFrontRegardless()
    }

    func buildMenu() {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于缓芽", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "显示缓芽", action: #selector(showMain), keyEquivalent: "0")
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏缓芽", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出缓芽", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BrandArtwork.menuImage
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.toolTip = "缓芽 · 休息一下，好状态继续"
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuContent(model: model))
    }

    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.title = model.preferences.showMenuCountdown ? " \(model.menuBarText)" : ""
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.imagePosition = .imageLeading
        button.toolTip = "缓芽 · \(model.status)" + (model.nextBatch.map { " · 下次\($0.title) \(model.countdown)" } ?? "")
        button.setAccessibilityLabel(button.toolTip)
    }

    @objc func showMain() {
        model.refreshLoginStatus()
        popover?.performClose(nil)
        mainWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    @objc func showSettings() { model.page = "设置"; showMain() }
    @objc func showAbout() { NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: "缓芽 · huǎn yá", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0", .credits: NSAttributedString(string: "工作很重要，你也是。\n本地运行 · 无需登录 · 不联网")]) }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func showReminder() {
        guard !model.engine.idle, !model.sessionLocked else { return }
        popover?.performClose(nil)
        prewarningWindow?.orderOut(nil)
        reminderWindow.setContentSize(NSSize(width: 410, height: model.reminderPanelHeight))
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            reminderWindow.setFrameOrigin(NSPoint(x: frame.maxX - 434, y: frame.maxY - model.reminderPanelHeight - 24))
        } else { reminderWindow.center() }
        reminderWindow.orderFrontRegardless()
        NSAccessibility.post(element: reminderWindow as Any, notification: .announcementRequested, userInfo: [.announcement: "缓芽：\(model.reminderKinds.map(\.title).joined(separator: "，"))", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        shortcuts.stop()
        model?.save()
        if captureDirectory == nil { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions = [.banner]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let raw = (info["kinds"] as? [String]) ?? (info["kind"] as? String).map { [$0] } ?? []
        let kinds = raw.compactMap(ReminderKind.init(rawValue:))
        Task { @MainActor in self.model.handleNotification(kinds: kinds, action: response.actionIdentifier, isPrewarning: info["prewarning"] as? Bool ?? false) }
        completionHandler()
    }

    func capturePage(_ index: Int, directory: String) {
        let pages = ["今日概览", "提醒计划", "健康统计", "设置"]
        if index < pages.count {
            model.notice = nil
            model.page = pages[index]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.capture(view: self.mainWindow.contentView!, path: "\(directory)/\(index)-page.png")
                self.capturePage(index + 1, directory: directory)
            }
        } else if index == pages.count {
            model.trigger(.eyes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.capture(view: self.reminderWindow.contentView!, path: "\(directory)/4-reminder.png")
                self.model.startBreak()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.capture(view: self.reminderWindow.contentView!, path: "\(directory)/5-break.png")
                    self.captureAdditionalPreviews(directory: directory)
                }
            }
        }
    }
    func capture(view: NSView, path: String) {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)); print("Captured: \(path)") }
    }
    func captureStandalone<V: View>(_ view: V, width: CGFloat, path: String) {
        let hosting = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true).preferredColorScheme(.light))
        hosting.frame.size = hosting.fittingSize
        capture(view: hosting, path: path)
    }
    func captureAdditionalPreviews(directory: String) {
        model.dismissReminder(snooze: false)
        model.trigger(kinds: ReminderKind.allCases)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.capture(view: self.reminderWindow.contentView!, path: "\(directory)/6-merged-reminder.png")
            self.model.startBreak(.eyes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.capture(view: self.reminderWindow.contentView!, path: "\(directory)/7-merged-break.png")
                self.model.dismissReminder(snooze: false)
                self.model.logWater(amount: 350)
                self.captureStandalone(MenuContent(model: self.model), width: 303, path: "\(directory)/8-menu-cups.png")
                self.model.undoWater()
                self.captureStandalone(SettingsView(model: self.model).padding(24).background(Palette.background).foregroundStyle(Palette.ink).font(.custom("PingFang SC", size: 13)).tint(Palette.green), width: 850, path: "\(directory)/9-settings-full.png")
                let saved = self.model.engine.saved
                var demo = saved
                demo.preferences.water.intervalMinutes = 1
                demo.preferences.eyes.intervalMinutes = 2
                demo.preferences.stretch.intervalMinutes = 3
                let start = Date().addingTimeInterval(-30)
                self.model.engine = ReminderEngine(saved: demo, now: start)
                for second in 1...29 { _ = self.model.engine.advance(now: start.addingTimeInterval(Double(second))) }
                self.model.tick()
                precondition(self.prewarningWindow.isVisible, "Prewarning is displayed before the grouped break")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.capture(view: self.prewarningWindow.contentView!, path: "\(directory)/10-prewarning.png")
                    self.model.dismissPrewarning()
                    self.model.engine = ReminderEngine(saved: saved)
                    self.captureSecondBatchPreviews(directory: directory)
                }
            }
        }
    }
    func captureSecondBatchPreviews(directory: String) {
        model.trigger(.stretch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.capture(view: self.reminderWindow.contentView!, path: "\(directory)/11-stretch-guide.png")
            for index in 0..<3 {
                self.captureStandalone(StretchGuide(model: self.model).padding(20).background(Palette.background), width: 400, path: "\(directory)/12-guide-\(index).png")
                self.model.cycleStretchCard()
            }
            self.model.dismissReminder(snooze: false)
            self.model.startBusy(minutes: 30)
            self.captureStandalone(MenuContent(model: self.model), width: 303, path: "\(directory)/13-busy-menu.png")
            self.model.endBusy()
            self.captureStandalone(ReminderInsights(model: self.model).padding(20).foregroundStyle(Palette.ink).background(Palette.background), width: 790, path: "\(directory)/14-rhythm-statistics.png")
            self.captureHourlyWorkPreviews(directory: directory)
            self.model.editPreferences { $0.showMenuCountdown = true }
            self.updateStatusItem()
            precondition(self.statusItem.button?.title.contains(self.model.countdown) == true, "Menu-bar countdown is connected to native status item")
            self.capture(view: self.statusItem.button!, path: "\(directory)/15-menu-countdown.png")
            self.verifyGlobalShortcuts()
            self.model.trigger(.eyes)
            self.model.startBreak()
            self.verifyInteractionState()
            self.verifyTimedReminder()
        }
    }
    func captureHourlyWorkPreviews(directory: String) {
        var hours = Array(repeating: 0.0, count: 24)
        hours[9] = 3120
        hours[10] = 1800
        for (hour, name) in [(9, "recorded"), (0, "zero"), (23, "future")] {
            let chart = VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("各时段工作量").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("每格 1 小时 · 悬停查看详情").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                HourlyWorkChart(seconds: hours, currentHour: 10, previewHour: hour)
                HStack { Text("00:00"); Spacer(); Text("06:00"); Spacer(); Text("12:00"); Spacer(); Text("18:00"); Spacer(); Text("24:00") }
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            .padding(24).foregroundStyle(Palette.ink).background(.white)
            self.captureStandalone(chart, width: 790, path: "\(directory)/16-hourly-\(name).png")
        }
    }

    func verifyGlobalShortcuts() {
        let manager = GlobalShortcutManager()
        defer { manager.stop() }
        var water = 0
        var rest = 0
        manager.onWater = { water += 1 }
        manager.onRest = { rest += 1 }
        precondition(manager.configure(enabled: true) == nil, "Native global hotkeys register")
        let conflict = GlobalShortcutManager()
        precondition(conflict.configure(enabled: true) != nil, "Shortcut conflicts are reported")
        conflict.stop()
        for id in 1...2 {
            var event: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event) == noErr)
            guard let event else { preconditionFailure("Missing native hotkey event") }
            var key = EventHotKeyID(signature: 0x52735570, id: UInt32(id))
            precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &key) == noErr)
            precondition(SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr)
            ReleaseEvent(event)
        }
        precondition(water == 1 && rest == 1, "Native hotkey handler dispatches both actions exactly once")
        manager.stop()
        precondition(conflict.configure(enabled: true) == nil, "Turning off releases both shortcuts")
        conflict.stop()
        print("PASS: native shortcut registration, conflict reporting, Carbon action dispatch and release; menu-bar countdown")
    }
    func verifyInteractionState() {
        let before = model.today.eyeBreaks
        model.finishReminder()
        precondition(model.today.eyeBreaks == before, "Cannot complete a break before its timer")
        model.snoozeCurrent()
        precondition(model.activeBreak == nil && model.currentReminder == nil && !model.engine.onBreak)
        let water = model.today.waterML
        model.logWater()
        precondition(model.today.waterML == water + model.preferences.waterML)
        model.togglePause(minutes: 15)
        precondition(model.engine.paused && model.engine.pausedUntil != nil && model.nextKind == nil)
        model.togglePause()
        precondition(!model.engine.paused && model.nextKind != nil)
        model.editPreferences { $0.eyes.enabled = false }
        precondition(!model.preferences.eyes.enabled)
        print("PASS: native interaction smoke checks")
    }

    func verifyTimedReminder() {
        var saved = model.engine.saved
        saved.preferences.water.intervalMinutes = 1
        saved.preferences.water.enabled = true
        saved.preferences.eyes.enabled = true
        saved.preferences.eyes.durationSeconds = 10
        let start = Date().addingTimeInterval(-60)
        model.engine = ReminderEngine(saved: saved, now: start)
        for second in 1...59 { _ = model.engine.advance(now: start.addingTimeInterval(Double(second))) }
        model.tick()
        precondition(model.currentReminder == .water && reminderWindow.isVisible, "A due reminder opens the desktop popup")
        model.finishReminder()
        let breaks = model.today.eyeBreaks
        let seconds = model.today.breakSeconds
        model.trigger(.eyes)
        model.startBreak()
        mainWindow.performClose(nil)
        precondition(!mainWindow.isVisible && reminderWindow.isVisible, "Closing the dashboard keeps reminder running")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.2) {
            self.model.tick()
            precondition(self.model.breakRemaining == 0)
            self.model.finishReminder()
            precondition(self.model.today.eyeBreaks == breaks + 1)
            precondition(self.model.today.breakSeconds == seconds + 10)
            precondition(!self.model.engine.onBreak && self.model.currentReminder == nil)
            print("PASS: automatic desktop popup, background operation, real 10-second break completion")
            NSApplication.shared.terminate(nil)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
