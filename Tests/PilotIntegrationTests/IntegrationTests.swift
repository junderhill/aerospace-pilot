import Foundation
import Testing
import PilotCore
import PilotIntegration
import PilotTestSupport

struct IntegrationTests {
    func client(_ runner: FakeProcessRunner, globalProtections: Set<String> = []) -> AeroSpaceClient {
        AeroSpaceClient(executable: URL(fileURLWithPath: "/fake/aerospace"), runner: runner, globalProtections: globalProtections)
    }
    @Test func snapshotUsesExplicitFieldsAndAcceptsAdditionalFields() async throws {
        let runner = FakeProcessRunner.healthy()
        await runner.set("list-windows", reply: .result(.init(stdout: "[{\"window-id\":17,\"app-bundle-id\":\"test.app\",\"app-name\":\"Test\",\"window-title\":\"Title\",\"workspace\":\"S\",\"monitor-id\":1,\"future\":true}]")))
        let snapshot = try await client(runner).snapshot()
        #expect(snapshot.windows.first?.bundleID == "test.app")
        let calls = await runner.calls
        #expect(calls.contains { $0.first == "list-windows" && $0.contains("%{window-id}%{app-bundle-id}%{app-name}%{window-title}%{workspace}%{monitor-id}") })
    }
    @Test(arguments: ["broken", "[{\"window-id\":1}]", "[{\"window-id\":0,\"app-bundle-id\":\"x.y\",\"app-name\":\"X\",\"window-title\":\"\",\"workspace\":\"S\",\"monitor-id\":1}]"])
    func malformedOrMissingFieldsDisableRestore(json: String) async throws {
        let runner = FakeProcessRunner.healthy()
        await runner.set("list-windows", reply: .result(.init(stdout: json)))
        let report = await HealthChecker(client: client(runner), manifest: .init(testedPairs: [])).check()
        #expect(report.state == .incompatible)
        #expect(!report.canRestore)
    }
    @Test func healthFailureStatesAndRecovery() async throws {
        let runner = FakeProcessRunner.healthy()
        for (kind, expected) in [(CommandFailure.Kind.missingExecutable, HealthReport.State.executableMissing), (.timeout, .unresponsive), (.exit, .serverUnavailable)] {
            await runner.set("list-windows", reply: .failure(CommandFailure(kind, executable: "/fake", arguments: [], detail: "Injected failure")))
            let result = await HealthChecker(client: client(runner), manifest: .init(testedPairs: [])).check()
            #expect(result.state == expected)
        }
        await runner.set("list-windows", reply: .result(.init(stdout: "[]")))
        #expect(await HealthChecker(client: client(runner), manifest: .init(testedPairs: [])).check().canRestore)
    }
    @Test func versionMismatchAndUntestedWarning() async throws {
        let runner = FakeProcessRunner.healthy()
        var report = await HealthChecker(client: client(runner), manifest: .init(testedPairs: [])).check()
        #expect(report.canRestore)
        #expect(report.warnings.contains { $0.contains("not been certified") })
        await runner.set("--version", reply: .result(.init(stdout: "aerospace CLI client version: 0.22.0-Beta a\nAeroSpace.app server version: 0.21.3-Beta b")))
        report = await HealthChecker(client: client(runner), manifest: .init(testedPairs: [])).check()
        #expect(report.state == .incompatible)
        #expect(report.message.contains("disagree"))
    }
    @Test(arguments: ["0.20.0", "0.21.3-Beta", "0.22.0-Beta", "1.0.0", "custom-build"])
    func unlistedVersionsAreNotSilentlyCertified(version: String) async throws {
        let report = await HealthChecker(client: client(.healthy(version: version)), manifest: .init(testedPairs: [VersionPair(client: "0.21.3-Beta hash", server: "0.21.3-Beta hash")])).check()
        #expect(report.canRestore)
        #expect(!report.warnings.isEmpty)
    }
    @Test func versionParserPreservesRawHashAndComponents() throws {
        let version = AeroSpaceVersion(raw: "0.21.3-Beta d56e1637")
        #expect(version.major == 0 && version.minor == 21 && version.patch == 3)
        #expect(version.prerelease == "Beta" && version.hash == "d56e1637")
        #expect(throws: PilotError.self) { try VersionPair(output: "Unknown") }
    }
    @Test func versionChangesPersistAcrossRestartWithoutDuplicateAlerts() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let old = VersionPair(client: "0.21.3-Beta a", server: "0.21.3-Beta a")
        let new = VersionPair(client: "0.22.0-Beta b", server: "0.22.0-Beta b")
        #expect(try await VersionTracker(url: url).observe(old).notice == nil)
        #expect(try await VersionTracker(url: url).observe(new).isNew)
        let tracker = VersionTracker(url: url)
        let repeated = try await tracker.observe(new)
        #expect(!repeated.isNew && repeated.notice != nil)
        try await tracker.acknowledge()
        #expect(try await tracker.observe(new).notice == nil)
    }
    @Test func processCapturesBothStreamsAndExitStatus() async throws {
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf out; printf err >&2; exit 7"], timeout: 2)
        #expect(result.status == 7 && result.stdout == "out" && result.stderr == "err")
    }
    @Test func processDeadlineAndCancellationAreBounded() async throws {
        let clock = ContinuousClock.now
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.05)
            Issue.record("Expected timeout")
        } catch let error as CommandFailure { #expect(error.kind == .timeout) }
        #expect(ContinuousClock.now - clock < .seconds(2))
        let task = Task { try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 30) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch let error as CommandFailure { #expect(error.kind == .cancelled) }
    }
    @Test func outputFloodIsBounded() async throws {
        do {
            _ = try await ProcessRunner(outputLimit: 1024).run(executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], timeout: 2)
            Issue.record("Expected output limit")
        } catch let error as CommandFailure { #expect(error.kind == .outputLimit) }
    }
    @Test func missingExecutableIsStructured() async throws {
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/missing/pilot-test"), arguments: [], timeout: 1)
            Issue.record("Expected missing executable")
        } catch let error as CommandFailure { #expect(error.kind == .missingExecutable) }
    }
    @Test func commandBoundaryRefusesProtectedMovesAndCloses() async throws {
        let runner = FakeProcessRunner.healthy()
        await runner.set("list-windows", reply: .result(.init(stdout: "[{\"window-id\":17,\"app-bundle-id\":\"com.openai.codex\",\"app-name\":\"ChatGPT\",\"window-title\":\"Private\",\"workspace\":\"S\",\"monitor-id\":1}]")))
        let configured = client(runner, globalProtections: ["com.openai.codex"])
        await #expect(throws: PilotError.self) { try await configured.move(windowID: 17, to: "T") }
        await #expect(throws: PilotError.self) { try await configured.close(windowID: 17, expectedBundleID: "com.openai.codex") }
        let calls = await runner.calls
        #expect(!calls.contains { ["close", "move-node-to-workspace"].contains($0.first ?? "") })
    }
}
