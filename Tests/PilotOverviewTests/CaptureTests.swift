import Foundation
import Testing
import PilotOverview

struct CaptureTests {
    @Test func cachedAgeIsExplicitAndNeverNegative() {
        let captured = Date(timeIntervalSince1970: 100)
        let thumbnail = Thumbnail(windowID: 1, state: .cached, png: Data([1]), capturedAt: captured, reason: "Window unavailable")
        #expect(thumbnail.age(at: Date(timeIntervalSince1970: 145)) == 45)
        #expect(thumbnail.age(at: Date(timeIntervalSince1970: 90)) == 0)
        #expect(thumbnail.label.contains("Cached"))
        #expect(Thumbnail(windowID: 2, state: .unavailable, png: nil, capturedAt: nil, reason: "Permission denied").age() == nil)
    }
}
