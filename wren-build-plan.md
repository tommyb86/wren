# Wren — Build Plan

A personal life-admin app for iOS. Single user, single device, no backend, no App Store, no paid Apple account.

**Constraint that shapes everything:** no Mac. All Swift is written by Claude Code, compiled by GitHub Actions on macOS runners, and installed to the phone via SideStore.

---

## 1. Stack

| Concern | Choice | Notes |
|---|---|---|
| Language / UI | Swift + SwiftUI | |
| Persistence | SwiftData | iOS 17+ |
| Deployment target | iOS 17.0 | iPhone 14 runs current iOS |
| Project generation | **XcodeGen** | `project.yml` → `.xcodeproj` in CI. This is what makes a Mac-less repo possible |
| Core logic | **SPM package, pure Foundation** | Compiles and tests locally on Windows via `swift test` |
| CI | GitHub Actions, `macos-15` runners | Public repo → unlimited free macOS minutes |
| Install | Unsigned IPA → GitHub Release → SideStore | SideStore re-signs on device |
| Notifications | `UNUserNotificationCenter`, local only | Remote push unavailable on free tier |
| Sync | None | CloudKit requires a paid account |
| Widgets | None | App Groups entitlement requires a paid account |

### The whole repo is text

No binary project files. `project.yml`, `.swift` files, `Info.plist`, and asset catalogues (which are just directories of `Contents.json`) are all hand-writable. The only binary is the app icon PNG.

### Free-tier limits inherited from Apple

- Signing certificate expires every **7 days** — SideStore refreshes in the background
- **3 sideloaded apps** at once; SideStore occupies one, leaving two
- ~10 new App IDs per rolling week (refreshes don't consume these)
- No push entitlement, no App Groups, no CloudKit
- Expect breakage after major iOS releases

---

## 2. Phase 0 — walking skeleton (do this first, in full)

**The point of Phase 0 is not to build features. It's to prove the pipeline works end to end before any real code exists.**

Deliverable: an app on the phone with one button that schedules a local notification 60 seconds out, plus a diagnostics screen.

### What it proves

1. XcodeGen produces a valid project from `project.yml`
2. `xcodebuild` compiles it unsigned on a GitHub runner
3. The unsigned IPA packages correctly
4. SideStore signs and installs it
5. The app launches on the device
6. Notification permission can be requested and granted
7. **A local notification actually fires on a free-tier signed app**

Item 7 is the real risk. Local notifications need no entitlement so this should work, but it is unverified on this exact setup and the entire app depends on it. If it fails, stop and reconsider the stack before writing anything else.

### Phase 0 scope

- `project.yml`, `Info.plist`, `.gitignore`
- `WrenApp.swift` — app entry, SwiftData container with one throwaway model
- One screen: app name, a "Test notification (60s)" button, a "Diagnostics" link
- `Logger` — in-memory ring buffer, 500 entries, persisted to `UserDefaults` on background
- Diagnostics screen — log list, pending notification requests, permission status, build number, share-sheet export
- Both CI workflows
- Tag `v0.0.1`, install, tap button, lock phone, wait

Do not add a second screen until this whole loop is green.

---

## 3. Repo layout

```
wren/
├── project.yml                      # XcodeGen spec
├── .github/workflows/
│   ├── check.yml                    # fast build + tests, every push
│   └── release.yml                  # unsigned IPA, on tags only
├── Packages/
│   └── WrenCore/                    # pure Foundation — builds on Windows
│       ├── Package.swift
│       ├── Sources/WrenCore/
│       │   ├── Schedule.swift
│       │   ├── ScheduleEngine.swift
│       │   ├── Money.swift
│       │   └── BillingPeriod.swift
│       └── Tests/WrenCoreTests/
├── Wren/
│   ├── WrenApp.swift
│   ├── Info.plist
│   ├── Assets.xcassets/             # hand-written Contents.json colour sets
│   ├── Core/
│   │   ├── Diagnostics/             # Logger, DiagnosticsView
│   │   ├── Notifications/           # NotificationScheduler
│   │   └── Storage/                 # ModelContainer, FileStore
│   ├── DesignSystem/
│   └── Features/
│       ├── Today/  Bins/  Tasks/  Bills/  Receipts/
└── Models/                          # SwiftData @Model types
```

**`WrenCore` is the important bit.** It has zero UIKit or SwiftUI imports — only Foundation. The Swift toolchain runs natively on Windows, so `swift test` gives you a real compiler and a real test run in seconds on your laptop, with no CI round trip. All date maths, recurrence logic, and money normalisation lives here.

Small caveat: swift-corelibs-Foundation has minor behavioural differences from Darwin Foundation on calendar edge cases. Date arithmetic is well covered, but sanity-check DST boundaries on device.

---

## 4. CI

### `project.yml` (sketch)

```yaml
name: Wren
options:
  bundleIdPrefix: au.wren
  deploymentTarget:
    iOS: "17.0"
packages:
  WrenCore:
    path: Packages/WrenCore
targets:
  Wren:
    type: application
    platform: iOS
    sources: [Wren, Models]
    dependencies:
      - package: WrenCore
    info:
      path: Wren/Info.plist
      properties:
        CFBundleDisplayName: Wren
        UILaunchScreen: {}
    settings:
      base:
        MARKETING_VERSION: "0.1.0"
        PRODUCT_BUNDLE_IDENTIFIER: au.wren.app
```

### `check.yml` — every push, ~2–3 min

```yaml
name: check
on: [push, pull_request, workflow_dispatch]
jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen xcbeautify
      - run: swift test --package-path Packages/WrenCore
      - run: xcodegen generate
      - name: Build unsigned
        run: |
          set -o pipefail
          xcodebuild build \
            -project Wren.xcodeproj \
            -scheme Wren \
            -destination 'generic/platform=iOS' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY="" \
            | xcbeautify
```

Run the `WrenCore` tests first — they're fast and catch the majority of logic errors before the slow Xcode build starts.

### `release.yml` — on tags only

```yaml
name: release
on:
  push:
    tags: ['v*']
jobs:
  ipa:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - name: Archive unsigned
        run: |
          xcodebuild archive \
            -project Wren.xcodeproj \
            -scheme Wren \
            -configuration Release \
            -archivePath "$RUNNER_TEMP/Wren.xcarchive" \
            -destination 'generic/platform=iOS' \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY=""
      - name: Package IPA
        run: |
          mkdir -p Payload
          cp -R "$RUNNER_TEMP/Wren.xcarchive/Products/Applications/Wren.app" Payload/
          zip -qr Wren.ipa Payload
      - uses: softprops/action-gh-release@v2
        with:
          files: Wren.ipa
```

`CODE_SIGNING_ALLOWED=NO` is the key flag. SideStore signs the payload on device with your Apple ID.

### The Claude Code loop

Claude drives this with the `gh` CLI rather than waiting on you:

```
git push
gh run watch --exit-status
gh run view --log-failed      # on failure, read, fix, push again
```

Cache SPM and DerivedData between runs to keep the check job short.

### Installing

1. Tag and push: `git tag v0.0.1 && git push --tags`
2. Download the IPA from the GitHub Release, on the phone
3. SideStore → `+` → select the IPA
4. Subsequent builds: same flow, overwrites in place, data preserved

---

## 5. Diagnostics — build it in Phase 0, not later

There is no debugger, no console, no simulator. Every runtime bug surfaces only as "it didn't work." You must ship your own observability from day one.

`Logger` writes to a bounded in-memory buffer and flushes to `UserDefaults` on backgrounding. Every notification scheduled, every SwiftData save, every OCR attempt gets a line.

The Diagnostics screen shows:
- Recent log entries, newest first, filterable by level
- All pending `UNNotificationRequest`s with their fire dates — this alone will save hours
- Notification authorisation status
- SwiftData row counts per model
- Build version and commit SHA
- Export button → share sheet → send yourself the log

When something misbehaves on the phone, this screen is your only window in. Treat it as a first-class feature.

---

## 6. The scheduling core

Bins, tasks, and bills are one problem: *a thing that recurs*. Reminders are only one consumer of that. The dashboard and expense forecasting are others — which is why this is an **occurrence engine**, not a reminder engine.

```swift
public struct Schedule: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, Sendable {
        case daily, weekly, monthly, yearly
    }
    public var frequency: Frequency
    public var interval: Int              // every N — fortnightly = weekly, interval 2
    public var anchorDate: Date           // the occurrence everything counts from
    public var weekdays: Set<Int>         // weekly only; empty = use anchor's weekday
    public var endDate: Date?
}

public struct ScheduleEngine {
    public static func next(_ s: Schedule, after: Date, calendar: Calendar) -> Date?
    public static func occurrences(_ s: Schedule, from: Date, to: Date, calendar: Calendar) -> [Date]
    public static func occurrences(_ s: Schedule, from: Date, limit: Int, calendar: Calendar) -> [Date]
}
```

Alternating fortnightly bins fall out naturally: two schedules, both fortnightly, anchored one week apart.

Use `Calendar` and `DateComponents` throughout — never manual arithmetic. Tests must cover: weekly, fortnightly alternating, monthly on the 31st (short months), yearly, DST transitions, and an `endDate` cutoff. These run locally on Windows in seconds.

---

## 7. Feature specs

### 7.1 Today

The screen that makes the app worth opening. Bins due tonight, tasks due, bills due, all actionable inline. Build it in Phase 4 once there's real data from three sources to unify.

### 7.2 Bins — dashboard state, not just reminders

The dashboard needs to answer **"what bin week is it?"** at a glance, so this is a read model, not just a notification trigger.

```swift
struct BinWeekState {
    let cycleStart: Date
    let cycleEnd: Date
    let due: [(bin: BinCollection, date: Date)]
}
```

Derived by asking the engine for occurrences inside the current collection cycle. On the dashboard:

- The Bins tile on Today: "Recycling week" with the distinctive bin's lid swatch, and when the next night is
- Bin rows in the agenda name the *night to put it out* ("Out tonight, collected 6:00 am"), since the collection date alone was the confusing part
- Multiple bins on one night appear as separate rows, each with its lid swatch
- Reminder the evening before

Model:

```swift
@Model final class BinCollection {
    var name: String = ""
    var colorHex: String = "#4A7C6F"     // actual lid colour
    var scheduleData: Data = Data()
    var reminderHoursBefore: Int = 14
    var isActive: Bool = true
}
```

Most QLD councils run general waste weekly and recycling fortnightly — two schedules, anchored appropriately.

### 7.3 Recurring tasks

Title, notes, schedule, reminder time. Completions record against the **due date**, not just "now", so history and overdue detection both work.

### 7.4 Bills — a reporting system

The point is knowing what your household spends, so the data model is built for reporting, not just reminding.

**The key concept is normalisation.** Bills arrive at different frequencies, so nothing is comparable until everything is converted to a common period. A $120 quarterly bill is $40/month equivalent. Every report depends on this.

Put it in `WrenCore` so it's locally testable:

```swift
public enum BillingPeriod {
    public static func monthlyEquivalentCents(amountCents: Int, schedule: Schedule) -> Int
    public static func annualCents(amountCents: Int, schedule: Schedule) -> Int
}
```

Models:

```swift
@Model final class Bill {
    var name: String = ""
    var amountCents: Int = 0
    var isVariableAmount: Bool = false      // electricity, water
    var scheduleData: Data = Data()
    var category: String = ""               // utilities, insurance, subscriptions...
    var paidBy: String = ""                 // optional, for a shared household
    var reminderDaysBefore: Int = 3
    var payments: [BillPayment]? = []
    var isActive: Bool = true
}

@Model final class BillPayment {
    var paidAt: Date = Date()
    var amountCents: Int = 0                // what was ACTUALLY paid
    var dueDate: Date = Date()              // which occurrence this settles
    var bill: Bill?
}
```

Recording both the expected amount and the actual payment is what makes the reports honest — variance is the interesting signal.

**Reports to build:**

- **Monthly commitment** — sum of monthly-equivalents across all active bills. The "what do we spend" number
- **By category** — same, grouped, as a breakdown
- **Annual total** — the yearly figure
- **This month** — what's due, what's paid, what's outstanding
- **12-month forecast** — engine-generated occurrences with amounts, showing lumpy months (rego, insurance) before they arrive
- **Per-bill history** — payment amounts over time, so "has the power bill gone up?" is answerable
- **Expected vs actual** — variance per bill, per month

Export to CSV via share sheet.

Money is `Int` cents everywhere. Format only at the display edge.

### 7.5 Tax receipts

Heaviest feature, build last.

- Capture via `VNDocumentCameraViewController` (VisionKit) — edge detection, perspective correction, multi-page
- OCR via Vision `VNRecognizeTextRequest`, `.accurate`, on-device
- Parse amount, date, vendor as **suggestions the user confirms**, never silent auto-fill
- Images as JPEG ~0.8 quality in `Documents/receipts/`, filename = UUID; never blobs in SwiftData
- Keep `rawOCRText` for full-text search later
- **Australian FY: 1 July – 30 June.** Group and filter by FY, not calendar year
- Export CSV + image zip per FY via share sheet — this is the actual payoff at tax time

---

## 8. Notifications

**The cap:** iOS allows **64 pending local notifications per app**. Schedule a year of bin days and iOS silently drops the excess.

Strategy:
1. Schedule only the next ~30 days of occurrences
2. Rebuild the entire set on every app foreground — cancel all, re-add. The set is small; diffing isn't worth it
3. Stable identifiers: `bin-<uuid>-<ISO8601>`, so rebuilds are idempotent
4. Log every scheduled request; surface the pending list in Diagnostics
5. Request permission on first meaningful use (adding the first bin), not at launch

Background top-up via `BGAppRefreshTask` is a nice-to-have. Verify the entitlement works on free-tier signing before relying on it; foreground rebuilds are sufficient for an app opened most days.

---

## 9. Design system

Calm neo-brutalism: paper and ink, one lime highlight, borders instead of shadows. Minimal in element count, confident in line. Chosen September 2026 from the explorations in `design/today/` (the canvas at `wren-today-redesign.html`); the earlier sage-and-serif notebook look is superseded.

**Light**

| Token | Hex | Use |
|---|---|---|
| `bg` | `#F3F0E8` | paper |
| `surface` | `#FFFFFF` | boxes |
| `textPrimary` | `#1C1A17` | ink — text *and* every border |
| `textSecondary` | `#5E5A52` | metadata |
| `accent` | `#1C1A17` | same as ink; links and ticks stay monochrome |
| `accentSoft` | `#E4F5A6` | pale lime — selected chips, suggestion pills |
| `highlight` | `#C6F135` | lime — the Today tag, Paid buttons, the one number that matters |
| `onHighlight` | `#111111` | text on lime, both appearances |
| `alert` | `#D93A2B` | overdue only |
| `divider` | `#DED9CE` | hairline row rules |
| `shadow` | `#1C1A17` | the offset block behind anything pressable |

**Dark**

| Token | Hex |
|---|---|
| `bg` | `#111111` |
| `surface` | `#111111` (borders do the work; no lifted panels) |
| `textPrimary` | `#F4EFE3` |
| `textSecondary` | `#B8B3A8` |
| `accent` | `#F4EFE3` |
| `accentSoft` | `#3A4410` |
| `highlight` | `#C6F135` |
| `onHighlight` | `#111111` |
| `alert` | `#FF6B5B` |
| `divider` | `#2A2823` |
| `shadow` | `#4A453C` |

Define as colour sets in `Assets.xcassets` (hand-written `Contents.json`), expose as `Color.wren.accent`. Never a raw hex in a view.

**Colour discipline:** ink and paper, lime only on things you can press or the one figure the sentence is about. Red appears *only* for overdue, so it means something when it shows up. Bin lid colours are the deliberate exception — they map to physical objects, and are drawn as bordered squares so they read as objects rather than status dots.

**Line:** every box, chip and swatch has a 1.5pt ink border (`Stroke.border`), corner radius 6 on cards and 3 on chips. No drop shadows. Anything pressable gets a hard 2pt offset block behind it (`.wrenHardShadow`), and pressing pushes it into that shadow. Rows separate with a 1pt `divider` rule.

**Shadows are their own token, not ink.** In dark mode `surface` and `background` are both `#111111`, so a box is nothing but its border, and inverting the ink would make every shadow a bright block — a glow, not a shadow. `shadow` is therefore ink on paper and a warm grey on dark. One shadow colour everywhere, including the destructive button.

**Day headers on Today are a label and a rule**, not a filled band. The band read well on paper but became the only filled shape on a dark screen.

**Typography:** Space Grotesk (SIL OFL, one variable TTF in `Wren/Fonts`, registered via `UIAppFonts`) for anything that carries the look — titles, section labels, chips, row titles, tile values, the summary sentence, money headlines — always through `WrenFont` so size and Dynamic Type anchor are decided once. SF Pro for reading: body copy, editors, list subtitles. No serif anywhere. Monospaced digits on all amounts. Diagnostics reports whether the family registered, because `Font.custom` falls back silently.

**Spacing:** 4pt scale (4, 8, 12, 16, 24, 32). Generous vertical rhythm.

**Interaction:** light haptic on completion. `.snappy` springs. Every list gets a designed empty state.

**Working without previews:** settle the visual design in HTML on your laptop with hot reload, then have Claude port the finished layout to SwiftUI. Converge on the look first, port once — don't iterate spacing through CI.

---

## 10. Phases

**Phase 0 — Walking skeleton.** Section 2. Nothing else until the notification fires on the device.

**Phase 1 — Schedule engine + Bins.** `WrenCore` engine with full local tests. Then bins, the bin-week dashboard card, and real notification scheduling. First actually useful build.

**Phase 2 — Recurring tasks.** Second engine consumer. Adds completion tracking.

**Phase 3 — Bills + reporting.** Third consumer. Money handling, payment history, normalisation, the report set in 7.4.

**Phase 4 — Today screen.** Unify the three sources now that real data exists.

**Phase 5 — Receipts.** Camera, OCR, file storage, FY grouping, export.

**Phase 6 — Polish.** JSON backup/restore, App Intents if they work on free signing, refinement.

---

## 11. Kickoff prompt for Claude Code

> I'm building **Wren**, a personal iOS life-admin app. Read `wren-build-plan.md` in the repo root — full architecture, constraints, data model, design tokens, and phases.
>
> Critical constraint: **I have no Mac.** You write the Swift, GitHub Actions compiles it, SideStore installs it. There is no local Xcode, no simulator, no previews, no debugger. The project is generated by XcodeGen from `project.yml` — never assume an `.xcodeproj` exists in the repo.
>
> Build **Phase 0 only** (section 2): `project.yml`, `Info.plist`, `.gitignore`, the app entry with a SwiftData container, a single screen with a "Test notification (60s)" button, the Logger and Diagnostics screen from section 5, and both CI workflows from section 4.
>
> Then push, watch the run with `gh run watch --exit-status`, and fix any failures by reading `gh run view --log-failed`. Iterate until the check job is green, then tag `v0.0.1` so the release workflow produces an IPA.
>
> Don't start Phase 1 until I confirm the notification actually fired on the device.

### Repo setup

```bash
mkdir wren && cd wren
git init
gh repo create wren --public --source=. --remote=origin
# add wren-build-plan.md to the root
```

Public repo — unlimited free macOS runner minutes, and nothing sensitive lives in it.

Keep this file in the repo and update it as decisions change. It's the shared context between sessions.

---

## 12. Non-goals

- No multi-user, accounts, or auth
- No bank feeds or transaction imports
- No App Store release
- No widgets or CloudKit (both need a paid account)
- No Android, no web version
