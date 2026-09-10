# Profile schema 1

The bundled example is `Sources/PilotProfiles/Resources/Work.json`. Files are UTF-8 JSON, with explicit schema version 1; unknown schema versions fail before any mutation.

| Field | Meaning |
| --- | --- |
| `id`, `name` | Stable profile UUID and display name. Internal filenames use UUIDs, never user-entered names. |
| `assignments` | Unique assignment ID, verified `bundleID`, `appName`, `workspace`, optional exact-title `identity`, `safariRecipe`, and `preferredMonitorName`. |
| `protectedBundleIDs` | Optional profile-specific protections. The Settings exclusions are applied at runtime and cannot be overridden by a profile import. |
| `cleanup` | `mode`: `keep`, `preview`, or `automatic`; `scope`: `managedApplications`, `selectedWorkspaces`, or `entireDesktop`. Preserved for profile compatibility; outside-app cleanup is an explicit per-apply checkbox and defaults off. |
| `workspaces` | Optional array of `{ "name": "1", "preferredMonitorName": "DELL U2723QE" }` entries. Captured workspaces include empty workspaces. Monitor IDs are never persisted; restore uses a unique currently present monitor with the same name and reports absent or ambiguous names. Older files may omit this field. |
| `monitorPolicy` | `followAeroSpace`: restore saved workspace monitor names when a unique matching display is present; otherwise leave the current mapping and report the reason. |

An identity is `{ "kind": "exactTitle", "value": "My document" }`. The exact title is an explicit matching constraint, not a saved runtime window ID and not a command to recreate content. Zero/multiple matches stay unresolved; a user may choose a current window in the preview. Selections are tied to that snapshot and discarded when the preview changes.

A Safari recipe is `{ "logicalWindow": "Work", "urls": ["https://example.com/"] }`. URLs must be distinct HTTP(S) addresses without embedded credentials. The profile validates and preserves the recipe; applying it reports the recipe as unsupported. Existing Safari content still requires an explicit all-window choice, and unapproved Safari windows prevent an indirect workspace move.

Multiple assignments for one app require distinct, nonempty exact titles. Safari's existing-content policy has one destination per profile. Profile-specific protections reject a conflicting assignment even when cleanup is set to keep. Settings exclusions skip matching assignments during restore and leave those applications unchanged.

Execution rechecks health, validates the profile, compares the desktop to the preview, and rechecks window identity and protections at action boundaries. It opens/reopens apps only if no window exists, waits for actual windows, resolves a unique identity, moves, and verifies placement. Saved workspace monitor mappings are applied after window placement and verified. If the outside-app checkbox is enabled, the preview's exact regular process identities (PID and launch date when available) receive normal termination requests after placement; process drift, new apps, refusals, cancellation, and save dialogs stop or skip cleanup without force-quitting. Completion checks run again after the last assignment. Outcomes distinguish completed placement, intentional skip, cancellation, failure and unresolved work. A skip is never reported as a verified placement.

No saved file contains runtime IDs, shell commands, exact tiling trees, existing Safari tab content, or terminal session state. Profile load/export validates before writing; replacement is atomic.
