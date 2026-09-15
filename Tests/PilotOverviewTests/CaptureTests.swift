import Foundation
import Testing
@testable import PilotOverview

struct CaptureTests {
    @Test func cachedAgeIsExplicitAndNeverNegative() {
        let captured = Date(timeIntervalSince1970: 100)
        let thumbnail = Thumbnail(windowID: 1, state: .cached, png: Data([1]), capturedAt: captured, reason: "Window unavailable")
        #expect(thumbnail.age(at: Date(timeIntervalSince1970: 145)) == 45)
        #expect(thumbnail.age(at: Date(timeIntervalSince1970: 90)) == 0)
        #expect(thumbnail.label.contains("Cached"))
        #expect(Thumbnail(windowID: 2, state: .unavailable, png: nil, capturedAt: nil, reason: "Permission denied").age() == nil)
    }

    @Test @MainActor func lateCaptureResultCannotResumeAfterDeadline() async {
        var pending: CaptureDeadline<Int>?
        do {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                pending = CaptureDeadline(continuation, after: .milliseconds(10))
            }
            Issue.record("Expected the capture deadline to expire")
        } catch {
            #expect(error.localizedDescription.contains("deadline"))
        }
        pending?.finish(.success(42)) // A late ScreenCaptureKit result must be ignored.
    }
}
