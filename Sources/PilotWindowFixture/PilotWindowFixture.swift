import AppKit

@main struct PilotWindowFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = FixtureDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        for (index, name) in ["Pilot Fixture Red", "Pilot Fixture Green", "Pilot Fixture Blue"].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 80 + index * 70, y: 120 + index * 40, width: 480, height: 320),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = name
            let content = PatternView(frame: window.contentLayoutRect)
            content.index = index
            window.contentView = content
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor final class PatternView: NSView {
    var index = 0
    override func draw(_ dirtyRect: NSRect) {
        [NSColor.red, .green, .blue][index].setFill()
        bounds.fill()
        NSColor.white.setFill()
        NSRect(x: bounds.width * 0.25, y: bounds.height * 0.25, width: bounds.width * 0.5, height: bounds.height * 0.5).fill()
        NSColor.black.setFill()
        NSRect(x: bounds.width * 0.4, y: bounds.height * 0.4, width: bounds.width * 0.2, height: bounds.height * 0.2).fill()
    }
}
