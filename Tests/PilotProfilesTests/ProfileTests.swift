import Foundation
import Testing
import PilotCore
import PilotProfiles
import PilotTestSupport

@MainActor struct ProfileTests {
    func window(_ id: Int = 1, bundle: String = "test.editor", title: String = "Document", workspace: String = "start") -> DesktopWindow {
        DesktopWindow(id: id, bundleID: bundle, appName: bundle, title: title, workspace: workspace)
    }
    func profile(_ assignments: [Assignment]? = nil) -> Profile {
        Profile(name: "Test", assignments: assignments ?? [Assignment(id: "editor", bundleID: "test.editor", appName: "Editor", workspace: "T")])
    }
    func engine(_ desktop: MemoryDesktop, _ apps: MemoryApplications, timeout: Double = 0.2,
                globalProtections: Set<String> = []) -> RestoreEngine {
        RestoreEngine(desktop: desktop, apps: apps, globalProtections: globalProtections,
                      windowTimeout: timeout, pollInterval: .milliseconds(5), preflight: {})
    }
    @Test func workUsesBoilerplateAppsAndNoContentRecipes() throws {
        let work = try Profile.work()
        #expect(work.assignments.map(\.workspace) == ["1", "2", "3"])
        #expect(work.assignments.map(\.bundleID) == ["com.apple.Safari", "com.microsoft.VSCode", "com.apple.iCal"])
        #expect(work.assignments.allSatisfy { $0.safariRecipe == nil })
        #expect(work.protectedBundleIDs.isEmpty)
    }
    @Test func exportImportPreservesRecipesAndProtections() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory.appendingPathComponent("profiles"))
        var work = try Profile.work()
        work.assignments[0].safariRecipe = SafariRecipe(logicalWindow: "Work", urls: ["https://example.com/"])
        work.cleanup = .init(mode: .preview, scope: .selectedWorkspaces)
        let export = directory.appendingPathComponent("Work.json")
        try store.export(work, to: export)
        let imported = try store.importProfile(from: export)
        #expect(imported == work)
        #expect(try store.list() == [work])
        #expect(!String(decoding: try Data(contentsOf: export), as: UTF8.self).contains("window-id"))
    }
    @Test func savedLayoutCanBeRenamedAndDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        let original = profile()
        let saved = try store.save(original)
        let renamed = try store.rename(original, to: "Documents")
        #expect(renamed.name == "Documents")
        #expect(try store.list().map(\.name) == ["Documents"])
        try store.delete(renamed)
        #expect(try store.list().isEmpty)
        #expect(FileManager.default.fileExists(atPath: saved.path) == false)
    }
    @Test func captureUsesConfiguredExclusionsAndCanAllowPreviouslyExcludedApps() throws {
        let snapshot = DesktopSnapshot(windows: [
            window(1, bundle: "com.openai.codex", title: "ChatGPT"),
            window(2, bundle: "test.editor", title: "Document")
        ])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let excluded = try ProfileStore(directory: directory, globalProtections: ["com.openai.codex"])
            .capture(name: "Excluded", snapshot: snapshot)
        #expect(excluded.assignments.map(\.bundleID) == ["test.editor"])
        let included = try ProfileStore(directory: directory, globalProtections: [])
            .capture(name: "Included", snapshot: snapshot)
        #expect(included.assignments.map(\.bundleID) == ["com.openai.codex", "test.editor"])
    }
    @Test func pilotIsAlwaysExcludedFromCapturedLayouts() throws {
        let snapshot = DesktopSnapshot(windows: [
            window(1, bundle: Protection.pilot, title: "AeroSpace Pilot"),
            window(2, bundle: "test.editor", title: "Document")
        ])
        let profile = try ProfileStore(directory: URL(fileURLWithPath: "/unused"))
            .capture(name: "Without Pilot", snapshot: snapshot)
        #expect(profile.assignments.map(\.bundleID) == ["test.editor"])
        #expect(profile.protectedBundleIDs == [Protection.pilot])
    }
    @Test func restorePlanSkipsConfiguredExcludedAssignments() throws {
        let assignment = Assignment(id: "chatgpt", bundleID: "com.openai.codex", appName: "ChatGPT", workspace: "C")
        let plan = try RestorePlanner(globalProtections: ["com.openai.codex"]).plan(
            Profile(name: "Test", assignments: [assignment]),
            snapshot: DesktopSnapshot(windows: [window(1, bundle: "com.openai.codex", title: "ChatGPT")])
        )
        #expect(plan.items.first?.action == .skipped)
        #expect(plan.items.first?.detail.contains("excluded") == true)
    }
    @Test func malformedUnknownAndConflictingImportsCannotPartiallyMutate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        let work = try Profile.work()
        let destination = try store.save(work)
        let initial = try Data(contentsOf: destination)
        #expect(throws: (any Error).self) { try ProfileStore.decode(Data("broken".utf8)) }
        #expect(throws: PilotError.self) { try ProfileStore.decode(Data("{\"schemaVersion\":99}".utf8)) }
        var conflict = work
        conflict.assignments[0].bundleID = Protection.pilot
        #expect(throws: PilotError.self) { try store.save(conflict) }
        #expect(try Data(contentsOf: destination) == initial)
        conflict = work
        #expect(try store.save(conflict) == destination)
        try work.validate(globalProtections: ["com.apple.Safari"])
    }
    @Test(arguments: ["javascript:alert(1)", "file:///tmp/private", "https://user:password@example.com", "not a url"])
    func unsafeRecipeIsRejected(url: String) throws {
        var work = try Profile.work()
        work.assignments[0].safariRecipe = .init(logicalWindow: "Work", urls: [url])
        #expect(throws: PilotError.self) { try work.validate() }
    }
    @Test func coldWarmAndRepeatWorkRestoreHasNoDuplicatesAndProtectsClosedChatGPT() async throws {
        let work = try Profile.work()
        let desktop = MemoryDesktop()
        let apps = MemoryApplications(desktop: desktop, installed: Set(work.assignments.map(\.bundleID)))
        let exclusions: Set<String> = ["com.openai.codex"]
        let restorer = engine(desktop, apps, globalProtections: exclusions)
        let first = try await restorer.apply(RestorePlanner(globalProtections: exclusions).plan(work, snapshot: desktop.snapshot()))
        #expect(first.allPlacementsVerified)
        #expect(apps.opened.count == 3 && !apps.running.contains("com.openai.codex"))
        let snapshot = try await desktop.snapshot()
        let again = try RestorePlanner(globalProtections: exclusions).plan(work, snapshot: snapshot)
        let second = try await restorer.apply(again, safariConsent: .init(choice: .moveAll, snapshot: snapshot))
        #expect(second.allPlacementsVerified)
        #expect(apps.opened.count == 3)
        #expect(try await desktop.snapshot().windows.count == 3)
        #expect(await desktop.moves.count == 3)
    }
    @Test func protectedOpenAppAndUnrelatedWindowsRemainUnchanged() async throws {
        let protected = window(9, bundle: "com.openai.codex", title: "Important content", workspace: "P")
        let unrelated = window(10, bundle: "other.app", workspace: "X")
        let desktop = MemoryDesktop(windows: [window(), protected, unrelated])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        apps.running = ["com.openai.codex"]
        var p = profile()
        p.cleanup = .init(mode: .automatic, scope: .entireDesktop)
        let exclusions: Set<String> = ["com.openai.codex"]
        let plan = try await RestorePlanner(globalProtections: exclusions).plan(p, snapshot: desktop.snapshot())
        #expect(plan.futureClosureCandidates == [unrelated])
        _ = try await engine(desktop, apps, globalProtections: exclusions).apply(plan)
        let after = try await desktop.snapshot()
        #expect(after.windows.contains(protected) && after.windows.contains(unrelated))
        #expect(apps.opened.isEmpty && apps.closed.isEmpty && apps.running.contains("com.openai.codex"))
    }
    @Test func runningAppWithoutWindowReopensAndWaitsForDelayedWindow() async throws {
        let desktop = MemoryDesktop()
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        apps.running = ["test.editor"]; apps.delaySnapshots = 3
        let result = try await engine(desktop, apps).apply(RestorePlanner().plan(profile(), snapshot: desktop.snapshot()))
        #expect(result.allPlacementsVerified && apps.opened == ["test.editor"])
    }
    @Test func launchFailureAndNoWindowTimeoutAreVisible() async throws {
        for fails in [true, false] {
            let desktop = MemoryDesktop()
            let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
            apps.createsWindows = false
            if fails { apps.launchFails = ["test.editor"] }
            let report = try await engine(desktop, apps, timeout: 0.02).apply(RestorePlanner().plan(profile(), snapshot: desktop.snapshot()))
            #expect(report.outcomes[0].status == .failed)
            #expect(!report.allPlacementsVerified)
        }
    }
    @Test func relaunchUsesSavedTitlesNotRuntimeIDs() async throws {
        let desktop = MemoryDesktop(windows: [window(1, title: "One", workspace: "1"), window(2, title: "Two", workspace: "2")])
        let store = ProfileStore(directory: URL(fileURLWithPath: "/unused"))
        let saved = try await store.capture(name: "Documents", snapshot: desktop.snapshot())
        let decoded = try ProfileStore.decode(JSONFiles.encode(saved))
        await desktop.replaceWindows([window(101, title: "Two"), window(102, title: "One")])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        let report = try await engine(desktop, apps).apply(RestorePlanner().plan(decoded, snapshot: desktop.snapshot()))
        #expect(report.allPlacementsVerified)
        let windows = try await desktop.snapshot().windows
        #expect(windows.first { $0.id == 101 }?.workspace == "2")
        #expect(windows.first { $0.id == 102 }?.workspace == "1")
        #expect(apps.opened.isEmpty)
    }
    @Test func ambiguityNeverMovesWithoutExplicitResolution() async throws {
        let desktop = MemoryDesktop(windows: [window(1), window(2)])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        let plan = try await RestorePlanner().plan(profile(), snapshot: desktop.snapshot())
        #expect(plan.items[0].action == .resolve)
        let restorer = engine(desktop, apps)
        let unresolved = try await restorer.apply(plan)
        #expect(unresolved.outcomes[0].status == .unresolved && apps.opened.isEmpty)
        #expect(await desktop.moves.isEmpty)
        let resolved = try await restorer.apply(plan, resolutions: [.init(assignmentID: "editor", window: window(2))])
        #expect(resolved.allPlacementsVerified)
        #expect(try await desktop.snapshot().windows.first { $0.id == 1 }?.workspace == "start")
    }
    @Test func stalePreviewStopsBeforeAnyMutation() async throws {
        let desktop = MemoryDesktop(windows: [window()])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        let plan = try await RestorePlanner().plan(profile(), snapshot: desktop.snapshot())
        await desktop.replaceWindows([window(2)])
        await #expect(throws: PilotError.self) { try await engine(desktop, apps).apply(plan) }
        #expect(await desktop.moves.isEmpty)
        #expect(apps.opened.isEmpty)
    }
    @Test(arguments: [SafariChoice.moveAll, .leaveInPlace, .cancel, .closeAll])
    func safariChoiceCoversEveryWorkspace(choice: SafariChoice) async throws {
        let safari = Protection.safari
        let original = [window(1, bundle: safari, workspace: "other"), window(2, bundle: safari, workspace: "private")]
        let desktop = MemoryDesktop(windows: original)
        let apps = MemoryApplications(desktop: desktop, installed: [safari])
        let p = profile([Assignment(id: "safari", bundleID: safari, appName: "Safari", workspace: "S")])
        let snapshot = try await desktop.snapshot()
        let report = try await engine(desktop, apps).apply(RestorePlanner().plan(p, snapshot: snapshot), safariConsent: .init(choice: choice, snapshot: snapshot))
        let after = try await desktop.snapshot().windows
        switch choice {
        case .moveAll:
            #expect(report.allPlacementsVerified && after.count == 2 && after.allSatisfy { $0.workspace == "S" })
            #expect(apps.closed.isEmpty && apps.opened.isEmpty)
        case .leaveInPlace:
            #expect(report.outcomes[0].status == .skipped && after == original)
        case .cancel:
            #expect(report.outcomes[0].status == .cancelled && after == original)
        case .closeAll:
            #expect(report.allPlacementsVerified && apps.closed == [1, 2] && after.count == 1)
            #expect(after[0].id != 1 && after[0].id != 2 && after[0].workspace == "S")
        }
    }
    @Test func safariMissingConsentOrRefusedCloseLeavesFurtherWorkUntouched() async throws {
        let desktop = MemoryDesktop(windows: [window(1, bundle: Protection.safari), window(2, bundle: Protection.safari)])
        let apps = MemoryApplications(desktop: desktop, installed: [Protection.safari])
        let p = profile([Assignment(id: "safari", bundleID: Protection.safari, appName: "Safari", workspace: "S")])
        let snapshot = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(p, snapshot: snapshot)
        let noConsent = try await engine(desktop, apps).apply(plan)
        #expect(noConsent.outcomes[0].status == .unresolved && apps.closed.isEmpty)
        apps.closeRefused = true
        let refused = try await engine(desktop, apps, timeout: 0.02).apply(plan, safariConsent: .init(choice: .closeAll, snapshot: snapshot))
        #expect(refused.outcomes[0].status == .failed)
        #expect(apps.closed == [1] && apps.opened.isEmpty)
        #expect(await desktop.moves.isEmpty)
    }
    @Test func recipesAreStoredButCannotMutateSafariInPhase3() async throws {
        let desktop = MemoryDesktop(windows: [window(1, bundle: Protection.safari)])
        let apps = MemoryApplications(desktop: desktop, installed: [Protection.safari])
        let p = profile([Assignment(bundleID: Protection.safari, appName: "Safari", workspace: "S", safariRecipe: .init(logicalWindow: "Work", urls: ["https://example.com"]))])
        let snapshot = try await desktop.snapshot()
        let report = try await engine(desktop, apps).apply(RestorePlanner().plan(p, snapshot: snapshot), safariConsent: .init(choice: .closeAll, snapshot: snapshot))
        #expect(report.outcomes[0].status == .unresolved && apps.closed.isEmpty && apps.opened.isEmpty)
    }
    @Test func placementRefusalDisappearanceAndMissingAppRemainFailures() async throws {
        for scenario in ["refuse", "disappear", "missing"] {
            let desktop = MemoryDesktop(windows: scenario == "missing" ? [] : [window()])
            if scenario == "refuse" { await desktop.refuseMoves() }
            if scenario == "disappear" { await desktop.disappearOnMove(1) }
            let apps = MemoryApplications(desktop: desktop, installed: [])
            let report = try await engine(desktop, apps).apply(RestorePlanner().plan(profile(), snapshot: desktop.snapshot()))
            #expect(report.outcomes[0].status == .failed && !report.allPlacementsVerified)
        }
    }
    @Test func missingMonitorUsesCurrentAeroSpaceMapping() async throws {
        let desktop = MemoryDesktop(windows: [window()])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        var p = profile()
        p.assignments[0].preferredMonitorName = "Disconnected display"
        let plan = try await RestorePlanner().plan(p, snapshot: desktop.snapshot())
        #expect(plan.warnings.contains { $0.contains("absent") })
        #expect(try await engine(desktop, apps).apply(plan).allPlacementsVerified)
    }
    @Test func preflightFailureBlocksAllActions() async throws {
        let desktop = MemoryDesktop(windows: [window()])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        let restorer = RestoreEngine(desktop: desktop, apps: apps, preflight: { throw PilotError.unavailable("Version changed") })
        let plan = try await RestorePlanner().plan(profile(), snapshot: desktop.snapshot())
        await #expect(throws: PilotError.self) { try await restorer.apply(plan) }
        #expect(await desktop.moves.isEmpty)
    }
    @Test func cancellationStopsRemainingAssignments() async throws {
        let desktop = MemoryDesktop()
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor", "test.other"])
        apps.createsWindows = false
        let p = profile([
            Assignment(id: "editor", bundleID: "test.editor", appName: "Editor", workspace: "T"),
            Assignment(id: "other", bundleID: "test.other", appName: "Other", workspace: "A")
        ])
        let plan = try await RestorePlanner().plan(p, snapshot: desktop.snapshot())
        let restorer = engine(desktop, apps, timeout: 3)
        let task = Task { try await restorer.apply(plan) }
        while apps.opened.isEmpty { await Task.yield() }
        task.cancel()
        let report = try await task.value
        #expect(report.outcomes.allSatisfy { $0.status == .cancelled })
        #expect(apps.opened == ["test.editor"])
        #expect(await desktop.moves.isEmpty)
    }
    @Test func safariConsentCannotBeReusedForChangedContent() async throws {
        let desktop = MemoryDesktop(windows: [window(bundle: Protection.safari, title: "Original")])
        let apps = MemoryApplications(desktop: desktop, installed: [Protection.safari])
        let old = try await desktop.snapshot()
        let consent = SafariConsent(choice: .closeAll, snapshot: old)
        await desktop.replaceWindows([window(bundle: Protection.safari, title: "Changed")])
        let p = profile([Assignment(bundleID: Protection.safari, appName: "Safari", workspace: "S")])
        let plan = try await RestorePlanner().plan(p, snapshot: desktop.snapshot())
        let report = try await engine(desktop, apps).apply(plan, safariConsent: consent)
        #expect(report.outcomes[0].status == .unresolved && apps.closed.isEmpty && apps.opened.isEmpty)
        #expect(await desktop.moves.isEmpty)
    }

    @Test func changedTitleReusesUniqueWindowAlreadyInSavedWorkspace() async throws {
        let desktop = MemoryDesktop(windows: [window(title: "", workspace: "T")])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        let p = profile([Assignment(id: "editor", bundleID: "test.editor", appName: "Editor",
                                    workspace: "T", identity: .init(exactTitle: "Old title"))])
        let snapshot = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(p, snapshot: snapshot)
        #expect(plan.items[0].action == .alreadyPlaced)
        #expect(plan.items[0].detail.contains("title changed"))
        let report = try await engine(desktop, apps).apply(plan)
        #expect(report.outcomes[0].status == .completed)
        #expect(await desktop.moves.isEmpty)
    }

    @Test func duplicateSavedEntriesAcceptTheOnlyWindowAlreadyInTheirWorkspace() async throws {
        let desktop = MemoryDesktop(windows: [window(title: "", workspace: "S")])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        let p = profile([
            Assignment(id: "first", bundleID: "test.editor", appName: "Editor", workspace: "S", identity: .init(exactTitle: "Old tab A")),
            Assignment(id: "second", bundleID: "test.editor", appName: "Editor", workspace: "S", identity: .init(exactTitle: "Old tab B"))
        ])
        let snapshot = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(p, snapshot: snapshot)
        #expect(plan.items.allSatisfy { $0.action == .alreadyPlaced })
        let report = try await engine(desktop, apps).apply(plan)
        #expect(report.outcomes.count == 2)
        #expect(report.outcomes.allSatisfy { $0.status == .completed })
        #expect(await desktop.moves.isEmpty)
        #expect(apps.opened.isEmpty)
    }

    @Test func workspaceFallbackDoesNotGuessOrStealAnotherAssignment() throws {
        let first = Assignment(id: "first", bundleID: "test.editor", appName: "Editor",
                               workspace: "T", identity: .init(exactTitle: "First"))
        let second = Assignment(id: "second", bundleID: "test.editor", appName: "Editor",
                                workspace: "U", identity: .init(exactTitle: "Second"))
        let planner = RestorePlanner()
        let reserved = try planner.plan(profile([first, second]), snapshot: .init(windows: [window(title: "Second", workspace: "T")]))
        #expect(reserved.items[0].action == .resolve)
        #expect(reserved.items[1].action == .move)
        let ambiguous = try planner.plan(profile([first]), snapshot: .init(windows: [
            window(1, title: "New A", workspace: "T"), window(2, title: "New B", workspace: "T")
        ]))
        #expect(ambiguous.items[0].action == .resolve)
        let elsewhere = try planner.plan(profile([first]), snapshot: .init(windows: [window(title: "New", workspace: "U")]))
        #expect(elsewhere.items[0].action == .resolve)
    }

    @Test func captureUsesWorkspaceMonitorAndPersistsEmptyWorkspaces() throws {
        let snapshot = DesktopSnapshot(
            windows: [DesktopWindow(id: 1, bundleID: "test.editor", appName: "Editor", title: "Document",
                                    workspace: "T", monitorID: 2)],
            workspaces: [
                Workspace(name: "T", monitorID: 1),
                Workspace(name: "Empty", monitorID: 2)
            ],
            monitors: [
                Monitor(id: 1, name: "Built-in"),
                Monitor(id: 2, name: "External")
            ]
        )
        let profile = try ProfileStore(directory: URL(fileURLWithPath: "/unused"))
            .capture(name: "Documents", snapshot: snapshot)
        #expect(profile.assignments[0].preferredMonitorName == "Built-in")
        #expect(profile.workspaces == [
            SavedWorkspace(name: "Empty", preferredMonitorName: "External"),
            SavedWorkspace(name: "T", preferredMonitorName: "Built-in")
        ])
        #expect(try ProfileStore.decode(JSONFiles.encode(profile)) == profile)
    }

    @Test func cleanupPreviewIncludesWindowlessAppsAndOnlyOptInQuitsThem() async throws {
        let desktop = MemoryDesktop(windows: [window()])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        apps.observedApplications = [
            RunningApplication(processID: 10, bundleID: "other.app", appName: "Other"),
            RunningApplication(processID: 11, bundleID: "test.editor", appName: "Editor")
        ]
        let initial = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(
            profile(),
            snapshot: initial,
            runningApplications: apps.runningApplications()
        )
        #expect(plan.cleanupCandidates.map(\.bundleID) == ["other.app"])

        let restorer = engine(desktop, apps)
        _ = try await restorer.apply(plan)
        #expect(apps.terminated.isEmpty)

        let refreshed = try await desktop.snapshot()
        let repeatPlan = try RestorePlanner().plan(
            profile(),
            snapshot: refreshed,
            runningApplications: apps.runningApplications()
        )
        let report = try await restorer.apply(repeatPlan, closeAppsOutsideLayout: true)
        #expect(apps.terminated.map(\.bundleID) == ["other.app"])
        #expect(report.cleanup.contains("1 application"))
    }

    @Test func cleanupRejectsNewOrRelaunchedProcessesWithoutQuittingAnything() async throws {
        let desktop = MemoryDesktop(windows: [window()])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        let originalDate = Date(timeIntervalSince1970: 10)
        apps.observedApplications = [
            RunningApplication(processID: 10, bundleID: "other.app", appName: "Other", launchDate: originalDate)
        ]
        let initial = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(
            profile(),
            snapshot: initial,
            runningApplications: apps.runningApplications()
        )

        apps.observedApplications = [
            RunningApplication(processID: 10, bundleID: "other.app", appName: "Other", launchDate: originalDate.addingTimeInterval(1)),
            RunningApplication(processID: 12, bundleID: "new.app", appName: "New")
        ]
        let report = try await engine(desktop, apps).apply(plan, closeAppsOutsideLayout: true)
        #expect(apps.terminated.isEmpty)
        #expect(report.cleanup.contains("changed after preview"))
    }

    @Test func cleanupRefusalAndCancellationAreReportedWithoutForceQuit() async throws {
        let desktop = MemoryDesktop(windows: [window()])
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        apps.observedApplications = [
            RunningApplication(processID: 10, bundleID: "first.app", appName: "First"),
            RunningApplication(processID: 11, bundleID: "second.app", appName: "Second")
        ]
        let initial = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(
            profile(),
            snapshot: initial,
            runningApplications: apps.runningApplications()
        )
        // The plan's candidates are both outside the saved layout.
        #expect(plan.cleanupCandidates.count == 2)

        apps.terminateRefused = true
        let refused = try await engine(desktop, apps, timeout: 0.02)
            .apply(plan, closeAppsOutsideLayout: true)
        #expect(apps.terminated.isEmpty && refused.cleanup.contains("refused"))

        let refreshed = try await desktop.snapshot()
        let repeatPlan = try RestorePlanner().plan(
            profile(),
            snapshot: refreshed,
            runningApplications: apps.runningApplications()
        )
        apps.terminateRefused = false
        let cancelledTask = Task {
            try await engine(desktop, apps, timeout: 0.02)
                .apply(repeatPlan, closeAppsOutsideLayout: true)
        }
        cancelledTask.cancel()
        let cancelled = try await cancelledTask.value
        #expect(apps.terminated.isEmpty && cancelled.cleanup.contains("cancelled"))
    }

    @Test func cleanupProtectsPilotSettingsAndManagedBundlesButAllowsOutsideSafari() async throws {
        let desktop = MemoryDesktop()
        let apps = MemoryApplications(desktop: desktop, installed: [])
        apps.observedApplications = [
            RunningApplication(processID: 1, bundleID: Protection.pilot, appName: "Pilot"),
            RunningApplication(processID: 2, bundleID: "excluded.app", appName: "Excluded"),
            RunningApplication(processID: 3, bundleID: Protection.safari, appName: "Safari"),
            RunningApplication(processID: 4, bundleID: "other.app", appName: "Other"),
            RunningApplication(processID: 5, bundleID: "test.editor", appName: "Editor")
        ]
        let initial = try await desktop.snapshot()
        let plan = try RestorePlanner(globalProtections: ["excluded.app"]).plan(
            profile(),
            snapshot: initial,
            runningApplications: apps.runningApplications()
        )
        #expect(Set(plan.cleanupCandidates.map(\.bundleID)) == Set([Protection.safari, "other.app"]))
    }

    @Test func savedWorkspaceMonitorIsRestoredAndMovesWindowsWithTheWorkspace() async throws {
        let desktop = MemoryDesktop()
        await desktop.replaceState(DesktopSnapshot(
            windows: [DesktopWindow(id: 1, bundleID: "test.editor", appName: "Editor", title: "Document",
                                    workspace: "T", monitorID: 1)],
            workspaces: [Workspace(name: "T", monitorID: 1)],
            monitors: [Monitor(id: 1, name: "Built-in"), Monitor(id: 2, name: "External")]
        ))
        let apps = MemoryApplications(desktop: desktop, installed: ["test.editor"])
        var p = profile()
        p.assignments[0].preferredMonitorName = "External"
        // Leave workspaces empty to exercise the assignment-level fallback used
        // by profiles saved before workspace mappings were introduced.
        let initial = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(p, snapshot: initial)
        #expect(plan.workspaceMonitorTargets == [SavedWorkspace(name: "T", preferredMonitorName: "External")])

        let report = try await engine(desktop, apps).apply(plan)
        let workspaceMoves = await desktop.workspaceMoves
        #expect(workspaceMoves.count == 1 && workspaceMoves[0].0 == "T" && workspaceMoves[0].1 == "External")
        #expect(report.workspaceOutcomes.first?.status == .completed)
        let after = try await desktop.snapshot()
        #expect(after.workspaces.first?.monitorID == 2 && after.windows.first?.monitorID == 2)
    }

    @Test func protectedOrUnapprovedSafariWorkspaceIsNotMovedIndirectly() async throws {
        let desktop = MemoryDesktop()
        await desktop.replaceState(DesktopSnapshot(
            windows: [DesktopWindow(id: 1, bundleID: Protection.safari, appName: "Safari", title: "Tabs",
                                    workspace: "T", monitorID: 1)],
            workspaces: [Workspace(name: "T", monitorID: 1)],
            monitors: [Monitor(id: 1, name: "Built-in"), Monitor(id: 2, name: "External")]
        ))
        let apps = MemoryApplications(desktop: desktop, installed: [Protection.safari])
        let p = Profile(
            name: "Safari",
            assignments: [Assignment(id: "safari", bundleID: Protection.safari, appName: "Safari", workspace: "T",
                                     preferredMonitorName: "External")],
            workspaces: [SavedWorkspace(name: "T", preferredMonitorName: "External")]
        )
        let snapshot = try await desktop.snapshot()
        let plan = try RestorePlanner().plan(p, snapshot: snapshot)
        let report = try await engine(desktop, apps).apply(
            plan,
            safariConsent: .init(choice: .leaveInPlace, snapshot: snapshot)
        )
        #expect(await desktop.workspaceMoves.isEmpty)
        #expect(report.workspaceOutcomes.first?.status == .skipped)
        let after = try await desktop.snapshot()
        #expect(after.workspaces.first?.monitorID == 1)
    }
}
