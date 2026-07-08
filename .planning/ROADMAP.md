### Phase 6: remove the history feature

**Goal:** The per-tool history feature is gone from Flint — no history panel, no per-tool history capture, no history entries in global search, no history-limit preference. Global search still works (tools only). The app builds clean, the full test suite is green, and no dead history/GRDB code or unused dependency remains. Nothing a user could reach is broken by the removal.
**Requirements**: (removal — supersedes INFRA-13 history-limit pref, history portions of INFRA-09/10)
**Depends on:** Phase 5
**Rationale:** History is unused in practice; it adds surface area across every tool ViewModel (an `onSaveHistory:` closure), a GRDB-backed store, a dedicated panel, and half of the global-search path. Removing it shrinks the code, drops the GRDB dependency if nothing else needs it, and eliminates the INFRA-09 "don't leak secrets into history" hazard entirely.
**Plans:** 7/7 plans complete

Plans:

**Wave 1** *(strip per-tool history capture — parallel, disjoint tool dirs)*
- [x] 06-01-PLAN.md — Remove onSaveHistory/HistoryEntry from Hash, JWT, Base64, URL tools (VM + View + Definition); the INFRA-09 secret-exclusion group
- [x] 06-02-PLAN.md — Remove onSaveHistory/HistoryEntry from Color, NumberBase, Regex, JSON tools; delete stale GRDB comments in Color/NumberBase VMs
- [x] 06-03-PLAN.md — Remove onSaveHistory/HistoryEntry from UUID, Timestamp, TextDiff, Markdown, ImageCompress tools + clean ImageCompressViewModelTests (drop history-fires-once test)

**Wave 2** *(tools-only search + app/prefs unwiring — parallel, disjoint files; blocked on Wave 1)*
- [x] 06-04-PLAN.md — Make global search tools-only: reduce SearchResultsMerger + SearchView (drop .historyEntry, historyResults, onSelectHistoryEntry, onShowHistory; "No tools" copy)
- [x] 06-05-PLAN.md — Remove app-level history wiring (FlintApp, MainWindowView), popover history nav + ⌘H shortcut (MenuBarPopoverView), and the History preference (PreferencesStore.historyLimit + PreferencesView tab)

**Wave 3** *(delete files + pbxproj surgery + drop GRDB; blocked on Waves 1-2)*
- [x] 06-06-PLAN.md — Delete the 5 history files, remove their pbxproj refs (build-file/file-ref/group/sources), and drop the GRDB package entirely (no source consumer remains)

**Wave 4** *(phase goal gate; blocked on all)*
- [x] 06-07-PLAN.md — No-dead-symbols grep + clean build + full test suite + human re-verify search works and tools unbroken (checkpoint:human-verify)

Surface area (from code map):
- **Delete:** `Core/Services/HistoryStore.swift`, `Core/Models/HistoryEntry.swift`, `UI/HistoryPanelView.swift`, `UI/Components/HistoryRowView.swift`, `FlintTests/HistorySearchTests.swift`
- **Unwind per-tool capture:** remove `onSaveHistory:`/`HistoryEntry` from every tool ViewModel + its init call site (Hash, Color, Base64, URLEncoder, UUID, Regex, NumberBase, JWT, JSONFormatter, Timestamp, TextDiff, Markdown, ImageCompress) and Definition/View wiring
- **Search (keep, tools-only):** strip history from `UI/SearchView.swift` and `Core/Services/SearchResultsMerger.swift` (drop `.historyEntry` case, `historyResults`, `onSelectHistoryEntry`, `onShowHistory`)
- **App wiring:** `App/FlintApp.swift`, `UI/MenuBarPopoverView.swift`, `UI/MainWindowView.swift` — remove store injection + history navigation
- **Preferences:** remove `historyLimit` from `Core/Services/PreferencesStore.swift` (INFRA-13) and its UI in `UI/PreferencesView.swift`
- **Dependency:** GRDB confirmed used ONLY by the two deleted files (Color/NumberBase VM "imports" are comment-only, no real `import GRDB`) → drop the GRDB package from `Flint.xcodeproj`; also remove the deleted files from the pbxproj
- **Verify:** clean build + full `xcodebuild test` green; global search returns tools; no `History`/`GRDB` symbols remain outside `build/`

### Phase 7: Keep menubar popover open after color picker use

**Goal:** After choosing a color via the eyedropper (NSColorSampler) or the system ColorPicker (NSColorPanel), the popover currently loses key focus and dismisses. Keep it open — or re-present it — so the picked color lands in the Color tool and the user can copy any format and keep working.
**Requirements**: PHASE-07-GOAL (popover survives both color pickers), CLR-02
**Depends on:** Phase 6
**Plans:** 1 plan

Plans:
- [ ] 07-01-PLAN.md — Eyedropper re-present + NSColorPanel falling-edge watchdog (both pickers keep the popover usable, D-04) + manual UAT gate
