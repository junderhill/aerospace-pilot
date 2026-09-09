import Carbon

struct QuickViewShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyName: String

    static let defaultConfiguration = QuickViewShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey),
        keyName: "Space"
    )

    var displayLabel: String {
        var label = ""
        if modifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        return label + keyName
    }
}

/// Registers a single shortcut, without monitoring other keyboard input.
@MainActor final class OverviewShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func start(configuration: QuickViewShortcut = .defaultConfiguration, action: @escaping () -> Void) -> String? {
        guard hotKey == nil else { return nil }
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x50494C54, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application-target events on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<OverviewShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return "Could not register the overview shortcut (\(status)). Use the Workspaces button." }
        let registration = RegisterEventHotKey(configuration.keyCode, configuration.modifiers,
                                              EventHotKeyID(signature: 0x50494C54, id: 1), GetApplicationEventTarget(),
                                              OptionBits(kEventHotKeyExclusive), &hotKey)
        if registration != noErr {
            stop()
            return "\(configuration.displayLabel) is unavailable or already in use. Use the Workspaces button."
        }
        return nil
    }

    func restart(configuration: QuickViewShortcut) -> String? {
        guard let action else { return nil }
        stop()
        return start(configuration: configuration, action: action)
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }
}
