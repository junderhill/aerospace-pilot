import AppKit
import ScreenCaptureKit
import PilotCore

public struct Thumbnail: Sendable {
    public enum State: String, Codable, Sendable { case fresh, cached, unavailable }
    public let windowID: Int
    public let state: State
    public let png: Data?
    public let capturedAt: Date?
    public let reason: String?
    public func age(at now: Date = Date()) -> TimeInterval? { capturedAt.map { max(0, now.timeIntervalSince($0)) } }
    public var label: String {
        switch state {
        case .fresh: "Fresh capture"
        case .cached: "Cached · \(Int(age() ?? 0)) seconds old"
        case .unavailable: reason ?? "Thumbnail unavailable"
        }
    }
    public init(windowID: Int, state: State, png: Data?, capturedAt: Date?, reason: String?) {
        self.windowID = windowID; self.state = state; self.png = png; self.capturedAt = capturedAt; self.reason = reason
    }
}

@MainActor public final class WindowCaptureService {
    private struct Entry { let window: DesktopWindow; let thumbnail: Thumbnail }
    private var cache: [Int: Entry] = [:]
    public let maximumWindows: Int
    public let maximumAge: TimeInterval
    public init(maximumWindows: Int = 60, maximumAge: TimeInterval = 60) {
        self.maximumWindows = max(1, maximumWindows); self.maximumAge = max(0, maximumAge)
    }
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    public func clear() { cache.removeAll() }

    /// Public ScreenCaptureKit only: never switch/focus workspaces to acquire a preview.
    /// No permission request, login item, disk cache, deprecated capture API or background timer.
    public func capture(_ windows: [DesktopWindow]) async -> [Thumbnail] {
        let windows = windows.filter { $0.bundleID != Protection.pilot }
        guard Self.hasPermission else {
            clear() // Do not keep showing stale captured content after permission is revoked.
            return windows.map { unavailable($0.id, "Screen Recording permission is unavailable.") }
        }
        let liveIDs = Set(windows.map(\.id))
        cache = cache.filter { liveIDs.contains($0.key) && ($0.value.thumbnail.age() ?? .infinity) <= maximumAge }
        do {
            let content = try await timedShareableContent().content
            let byID = Dictionary(content.windows.map { (Int($0.windowID), $0) }, uniquingKeysWith: { first, _ in first })
            var results: [Thumbnail] = []
            for (index, window) in windows.enumerated() {
                if Task.isCancelled { results.append(unavailable(window.id, "Capture cancelled.")); continue }
                guard index < maximumWindows else { results.append(unavailable(window.id, "Capture batch limit reached.")); continue }
                guard let source = byID[window.id], source.owningApplication?.bundleIdentifier == window.bundleID,
                      source.frame.width > 1, source.frame.height > 1 else {
                    results.append(fallback(window, reason: "Window unavailable, minimized, or no longer shareable.")); continue
                }
                do {
                    let configuration = SCStreamConfiguration()
                    let scale = min(2, 640 / max(source.frame.width, source.frame.height))
                    configuration.width = max(2, Int(source.frame.width * scale))
                    configuration.height = max(2, Int(source.frame.height * scale))
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true
                    let image = try await timedImage(filter: SCContentFilter(desktopIndependentWindow: source), configuration: configuration)
                    guard image.width > 1, image.height > 1,
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                        throw PilotError.unavailable("Capture returned no usable image.")
                    }
                    let thumbnail = Thumbnail(windowID: window.id, state: .fresh, png: png, capturedAt: Date(), reason: nil)
                    cache[window.id] = Entry(window: window, thumbnail: thumbnail)
                    if cache.count > maximumWindows, let oldest = cache.min(by: {
                        ($0.value.thumbnail.capturedAt ?? .distantPast) < ($1.value.thumbnail.capturedAt ?? .distantPast)
                    }) { cache[oldest.key] = nil }
                    results.append(thumbnail)
                } catch { results.append(fallback(window, reason: error.localizedDescription)) }
            }
            return results
        } catch { return windows.map { fallback($0, reason: error.localizedDescription) } }
    }
    private func unavailable(_ id: Int, _ reason: String) -> Thumbnail {
        Thumbnail(windowID: id, state: .unavailable, png: nil, capturedAt: nil, reason: reason)
    }
    private func fallback(_ window: DesktopWindow, reason: String) -> Thumbnail {
        guard let entry = cache[window.id], entry.window == window, (entry.thumbnail.age() ?? .infinity) <= maximumAge else {
            cache[window.id] = nil
            return unavailable(window.id, reason)
        }
        return Thumbnail(windowID: window.id, state: .cached, png: entry.thumbnail.png, capturedAt: entry.thumbnail.capturedAt, reason: reason)
    }
    private func timedShareableContent() async throws -> CaptureContent {
        try await withCheckedThrowingContinuation { continuation in
            let pending = CaptureDeadline(continuation)
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
                let transfer = content.map(CaptureContent.init)
                Task { @MainActor in
                    if let transfer { pending.finish(.success(transfer)) }
                    else { pending.finish(.failure(error ?? PilotError.unavailable("No shareable content."))) }
                }
            }
        }
    }
    private func timedImage(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            let pending = CaptureDeadline(continuation)
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                Task { @MainActor in
                    if let image { pending.finish(.success(image)) }
                    else { pending.finish(.failure(error ?? PilotError.unavailable("No captured image."))) }
                }
            }
        }
    }
}

// ScreenCaptureKit returns an immutable snapshot through a pre-concurrency ObjC API.
// Transfer that snapshot once; all consumption remains confined to the main actor.
private struct CaptureContent: @unchecked Sendable {
    let content: SCShareableContent
}

/// The callback may arrive after the deadline; resume a continuation at most once.
@MainActor private final class CaptureDeadline<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.finish(.failure(PilotError.unavailable("ScreenCaptureKit exceeded its 3-second deadline.")))
        }
    }
    func finish(_ result: Result<Value, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}
