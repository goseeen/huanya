import AppKit
import CoreGraphics
import ServiceManagement
import Carbon

enum LoginItemStatus: Equatable {
    case disabled, enabled, requiresApproval, notFound
    var isSelected: Bool { self == .enabled || self == .requiresApproval }
    var description: String {
        switch self {
        case .disabled: return "已关闭"
        case .enabled: return "已开启"
        case .requiresApproval: return "等待系统允许"
        case .notFound: return "请先安装到应用程序"
        }
    }
}

@MainActor
protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor
final class SystemLoginItemManager: LoginItemManaging {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .disabled
        @unknown default: return .disabled
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
final class PreviewLoginItemManager: LoginItemManaging {
    var status: LoginItemStatus = .disabled
    func register() throws { status = .enabled }
    func unregister() throws { status = .disabled }
    func openSettings() {}
}

enum SystemActivity {
    @MainActor
    static func frontmostApplication() -> BusyApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication, let identifier = app.bundleIdentifier else { return nil }
        return BusyApplication(bundleIdentifier: identifier, name: app.localizedName ?? identifier)
    }
    static func idleSeconds() -> Double {
        // Read only the aggregate idle duration, never key or pointer contents.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
    }

    @MainActor
    static var launchedAtLogin: Bool {
        isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
    }

    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard event?.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event?.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
            || event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

// Registers only these two key combinations; it never monitors general typing.
@MainActor
final class GlobalShortcutManager {
    var onWater: (() -> Void)?
    var onRest: (() -> Void)?
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    private static let signature: OSType = 0x52735570

    func configure(enabled: Bool) -> String? {
        stop()
        guard enabled else { return nil }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr else { return result }
            return MainActor.assumeIsolated {
                guard key.signature == GlobalShortcutManager.signature else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(context).takeUnretainedValue()
                if key.id == 1 { manager.onWater?() }
                else if key.id == 2 { manager.onRest?() }
                return noErr
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { stop(); return "快捷键初始化失败（\(status)）" }
        for (index, code) in [kVK_ANSI_W, kVK_ANSI_R].enumerated() {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(code), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: Self.signature, id: UInt32(index + 1)), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            guard result == noErr, let reference else {
                stop()
                return "快捷键被占用或注册失败（\(result)），请关闭冲突快捷键后重试。"
            }
            keys.append(reference)
        }
        return nil
    }
    func stop() {
        for key in keys { UnregisterEventHotKey(key) }
        keys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
