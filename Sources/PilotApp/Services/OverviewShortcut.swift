import Carbon

/// Registers a single shortcut, without monitoring other keyboard input.
@MainActor final class OverviewShortcut {
    static let label = "⌃⌥Space"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func start(action: @escaping () -> Void) -> String? {
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
        let registration = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                                              EventHotKeyID(signature: 0x50494C54, id: 1), GetApplicationEventTarget(),
                                              OptionBits(kEventHotKeyExclusive), &hotKey)
        if registration != noErr {
            stop()
            return "Control–Option–Space is unavailable or already in use. Use the Workspaces button."
        }
        return nil
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil; action = nil
    }
}
