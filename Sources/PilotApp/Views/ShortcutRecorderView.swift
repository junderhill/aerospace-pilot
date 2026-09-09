import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: QuickViewShortcut

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl(shortcut: shortcut)
        control.onChange = { value in context.coordinator.shortcut.wrappedValue = value }
        return control
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.shortcut = shortcut
        nsView.needsDisplay = true
    }

    final class Coordinator {
        var shortcut: Binding<QuickViewShortcut>
        init(shortcut: Binding<QuickViewShortcut>) { self.shortcut = shortcut }
    }
}

final class ShortcutRecorderControl: NSView {
    var shortcut: QuickViewShortcut
    var onChange: ((QuickViewShortcut) -> Void)?

    init(shortcut: QuickViewShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Quick View keyboard shortcut")
        setAccessibilityValue(shortcut.displayLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        let keyCode = UInt32(event.keyCode)
        let name = Self.keyNames[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(keyCode)"
        let value = QuickViewShortcut(keyCode: keyCode, modifiers: modifiers, keyName: name)
        shortcut = value
        onChange?(value)
        setAccessibilityValue(value.displayLabel)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = isWindowFirstResponder ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSString(string: shortcut.displayLabel)
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    private var isWindowFirstResponder: Bool {
        window?.firstResponder === self
    }

    private static let keyNames: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        76: "Enter", 117: "Forward Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}
