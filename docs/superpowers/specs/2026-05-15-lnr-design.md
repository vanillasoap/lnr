# lnr — Design Spec

A macOS menubar app that surfaces your Linear issues at a glance.

## Tech Stack

- Swift, macOS 14+ (Sonoma)
- AppKit shell (NSStatusItem + NSPopover) hosting SwiftUI views
- Linear GraphQL API, personal API key auth
- No third-party dependencies (URLSession, Security framework, SMAppService)
- Xcode project with SPM if needed

## Architecture

### Approach

AppKit owns the menubar integration (NSStatusItem, NSPopover, NSWindow for settings). All view content is SwiftUI hosted via NSHostingView. This matches how Apple's Weather widget works — full control over the status item and popover chrome, declarative UI inside.

### Key Objects

- **`AppDelegate`** — Creates NSStatusItem, owns NSPopover, updates icon/badge state. Observes `AppState` via Combine.
- **`AppState`** (ObservableObject, @MainActor) — Single source of truth. Holds issues, connection status, sync status, selected teams, view mode, sort/filter preferences.
- **`LinearService`** (actor) — All API communication. Owns the polling loop (structured concurrency `Task.sleep`). Publishes results to `AppState`.
- **`KeychainService`** — Thin wrapper around Security framework for API key storage.

### App Lifecycle

1. App launches, `AppDelegate` creates status item with ring+dot icon.
2. Checks Keychain for API key.
3. If no key: `connectionStatus = .notConfigured`, popover shows onboarding.
4. If key exists: validates with `viewer` query, sets `.connected` or `.error`.
5. On connected: fetches teams, then issues. Starts polling loop.
6. Click status item: shows popover (onboarding or issue list depending on state).

### File Structure

```
lnr/
├── lnrApp.swift                  # @main App, NSApplicationDelegateAdaptor
├── AppDelegate.swift             # NSStatusItem, NSPopover, icon state
├── AppState.swift                # ObservableObject, shared state
├── Models/
│   ├── Issue.swift               # Issue model (Codable, Identifiable)
│   ├── WorkflowState.swift       # Workflow state model
│   └── Team.swift                # Team model
├── Services/
│   ├── LinearService.swift       # GraphQL client, polling, mutations
│   └── KeychainService.swift     # Secure API key storage
├── Views/
│   ├── PopoverContentView.swift  # Root view (switches onboarding vs issue list)
│   ├── Onboarding/
│   │   ├── WelcomeView.swift
│   │   ├── APIKeyView.swift
│   │   └── TeamPickerView.swift
│   ├── IssueList/
│   │   ├── IssueListView.swift   # Header, search, footer, hosts flat/grouped
│   │   ├── FlatListView.swift    # View A — sorted flat list
│   │   ├── GroupedListView.swift # View B — grouped by state with tabs
│   │   ├── IssueRowView.swift    # Compact + expanded states
│   │   └── EmptyStateView.swift  # Inbox zero, loading, error states
│   └── Settings/
│       ├── SettingsWindowController.swift  # NSWindow hosting SwiftUI
│       ├── GeneralSettingsView.swift
│       ├── AccountSettingsView.swift
│       ├── ShortcutsSettingsView.swift
│       └── AdvancedSettingsView.swift
└── Utilities/
    └── Constants.swift           # Popover dimensions, API URL, defaults keys
```

## Data Layer

### Models

**Issue** — `id: String`, `identifier: String` (e.g. "ENG-1247"), `title: String`, `description: String?`, `priority: Int` (0=none, 1=urgent, 2=high, 3=medium, 4=low), `state: WorkflowState`, `team: Team`, `url: String`, `updatedAt: Date`, `createdAt: Date`

**WorkflowState** — `id: String`, `name: String`, `type: StateType` (enum: backlog/unstarted/started/completed/cancelled), `color: String`, `position: Double`

**Team** — `id: String`, `key: String`, `name: String`, `color: String`

### State Enums

```swift
enum ConnectionStatus {
    case notConfigured
    case connecting
    case connected(userName: String, orgName: String)
    case error(message: String)
}

enum SyncStatus {
    case idle
    case syncing
    case failed(lastAttempt: Date)
}

enum ViewMode: String {
    case flat
    case groupedByState
}
```

### GraphQL Client

Lightweight struct around URLSession. Single endpoint: `https://api.linear.app/graphql`. Auth via `Authorization` header with the API key. Request building with `JSONSerialization`, response parsing with `JSONDecoder`.

### Queries

1. **Viewer** (validation + user info): `viewer { id name organization { name } }`
2. **Assigned issues**: `viewer { assignedIssues(filter: { snoozedBy: { null: true } }) { nodes { id identifier title description priority state { id name type color position } team { id key name color } url updatedAt createdAt } } }`
3. **Team list** (with issue counts): `teams { nodes { id key name color issues(filter: { assignee: { isMe: { eq: true } } }) { nodes { id } } } }`
4. **Workflow states** (per team): `team(id: $teamId) { states { nodes { id name type color position } } }`
5. **Update issue status**: `mutation { issueUpdate(id: $id, input: { stateId: $stateId }) { success } }`
6. **Update issue priority**: `mutation { issueUpdate(id: $id, input: { priority: $priority }) { success } }`
7. **Snooze issue**: `mutation { issueUpdate(id: $id, input: { snoozedUntilAt: $date }) { success } }`
8. **Delete issue**: `mutation { issueDelete(id: $id) { success } }`

### Polling

`LinearService` runs a `Task.sleep`-based loop (structured concurrency). Default 60s, configurable via settings. Each tick fetches the full assigned issues set and replaces the array on `AppState`. No pagination needed — personal assigned issues are typically <100.

### Caching

In-memory only for v1. No disk persistence. List is empty until first fetch completes.

### Error Handling

GraphQL errors and HTTP failures are caught in `LinearService`, which sets `AppState.syncStatus = .failed(...)`. Retries happen automatically on the next poll tick.

Optimistic updates: for status, priority, and snooze mutations, the local `AppState` is updated immediately. If the API call fails, the change is reverted and a brief error appears in the sync status.

## Menubar Icon

### Design

SF Symbol `circle.circle` (ring + dot), rendered as an NSImage template image on the NSStatusItem button.

### Five States

| State | Icon | Badge | Tooltip |
|---|---|---|---|
| Idle (connected, 0 issues) | `circle.circle` | none | "lnr — Connected" |
| With badge (N issues) | `circle.circle` | N as text next to icon | "lnr — 22 issues" |
| Syncing | `arrow.triangle.2.circlepath` or rotation animation | unchanged | "lnr — Syncing..." |
| API error | `circle.circle` + small red `exclamationmark.circle.fill` overlay | unchanged | "lnr — Last sync failed" |
| No key | `circle.circle` (dimmed, no badge) | none | "lnr — Not configured" |

Badge count is rendered as a string alongside the icon using `NSStatusItem.button.title`, similar to how Weather shows the temperature.

`AppDelegate` observes `AppState` via Combine (`$connectionStatus`, `$syncStatus`, `$issues`) and updates the status item accordingly. All updates on `@MainActor`.

## Onboarding Flow

Shown inside the popover when `connectionStatus == .notConfigured`. Replaces the issue list — not a separate window.

### Step 1 — Welcome

- App icon (ring+dot), "Welcome to lnr" heading
- Subtitle: "Your Linear issues in the menubar. Lightweight, native, and stays out of your way."
- "Get Started" button
- Page dots (3 steps)

### Step 2 — Connect to Linear

- "Connect to Linear" heading
- Instructional text: "Paste a personal API key from linear.app/settings/api. It's stored securely in your macOS Keychain."
- SecureField for key input, checkmark on validation success
- On entry: validates against Linear's `viewer` query
- Success: "Connected as [Name] · [Org]" in green
- Failure: error message in red
- Security note: "Key never leaves your machine. lnr talks to Linear directly via HTTPS."
- Skip / Continue buttons. Skip goes to the empty "not configured" state. Continue enabled only after validation succeeds.

### Step 3 — Pick Teams

- "Pick teams" heading, subtitle: "Show issues from these teams in your menubar."
- Team list: color dot, team key badge, team name, issue count (trailing)
- Checkboxes per team, all checked by default for teams with >0 issues
- Back / Finish buttons. Finish saves team selection to UserDefaults, transitions to issue list, triggers first fetch.

### Re-entry

If the API key is deleted from Settings, the app shows a simplified "Connect to Linear" empty state with "Open Settings..." button — not the full onboarding wizard.

## Main Popover — Issue List

### Dimensions

~360pt wide, dynamic height up to ~500pt with scroll. Managed by NSPopover contentSize.

### Header Bar

- Leading: app icon (ring+dot) + "Inbox" label + issue count
- Trailing: refresh button (`arrow.clockwise`), sort button (`line.3.horizontal.decrease`), view toggle (`line.3.horizontal.decrease.circle`), settings gear (`gearshape`)

### Search Bar

Below header. Placeholder: "Search 22 issues..." with Cmd+K hint. Filters issues client-side by identifier and title.

### Footer Bar

- Leading: keyboard hints (arrow up/down to navigate, return to open)
- Trailing: sync status ("Synced just now", "12s ago")

### View A — Flat List (Default)

Single scrollable list. Default sort: updated date descending.

Each row: `[priority icon] [status dot] [identifier] [title...] [timestamp]`

Selected row gets accent color tint highlight. Keyboard navigable: arrow keys move selection, Return opens in Linear, Space expands/collapses.

### View B — Grouped by State

Three tab pills at top: Active / Backlog / Done.
- Active = started + unstarted state types
- Backlog = backlog state type
- Done = completed + cancelled state types

"All teams" dropdown trailing the tabs.

Within each tab, issues grouped by specific state name with collapsible section headers (e.g. "IN PROGRESS 3", "TODO 4"). Same `IssueRowView` per row.

Footer summary: "3 active · 5 todo · 2 review" + sync time.

### Switching Views

The view toggle button in the header switches between A and B. Persisted to UserDefaults.

### Sort Options (Dropdown from Sort Button)

- Priority (urgent first)
- Status
- Updated (newest first) — default
- Created (newest first)

## Issue Row

### Compact (Default)

`[priority icon] [status dot] [identifier] [title — single line, truncated] [relative timestamp]`

Priority icons:
- Urgent (1): `exclamationmark.triangle.fill` in red
- High (2): bar chart 3 bars
- Medium (3): bar chart 2 bars
- Low (4): bar chart 1 bar
- None (0): `circle` outline

Status dot: small colored circle matching workflow state color from Linear.

Identifier: monospace, secondary color.

Timestamp: relative ("12m", "1h", "3d"), secondary color.

### Expanded (Space Key or Chevron Click)

- Top line: identifier + status pill (name + color, e.g. "In Progress" with orange tint)
- Full title (wrapping, up to 2 lines)
- Description preview: first ~4 lines of markdown-stripped plaintext, "..." truncation
- Bottom bar: team color dot + team key ("ENG"), "12m ago", open externally button, status dot (quick-change), overflow "..." menu, "Open in Linear" accent button
- Chevron/click collapses back

### Special States

**Empty (inbox zero):** Centered tray icon, "Inbox zero." heading, "No issues assigned to you. lnr will check again in 60s." subtitle (reflects actual polling interval).

**Loading:** Centered ProgressView spinner, "Loading issues..." text, footer shows "Connecting..."

**Error (sync failed, no cached data):** Centered exclamation icon, "Couldn't reach Linear", "Check your connection or API key." subtitle, "Retry" button.

## Actions & Context Menu

### Right-Click Context Menu

| Action | Shortcut | Behavior |
|---|---|---|
| Open in Linear | Cmd+O | Opens issue URL in browser or Linear app per settings |
| Copy link | Cmd+L | Copies issue URL to clipboard |
| Copy identifier | Cmd+. | Copies e.g. "ENG-1247" to clipboard |
| Change status... | → submenu | Team's workflow states, checkmark on current, colored dots |
| Set priority... | → submenu | Urgent/High/Medium/Low/None, checkmark on current |
| Snooze... | → submenu | 1 hour / 4 hours / Tomorrow / Next week |
| Delete | Cmd+Backspace | Confirmation dialog first |

### Status Submenu

Dynamically populated from the issue's team workflow states (cached when teams load). States ordered by position. Colored dots per state. Checkmark on current. Selecting fires `issueUpdate` mutation with optimistic local update.

### Priority Submenu

Static list: Urgent, High, Medium, Low, None. Checkmark on current. Immediate mutation + optimistic update.

### Snooze Submenu

Options: 1 hour, 4 hours, Tomorrow (9am), Next week (Monday 9am). Uses `snoozedUntilAt` field on the issue. Snoozed issues disappear from the list; next poll after snooze expires picks them back up.

### Delete Confirmation

Modal alert: "Delete ENG-1247? This will permanently delete the issue from Linear. This action cannot be undone." Cancel / Delete (red, destructive). Fires `issueDelete` mutation.

### Expanded Row Actions

Inline buttons in the expanded row trigger the same actions as the context menu — just a different entry point.

## Settings Window

Standalone NSWindow (~480pt wide, ~400pt tall), standard macOS preferences style with toolbar tab picker. Opened from gear icon in popover header. Does not dismiss the popover.

### General Tab

- **Refresh interval** — Dropdown: 30s, 60s (default), 2m, 5m, 10m
- **Launch at login** — Toggle, backed by SMAppService.mainApp
- **Show badge count on icon** — Toggle
- **Appearance** — Segmented: Light / Dark / System (default)
- **Open issues in** — Dropdown: "Default browser" / "Linear desktop app" (uses `linear://` scheme, falls back to browser)

### Account Tab

- **API Key** — Masked display ("lin_api_••••••••••"), "Replace..." button to swap key with inline validation
- **Connected as** — User name and org from viewer query
- **Teams** — Same team picker as onboarding (checkboxes, colors, issue counts). Changes take effect immediately.
- **Sign out** — Removes key from Keychain, clears cached data, returns to not-configured state

### Shortcuts Tab

Reference list of existing keyboard shortcuts (Cmd+O, Cmd+L, Cmd+., etc.). Non-editable for v1.

### Advanced Tab

- **Reset all data** — Clears Keychain, UserDefaults, returns to fresh state. Confirmation dialog.
- **Debug** — Last sync timestamp, API response time, issue count.

## Out of Scope (v1)

- OAuth flow (personal API key only)
- Creating new issues
- Notifications / webhooks
- Multiple workspace support
- Issue comments beyond description preview
- Disk caching / offline mode
- Editable keyboard shortcuts
- Homebrew cask / DMG distribution (build from source)
