# AeroSpace Pilot

Run `./script/build_and_run.sh --verify` to build and open the development app.

An independent macOS companion for AeroSpace. This implementation covers the Phase 1 foundation, Phase 2 CLI/health/capture infrastructure, and Phase 3 profile workflow. **Desktop certification is still pending.** The cumulative gate reports missing evidence as blocked, never passed.

## Development

1. Install Xcode with Swift 6+ and select its developer directory. The package targets macOS 14+.
2. Run `./script/bootstrap.sh`. It checks prerequisites and resolves the dependency-free Swift package; repeat runs are safe.
3. Run `./script/build_and_run.sh --verify`, or use the project's **Run** action. The app stays under `dist/`; nothing is installed or registered at login.
4. Run `./script/test.sh` and `./script/test.sh --suite contracts` for deterministic tests.
5. Run `./script/verify.sh --phase 3` for cumulative gates and evidence under `artifacts/verification/`.

Scripts resolve their own project root, so they work from a different directory and in paths containing spaces. `PILOT_AEROSPACE_PATH` selects an explicit AeroSpace executable. Ordinary tests use fakes and require neither AeroSpace nor GUI permissions. SwiftPM may need to run outside an enclosing tool sandbox so that its own sandbox can start.

`./script/build.sh` builds and stages an ad-hoc-signed app plus `dist/pilot`, the read-only diagnostics CLI, and the controlled desktop fixture/runner. `./script/doctor.sh --desktop` builds and reports connectivity, per-process permission state, displays and installed Work identities. `build_and_run.sh` supports `--verify`, `--debug`, `--logs` and `--telemetry`; it restarts only this checkout's development app.

## Use profiles

1. Select **Work** and click **Preview Restore**.
2. Resolve any ambiguous windows using the preview's window picker.
3. Click **Apply Preview**, choose how to handle **all** existing Safari windows, then confirm **Apply Work**. The dialog defaults to leaving existing Safari content in place. **Cancel** returns to the preview without restoring any apps.

Work is a boilerplate example: Safari → 1, Visual Studio Code → 2, and Calendar → 3. Install the example apps or import a profile suited to your setup before applying it. The example contains no personal URLs, document titles, or monitor preferences. `com.openai.codex` and `com.openai.chat` are immutable protections.

Profiles are human-readable JSON. **Import**, **Export**, and **Save Desktop** support portable configuration. Saved profiles and version observations live in `~/Library/Application Support/AeroSpace Pilot/`. Imports fully validate before an atomic write. Runtime window IDs are never stored in profiles. Current windows are reused; missing windows are opened through Launch Services. Multiple windows require distinct exact-title identities or an explicit selection, and changed previews require a refresh.

Exact-title identities are useful for stable document/test windows, not a generic content-restoration mechanism. The engine cannot recreate an unsaved document or a terminal session. If an app opens a window that does not match the saved title, the result remains unresolved. For multiple Safari windows, Save Desktop can capture a single shared destination; Safari windows spread across destinations require choosing one destination first.

This phase preserves validated Safari URL recipes but reports them as unsupported during apply. It supplies no URLs or terminal commands. Cleanup settings round-trip, but all unrelated-app cleanup remains inactive until Phase 4. An explicit **Close All** Safari choice uses normal AeroSpace window close and waits for the window to disappear; it never dismisses dialogs or forces a quit. A refusal/cancellation stops further Safari work. After a successful close-all with no recipe, one ordinary Safari window is reopened and placed.

The monitor policy follows AeroSpace's existing workspace mapping. An absent preferred monitor is reported, then the workspace's current available mapping is used. Pilot never moves an entire workspace to another display during profile restore.

## Health and thumbnail proof

`dist/pilot health`, `dist/pilot doctor`, `dist/pilot work`, `dist/pilot validate FILE.json`, and `dist/pilot preview [FILE.json]` are read-only. Health distinguishes missing executable, unavailable/unresponsive server, malformed responses and CLI/server mismatch. Versions/hashes are retained; changes persist across launches and untested pairs stay visibly untested. Health refreshes on startup, activation, wake, every 30 seconds while the app is open, and before apply.

The app checks Screen Recording access at startup and when it becomes active. If access is missing, click **Allow Screen Recording** and enable **AeroSpace Pilot** in System Settings → Privacy & Security → Screen Recording (called **Screen & System Audio Recording** on some macOS versions). Reopen Pilot if macOS requests it or access remains unavailable. The app rechecks access when you return from Settings; profiles remain usable without this permission.

Development builds are ad-hoc signed, so rebuilding can invalidate an earlier permission grant. If Pilot is already enabled but still reports missing access after reopening, remove the old entry and add the current `dist/AeroSpace Pilot.app` again. **Show App in Finder** reveals the current app copy.

Use **Window previews → Capture Window Previews** to request images once access is available. The capture module uses public ScreenCaptureKit, excludes Pilot's own window, never switches workspaces, and labels images fresh, cached with age, or unavailable. Permission is requested only after clicking the permission button; there is no background capture. `dist/pilot capture --output DIRECTORY [--bundle-id ID]` saves explicit capture evidence and needs permission for its own process. Real inactive-workspace image quality still needs the dedicated desktop gate.

## Workspace overview

With Pilot running, press **Control–Option–Space** from any app, or click **Workspaces** in Pilot's toolbar. The shortcut toggles a full-display overview on the display under the pointer. It shows AeroSpace workspaces, including empty ones by default, with their identifiers, monitor names, and app/window titles. Window images load progressively when Screen Recording is available; names and navigation work without it.

1. Type a workspace identifier, app name, or window title to filter the cards.
2. Click a workspace heading to switch to it, or a window preview to focus that window. Up/Down selects a workspace; Return switches to it.
3. Press Escape, click Close, or press the shortcut again to dismiss. Opening and dismissing the overview does not move or close any windows.

Use **View options** in the overview header to persist **Group workspaces by monitor** and **Hide empty workspaces**. Monitor grouping is available when AeroSpace reports more than one display; it keeps each display's workspace cards together while preserving the workspace identifiers. Hiding empty workspaces also removes workspaces that contain only Pilot's own window.

The shortcut is active only while Pilot is running. If another app has reserved it, Pilot shows a warning and the toolbar/menu action remains available. The panel opens on the display under the pointer; with monitor grouping enabled, workspace cards are organized by AeroSpace display. It does not create a native macOS full-screen Space. Refresh reloads the desktop snapshot. A changed or closed selection is reported instead of blindly switching to a stale window ID. Images stay in memory and are discarded when the overview closes. Real inactive-workspace image quality still depends on ScreenCaptureKit availability and the pending desktop capture matrix.

Profiles run without importing the overview module; the capture module does not depend on profiles.

## Verification and remaining work

See the [profile schema](docs/PROFILE-SCHEMA.md) and desktop testing instructions below. Every required phase check is named in `verification/phases.json`. Reports include source digest, Git state, toolchain, OS, versions, environment, test counts, and logs. Exit codes are **0 passed, 1 failed, 3 blocked**. Hosted CI does not certify desktop behavior.

GitHub Actions is the selected CI host. Its workflow is checked in; no successful hosted run is claimed. No upstream AeroSpace source was changed.

## Desktop testing

Use a disposable logged-in macOS account for tests that launch or move windows or touch Safari.

1. Enable AeroSpace and its Accessibility permission, then run `./script/build.sh`.
2. Run `PILOT_DESKTOP_TEST_SESSION=1 ./script/test.sh --suite desktop` for controlled fixture tests. Keep the reserved `pilot-test-*` workspaces empty.
3. For capture checks, grant Screen Recording to the desktop runner. The full capture matrix requires two physical displays and remains pending.
4. Install the bundled example apps before running the Work lane. `PILOT_DESKTOP_TEST_SESSION=1 PILOT_ALLOW_WORK_RESTORE=1 ./script/verify.sh --phase 3` authorizes example-profile placement and Safari move-all in that test account. It leaves the resulting arrangement in place.

Personal profiles, planning notes, and local review evidence are excluded from Git. Keep additional private development material under `.local/`; keep shared examples free of personal configuration.
