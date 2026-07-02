---
phase: 06-remove-the-history-feature
plan: 06
subsystem: infra
tags: [xcodeproj, grdb, dead-code-removal, swift-package-manager]

# Dependency graph
requires:
  - phase: 06-01
    provides: Removed HistoryStore/HistoryEntry references from Hash, JWT, Base64, URL tools
  - phase: 06-02
    provides: Removed HistoryStore/HistoryEntry references from NumberBase and other tools
  - phase: 06-03
    provides: Removed remaining HistoryStore/HistoryEntry consumer references
  - phase: 06-04
    provides: Removed HistoryPanelView/HistoryRowView wiring from navigation/search
  - phase: 06-05
    provides: Removed final history UI entry points and preferences wiring
provides:
  - Five orphaned history source files deleted from disk (HistoryStore.swift, HistoryEntry.swift, HistoryPanelView.swift, HistoryRowView.swift, HistorySearchTests.swift)
  - Flint.xcodeproj/project.pbxproj with zero references to deleted history files
  - GRDB Swift package dependency fully removed from both Flint and FlintTests targets
affects: [06-07, phase-06-wave-4-build-verification]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - Flint.xcodeproj/project.pbxproj

key-decisions:
  - "Left Package.resolved (swiftpm lockfile) with a stale GRDB pin — it is not in the plan's files_modified scope and Xcode's package resolver will prune it automatically when packages are next resolved; not a source of build failure since the package reference is already gone from pbxproj."

patterns-established: []

requirements-completed: [INFRA-08]

# Metrics
duration: 12min
completed: 2026-07-02
---

# Phase 06 Plan 06: Delete History Files and Drop GRDB Summary

**Deleted the five orphaned history source files (HistoryStore, HistoryEntry, HistoryPanelView, HistoryRowView, HistorySearchTests) and fully removed the GRDB Swift package dependency from the Xcode project, completing the history-feature removal.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-02T02:07:00Z
- **Completed:** 2026-07-02T02:19:45Z
- **Tasks:** 3
- **Files modified:** 6 (5 deleted, 1 pbxproj edited)

## Accomplishments
- Deleted Core/Services/HistoryStore.swift, Core/Models/HistoryEntry.swift, UI/HistoryPanelView.swift, UI/Components/HistoryRowView.swift, FlintTests/HistorySearchTests.swift
- Removed all PBXBuildFile, PBXFileReference, PBXGroup children, and Sources build-phase entries for those five files from project.pbxproj
- Removed the GRDB package entirely: both PBXBuildFile "GRDB in Frameworks" entries, both Frameworks build-phase references, both packageProductDependencies entries (Flint + FlintTests), the packageReferences entry, the XCRemoteSwiftPackageReference block, and both XCSwiftPackageProductDependency blocks
- Verified no `import GRDB` remains anywhere in source, and all seven other packages (KeyboardShortcuts, MenuBarExtraAccess, HighlightSwift, UUIDv7, ChromaKit, swift-markdown, Sparkle) remain intact
- Validated project.pbxproj with `plutil -lint` after each edit — always OK

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete the five history source files** - `0b1e8cd` (feat)
2. **Task 2: Remove the five files from the pbxproj** - `a7884d4` (chore)
3. **Task 3: Drop the GRDB package from the pbxproj** - `663ffdd` (chore)

**Plan metadata:** (final commit follows this SUMMARY)

## Files Created/Modified
- `Core/Services/HistoryStore.swift` - deleted (GRDB-backed history store)
- `Core/Models/HistoryEntry.swift` - deleted (GRDB record)
- `UI/HistoryPanelView.swift` - deleted (history panel UI)
- `UI/Components/HistoryRowView.swift` - deleted (history row UI)
- `FlintTests/HistorySearchTests.swift` - deleted (history search tests)
- `Flint.xcodeproj/project.pbxproj` - removed 20 lines referencing the five deleted files, then removed 25 lines of GRDB package configuration (PBXBuildFile, Frameworks phase, packageProductDependencies, packageReferences, XCRemoteSwiftPackageReference, XCSwiftPackageProductDependency)

## Decisions Made
- Confirmed via `read_first` that all five files were history-only with no non-history exports before deleting (each file's header comment and content confirmed history-specific purpose; `HistorySearchTests.swift` tests `SearchResultsMerger` but specifically covers history-query detection behavior per its own header — `SearchResultsMerger.swift` itself is untouched and still used by `SearchView.swift`).
- Used `sed -E` bulk deletion for the single-line pbxproj entries (verified exact match count before/after: 20 lines removed for Task 2, matching the four-entry-per-file × five-files count from the plan's pbxproj_map) and targeted `Edit` for the three multi-line GRDB blocks (XCRemoteSwiftPackageReference + two XCSwiftPackageProductDependency blocks) to preserve exact structure of neighboring package entries.
- Left `Flint.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` untouched — it still has a stale GRDB pin, but this file is outside the plan's `files_modified` scope and is auto-regenerated by Xcode's package resolver; it cannot cause a build failure on its own since the package product reference is already gone from pbxproj.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The tree is now fully history-free: five history files deleted, pbxproj has zero references to them or to GRDB, and no source file imports GRDB.
- `plutil -lint` confirms the pbxproj is structurally valid, but an actual `xcodebuild` clean build + test run is deferred to the Wave-4 build-verification gate per this plan's `<verification>` section — that step will confirm package-graph resolution succeeds without GRDB and that `Package.resolved` gets pruned/regenerated correctly on next Xcode package resolve.
- No blockers identified.

---
*Phase: 06-remove-the-history-feature*
*Completed: 2026-07-02*
