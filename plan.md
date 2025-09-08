# Profiles Feature Plan

## Goals
- Add first-class “Profiles” that bundle transcription settings and post-processing behavior.
- Provide a Profiles section in Settings with CRUD (create, read, update, delete), default profile, and keyboard shortcut assignment.
- Each profile includes: title, transcription model selection, enable post-processing (checkbox), post-processing prompt (text), post-processing model selection, optional shortcut key, icon and color, app assignments.
- Post processing will be done via the Groq API/service.
- Ensure one and only one default profile exists; use it when no profile is explicitly chosen.
- Integrate profiles across the app: selection before recording/transcription, and keyboard shortcut activation.
- Persist profiles in the shared SQLite database (echo.sqlite)

## Scope
- In-scope: UI in Settings, persistence, validation, keyboard shortcut mapping, integration with transcription and post-processing pipeline, basic tests, documentation.
- Out-of-scope (for this phase): cloud sync or multi-device sync, role-based permissions, advanced shortcut sequences, team sharing.

---

## Definitions
- Profile: A saved bundle of settings: `{ id, title, isDefault, shortcut, transcriptionModel, postProcessingEnabled, postProcessingPrompt, createdAt, updatedAt }`.
- Default Profile: The profile automatically used unless another is explicitly selected. Exactly one must be default.
- Shortcut: A normalized key chord string (e.g., `cmd+1`, `ctrl+shift+p`). Optional, unique across profiles.
- App Assignment: Link a macOS app (bundleId) to a single profile.
- Profile Icon/Color: Optional visual identity used in lists and overlay.

---

## Data Model

### Type/Schema
Define Swift types for profiles that map to SQLite schema.

Profile (Swift):
```swift
struct Profile: Identifiable, Codable {
  let id: String                      // UUID v4
  var title: String                   // 1–64 chars, unique per user
  var isDefault: Bool                 // exactly one profile true
  var shortcut: String?               // normalized chord, unique if set
  var transcriptionModel: String      // enum or known model id
  var postProcessingEnabled: Bool
  var postProcessingPrompt: String    // up to 10k chars; supports {{TRANSCRIPTION}}; empty allowed if disabled
  var iconName: String?               // optional SF Symbol or asset name
  var iconColor: String?              // optional hex/system color string
  let createdAt: Date
  var updatedAt: Date
}

struct AppAssignment: Identifiable, Codable {
  var id: String { bundleId }         // Use bundleId as identifier
  let bundleId: String                // e.g., com.tinyspeck.slackmacgap
  let appName: String                 // display name at time of assign
  let profileId: String               // FK to profile
  let createdAt: Date
}
```

Validation rules:
- `title`: required, trim whitespace, 1–64 chars, unique case-insensitive.
- `isDefault`: exactly one `true` in the collection.
- `shortcut`: optional; when set must be unique and not reserved; normalized to platform-invariant representation.
- `transcriptionModel`: must be one of supported models; validate availability on device.
- `postProcessingEnabled`: if true and `postProcessingPrompt` is empty, allow save but warn (user can fill later).
- `iconName`: optional; must be valid SF Symbol or asset key when provided.
- `iconColor`: optional; must be valid hex or system color token when provided.
- App assignment uniqueness: each `bundleId` may be linked to at most one profile.
 - Prompt placeholders: exactly one supported placeholder `{{TRANSCRIPTION}}`. Unknown placeholders are rejected. If enabled and template lacks `{{TRANSCRIPTION}}`, allow save with warning 

### Storage (SQLite)
- Use a single shared SQLite DB file named `echo.sqlite` located in Application Support (`~/Library/Application Support/Echo/echo.sqlite`).
- Replace the previous JSON/config approach entirely; profiles live in SQLite tables alongside history.
- Add a `profiles` table and supporting indices. Maintain default invariants at the DB or service layer.
- Derive `defaultProfileId` at runtime by scanning `is_default = 1` (no duplicate truth).

Proposed SQL (v1):
```
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,                -- UUID v4
  title TEXT NOT NULL,
  is_default INTEGER NOT NULL CHECK (is_default IN (0,1)),
  shortcut TEXT,                      -- unique when not null
  transcription_model TEXT NOT NULL,
  post_processing_enabled INTEGER NOT NULL CHECK (post_processing_enabled IN (0,1)),
  post_processing_prompt TEXT NOT NULL,
  icon_name TEXT,
  icon_color TEXT,
  created_at REAL NOT NULL,           -- unix epoch seconds
  updated_at REAL NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_title_ci
  ON profiles(LOWER(title));

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_shortcut
  ON profiles(shortcut) WHERE shortcut IS NOT NULL;

-- Optional: enforce single default via partial unique index
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_one_default
  ON profiles(is_default)
  WHERE is_default = 1;

-- Apps assigned to profiles (an app can belong to only one profile)
CREATE TABLE IF NOT EXISTS profile_apps (
  profile_id TEXT NOT NULL,
  app_bundle_id TEXT NOT NULL,
  app_name TEXT NOT NULL,
  created_at REAL NOT NULL,
  PRIMARY KEY (profile_id, app_bundle_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_apps_bundle_unique
  ON profile_apps(app_bundle_id);

CREATE INDEX IF NOT EXISTS idx_profile_apps_profile
  ON profile_apps(profile_id);
```

### Migrations
- **Version Control**: Use SQLite's built-in `PRAGMA user_version` for schema versioning (simple, lightweight, native).
- Database file migration: if `echo_history.sqlite` exists and `echo.sqlite` does not, rename/move `echo_history.sqlite` to `echo.sqlite` to unify storage.
- Schema migrations run automatically on startup based on current `user_version`:
  - Version 0→1: Create `profiles` table (with icon columns) and indices
  - Version 1→2: Create `profile_apps` table and indices
  - Version 2→3: Future schema changes (e.g., post-processing model field)
- Data seeding: on first launch with no profiles, create a "Default" profile seeded from existing in-app settings (if any):
  - Copy current transcription model into the profile.
  - Mark as default and make the shortcut the existing system shortcut (Option+Space)
- Each migration is idempotent (safe to run multiple times) and forward-only.

---

## Keyboard Shortcuts
- Representation: canonical string `(<cmd|ctrl|alt|shift>+)*<key>`; store lowercase; platform expansion at runtime.
- Constraints: prevent duplicates, reject reserved chords (e.g., `cmd+q`, `cmd+w`) and any chords used globally by the app.
- UX: provide a “record shortcut” control; display conflicts inline; allow clearing the shortcut.
- Behavior: pressing a profile’s shortcut activates/selects that profile for the next transcription session (and optionally starts recording if applicable—configurable later).

While Recording
- Add shortcuts to switch profiles mid-recording (e.g., next/previous profile, or direct chords).
- When switching during recording, set a per-session manual override that disables automatic app-based switching until the session ends.

---

## UI/UX

### Settings > Profiles Section
- Entry point: New sidebar item `Profiles` under Settings.
- Layout:
  - Left: List of profiles with search and New button.
  - Right: Profile Editor form for selected profile.

List view:
- Shows each profile: title, model badge, post-processing toggle icon, shortcut chip, default star.
- Actions per row: Edit, Duplicate, Delete (disabled for sole remaining default until another is chosen).
- Toolbar: New Profile, Set Default, Clear Shortcut.

Editor form fields:
- Title: text input; uniqueness validation.
- Transcription Model: dropdown populated from supported models; includes availability status; shows description tooltip.
- Post-Processing: checkbox `Enable post-processing`.
- Post-Processing Prompt: multiline text area; enabled only when checkbox is on; character count; helper text including supported placeholder `{{TRANSCRIPTION}}`; quick-insert chip/button to insert placeholder.
- Shortcut: capture control with “Record”, “Stop”, “Clear”; conflict/reserved validation.
- Default toggle: radio button/checkbox to mark as Default (switching unsets previous default).
- Icon: picker for SF Symbols or app/bundle icons; preview in list and overlay.
- Color: color picker used to tint the icon/badge in UI and overlay.
- App Assignments: pane showing currently running apps with Add/Remove; search/filter; conflict messaging if already assigned to another profile.
- Save/Cancel buttons; dirty-state protection; optimistic UI with errors.

Empty state:
- If no profiles, show CTA to create Default profile (auto-filled) + explanation.

Accessibility:
- All controls keyboard accessible; ARIA labels for shortcut recorder.

### Profile Selection Outside Settings
- Quick selector in main toolbar/status area showing current active profile title; click opens a dropdown to switch profiles.
- Optional “pin favorites” (future); for now, show all profiles alphabetically with default at top.
- When switching, store `lastActiveProfileId` for session continuity.
- Overlay: show active profile icon/title tinted by its color; update live on profile change.

---

## Integration Points

### Transcription Pipeline
- On session start, determine active profile:
  1) explicitly chosen by user, else
  2) last active, else
  3) default profile.
- Use `profile.transcriptionModel` when requesting model; if unavailable, prompt to install or offer fallback with confirmation.

### Post-Processing Pipeline
- If `postProcessingEnabled`, run post-processing after transcription completes:
  - Render template: compute `finalPrompt` by replacing all `{{TRANSCRIPTION}}` tokens in `profile.postProcessingPrompt` with the raw transcript text (no other placeholders supported).
  - Input to LLM: `{ prompt: finalPrompt, meta: { model, duration, language }, rawTranscript }` (raw transcript also provided for adapters that need separate fields).
  - Output: processed text; show alongside original with a toggle to view raw/processed.
  - Errors: display non-blocking toast; keep original transcript.
- Provide a pluggable adapter interface so different LLMs/services can be wired without changing profile schema.

### Keyboard Handling
- Register profile shortcuts at app start and whenever profiles change.
- On shortcut activation: switch active profile (and optionally start recording, if configured later).
- De-register removed/changed shortcuts to avoid leaks.

### Active App Detection
- Observe `NSWorkspace.didActivateApplicationNotification` to detect the focused app.
- If the focused app has a mapped profile and there is no per-session manual override, automatically switch to that profile.
- Provide a small debounce (100–200ms) to avoid thrashing on rapid app changes.

---

## Behavior Rules
- Exactly one default profile at all times; if deleting the default and others exist, force user to pick a new default; if it’s the only profile, prevent deletion.
- Prevent saving duplicate titles or shortcuts.
- Prompt can be empty only if post-processing is disabled; if enabled and empty, allow save with warning; prompt user when first used.
- Model selection must validate against supported models; show inline error if unavailable.
- When models list changes (install/uninstall), mark affected profiles; show warning badge.
- An app cannot be assigned to more than one profile; enforce via unique index and service validation.
- Automatic app-based switching is disabled for the current session once the user switches profiles manually while recording.
- Overlay always reflects the actual active profile, including icon/color.

---

## API/Services

ProfilesService:
```
getAll(): Profile[]
getDefault(): Profile
getActive(): Profile
setActive(id: String): void
create(data): Profile
update(id, patch): Profile
remove(id): void
setDefault(id): void
validate(profile): ValidationResult
onChange(cb): Unsubscribe
```

ShortcutService (augment existing):
```
registerProfileShortcut(profileId, chord)
unregisterProfileShortcut(profileId)
normalizeChord(rawEvent) -> string
isReserved(chord) -> boolean
```

TranscriptionService (augment existing):
```
start({ model: profile.transcriptionModel, ... })
```

PostProcessingService (pluggable):
```
process({ transcript, prompt, meta }) -> Promise<string>
```

DatabaseService (shared):
```
open(databasePath: string) -> Connection
getCurrentVersion() -> Int32
setVersion(version: Int32)
runMigrations() -> void  // Automatically applies pending migrations based on user_version
transaction<T>(fn: (db) => T) -> T
onClose(cb): Unsubscribe
```

ProfilesRepository (SQLite-backed):
```
list(): Profile[]
get(id): Profile | null
create(data): Profile
update(id, patch): Profile
remove(id): void
getDefault(): Profile | null
setDefault(id): void  // enforces single default (index or tx)
appsForProfile(id): AppAssignment[]
assignApp(profileId, bundleId, appName): void  // throws on conflict
unassignApp(bundleId): void
getProfileForApp(bundleId): Profile | null
```

RunningAppsService:
```
listOpenApps(): { name: string; bundleId: string; icon?: NSImage }[]
observeActiveApp(cb): Unsubscribe
```

OverlayService:
```
showActiveProfile(profile: Profile)
updateOnProfileChange()
```

---

## Implementation Plan (Step-by-Step)
1) Types & Schema
- **DONE** Add `Profile` and `AppAssignment` Swift structs that map to SQLite schema.
- **DONE** Add constants for reserved shortcuts and supported models.
- **DONE** Add validators for icon/color and all profile fields.

2) Database Service (Shared)
- **DONE** Introduce `DatabaseService` as a generic app-wide SQLite manager targeting `echo.sqlite`.
- **DONE** On startup, rename/migrate `echo_history.sqlite` -> `echo.sqlite` when applicable.
- **DONE** Implement `PRAGMA user_version` based migration system with automatic execution on startup.

3) Persistence Layer (SQLite)
- **DONE** Create `profiles` table and indices via a migration.
- **DONE** Implement `ProfilesRepository` for CRUD, default enforcement, and queries.
- **DONE** Create `profile_apps` table + indices; add repository methods for assign/unassign/list and conflict enforcement.

4) Profiles Service
- **DONE** Wrap repository with validation, events, and active/default semantics.
- **DONE** Remove any JSON/config persistence for profiles.
- **PENDING** Add `getProfileForApp`, `assignApp`, `unassignApp` and in-memory cache.

5) Shortcut Integration
- **DONE** Normalization util, conflict detection, reserved map.
- **PENDING** Register/unregister lifecycle tied to ProfilesService changes.
- **PENDING** Add shortcuts for switching while recording; set per-session manual override flag.

6) UI: Settings > Profiles
- **DONE** Create Profiles page with list + editor.
- **DONE** Implement list with actions (edit, duplicate, delete, set default).
- **DONE** Implement editor form with validation and inline errors.
- **PENDING** Add shortcut recorder component with conflict messaging.
- **PENDING** Add icon/color pickers with preview.
- **PENDING** Add App Assignments panel listing currently open apps and allowing add/remove; surface conflicts.

7) UI: Global Selector
- **PENDING** Add current profile indicator and dropdown to main UI.
- **PENDING** Wire selection to ProfilesService.setActive.
- **PENDING** Overlay: display active profile icon/color; live update on change.

- **DONE** Use active profile’s model in transcription flow.
- **DONE** After transcription, if enabled, send to PostProcessingService with profile prompt; display results.
- **PENDING** Hook Active App Detection to auto-switch profiles, gated by per-session override when recording.

9) Safeguards & Edge Cases
- **DONE** Prevent deletion of sole profile; handle default reassignment.
- **PENDING** Handle unavailable models with fallback/warnings.
- **PENDING** Warn on empty prompt when post-processing enabled.
- **PENDING** Debounce active app changes; last-change-wins policy.
- **DONE** Unassign apps when deleting a profile.

10) Release Plan
- **DONE** Migration is non-destructive; automatic rename + profile seeding on first run.

---

## Acceptance Criteria
- **DONE** Profiles section appears in Settings with list and editor.
- **DONE** User can create, edit, duplicate, delete profiles.
- **DONE** User can set exactly one default profile; app prevents multiple defaults.
- **DONE** User can assign unique shortcut chords; conflicts and reserved chords blocked with clear messages.
- **DONE** Profile includes: title, transcription model, enable post-processing, post-processing prompt, shortcut.
- **DONE** Default profile exists after migration on first run.
- **PENDING** Active profile selector available outside Settings; selecting affects next transcription.
- **DONE** Transcription uses profile’s selected model.
- **DONE** If post-processing enabled, processed text appears; errors don’t block core flow.
- **DONE** All changes persist across restarts.
- **DONE** Profiles persist in SQLite within `echo.sqlite` (not JSON).
- **DONE** History and profiles share the same DB file.
- **DONE** If `echo_history.sqlite` exists, it is migrated/renamed to `echo.sqlite` automatically.
- **PENDING** Users can choose an icon and color for profiles; visible in lists and overlay.
- **PENDING** Users can assign currently open apps to a profile; assignments persist and are unique per app.
- **PENDING** Active profile changes automatically based on focused app, unless a manual override occurred during the current recording.
- **PENDING** While recording, profile-switch shortcuts work and disable auto app-based switching for that session.
- **DONE** Prompt field supports `{{TRANSCRIPTION}}` placeholder; unknown placeholders are rejected.
- **PENDING** Existing user post-processing settings migrate into the Default profile; if the legacy prompt lacks `{{TRANSCRIPTION}}`, the migration auto-appends it to preserve behavior.

---


## Rough Timeline (estimate)
- Day 1: Schema, persistence, migration, ProfilesService.
- Day 2: Settings UI (list + editor), validation.
- Day 3: Shortcut integration, global selector.
- Day 4: Pipeline wiring (transcription + post-processing), edge cases.
- Day 5: Tests, docs, polish.
