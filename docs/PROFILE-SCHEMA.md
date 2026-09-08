# Profile schema 1

The bundled example is `Sources/PilotProfiles/Resources/Work.json`. Files are UTF-8 JSON, with explicit schema version 1; unknown schema versions fail before any mutation.

| Field | Meaning |
| --- | --- |
| `id`, `name` | Stable profile UUID and display name. Internal filenames use UUIDs, never user-entered names. |
| `assignments` | Unique assignment ID, verified `bundleID`, `appName`, `workspace`, optional exact-title `identity`, `safariRecipe`, and `preferredMonitorName`. |
| `protectedBundleIDs` | Must include `com.openai.codex` and `com.openai.chat`. Global additions also apply and cannot be overridden by import. |
| `cleanup` | `mode`: `keep`, `preview`, or `automatic`; `scope`: `managedApplications`, `selectedWorkspaces`, or `entireDesktop`. Preserved but inactive in Phase 3. |
| `monitorPolicy` | `followAeroSpace`: use the workspace's current display mapping and report an absent preferred monitor. |

An identity is `{ "kind": "exactTitle", "value": "My document" }`. The exact title is an explicit matching constraint, not a saved runtime window ID and not a command to recreate content. Zero/multiple matches stay unresolved; a user may choose a current window in the preview. Selections are tied to that snapshot and discarded when the preview changes.

A Safari recipe is `{ "logicalWindow": "Work", "urls": ["https://example.com/"] }`. URLs must be distinct HTTP(S) addresses without embedded credentials. Phase 3 validates and preserves the recipe; applying it leaves Safari unresolved and untouched until Phase 4 defines and implements content semantics.

Multiple assignments for one app require distinct, nonempty exact titles. Safari's existing-content policy has one destination per profile. Protections reject a conflicting assignment even when cleanup is set to keep.

Execution rechecks health, validates the profile, compares the desktop to the preview, and rechecks window identity and protections at action boundaries. It opens/reopens apps only if no window exists, waits for actual windows, resolves a unique identity, moves, and verifies placement. Completion checks run again after the last assignment. Outcomes distinguish completed placement, intentional skip, cancellation, failure and unresolved work. A skip is never reported as a verified placement.

No saved file contains runtime IDs, shell commands, exact tiling trees, existing Safari tab content, or terminal session state. Profile load/export validates before writing; replacement is atomic.
