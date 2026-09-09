import Foundation
import Testing
import PilotCore

struct CoreTests {
    @Test func onlyImmutableAndExplicitProtectionsAreBlocked() throws {
        try Protection.requireMutable("com.openai.codex")
        #expect(throws: PilotError.self) { try Protection.requireMutable(Protection.pilot) }
        #expect(throws: PilotError.self) { try Protection.requireMutable("com.openai.codex", additional: ["com.openai.codex"]) }
        #expect(throws: PilotError.self) { try Protection.requireMutable("com.example.private", additional: ["com.example.private"]) }
        try Protection.requireMutable("com.apple.Safari")
    }
    @Test func atomicJSONRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("a file.json")
        try JSONFiles.write(["name": "First"], to: url)
        try JSONFiles.write(["name": "Second"], to: url)
        #expect(try JSONFiles.decode([String: String].self, from: Data(contentsOf: url)) == ["name": "Second"])
    }
}
