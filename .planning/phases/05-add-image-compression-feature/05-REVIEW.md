---
phase: 05-add-image-compression-feature
reviewed: 2026-06-30T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - Tools/ImageCompress/ImageCompressTransformer.swift
  - Tools/ImageCompress/ImageCompressViewModel.swift
  - Tools/ImageCompress/ImageCompressView.swift
  - Tools/ImageCompress/ImageCompressDefinition.swift
  - Core/Services/ToolRegistry.swift
findings:
  critical: 2
  warning: 3
  info: 0
  total: 5
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-06-30
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Five files were reviewed for the Image Compressor feature. The transformer core (ImageCompressTransformer) is robustly implemented: all ImageIO calls are guard-gated, EXIF/ICC metadata is carried forward via `AddImageFromSource`, partial writes are cleaned up on finalize failure, and the disambiguation loop never overwrites an existing file. INFRA-17 is satisfied there.

Two critical bugs exist in the ViewModel and View layers: a data race in the `.onDrop` handler where multiple `NSItemProvider` callbacks concurrently mutate an unsynchronized Swift Array, and a task-identity gap where a cancelled batch Task's cleanup block runs against the new batch's state, corrupting `isCompressing`, the results rows, and the history store. Three warnings round out the findings.

---

## Critical Issues

### CR-01: Concurrent `urls.append` from multiple `NSItemProvider` callbacks is an unprotected data race

**File:** `Tools/ImageCompress/ImageCompressView.swift:44-63`

**Issue:** The `.onDrop` handler collects dropped file URLs by creating a local `var urls: [URL] = []` and then calling `provider.loadItem(…)` for each provider inside a `DispatchGroup`. Each `loadItem` completion block fires on a private background dispatch queue (per NSItemProvider documentation). When the user drops two or more files simultaneously, multiple completion blocks run concurrently and all call `urls.append(url)` on the same Array. Swift's standard Array is not thread-safe for concurrent writes: this is an unprotected data race that produces undefined behavior — typically a corrupted array (duplicate entries, missing entries, or a crash via realloc).

The Swift 6 strict concurrency checker may not catch this because the closure captures a local `var` rather than an actor-isolated property, and `NSItemProvider.loadItem`'s completion type may not be annotated `@Sendable` in all SDK versions. The runtime race is real regardless.

**Fix:** Serialize all appends through the main queue or use an actor-isolated accumulator. The simplest correct pattern:

```swift
.onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
    let group = DispatchGroup()
    // Use a serial queue for accumulation — eliminates the concurrent-append race.
    let accumulatorQueue = DispatchQueue(label: "flint.drop.accumulator")
    var urls: [URL] = []
    for provider in providers {
        group.enter()
        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                accumulatorQueue.sync { urls.append(url) }
            }
        }
    }
    let capturedQuality = quality / 100.0
    group.notify(queue: .main) {
        Task { @MainActor in
            viewModel.compress(urls: urls, quality: capturedQuality)
        }
    }
    return true
}
```

---

### CR-02: Cancelled batch Task's cleanup block runs unconditionally against the new batch's state

**File:** `Tools/ImageCompress/ImageCompressViewModel.swift:156-219`

**Issue:** When `compress(urls:quality:)` is called while a previous batch Task (T1) is already running, the code calls `task?.cancel()`, replaces `self.rows` with the new batch rows, and starts a new Task (T2). However, `task?.cancel()` only *signals* cooperative cancellation — T1 continues executing until it reaches a `Task.isCancelled` check or returns.

There are two `guard !Task.isCancelled` checks inside the for-loop (lines 159, 169), but **neither is placed after** the `await Task.detached { ... }.value` on line 173. When T1's detached child task completes (ImageIO work is never cancellable), T1 resumes and unconditionally executes `await MainActor.run { self.rows[i].apply(result) }` (line 180) against what is now T2's rows — mutating the wrong row with a stale result.

After the for-loop breaks (or finishes), T1 falls through to the "Batch complete" `MainActor.run` block at line 189 **with no Task.isCancelled check**. This block:

1. Sets `self.isCompressing = false` — hides the Cancel button while T2 is still actively compressing.
2. Reads `self.rows` (T2's rows) to count `.done` items and collect filenames.
3. Calls `capturedOnSave(HistoryEntry(…))` with T2's filenames and an incorrect savings metric — saving a spurious or mixed-data history entry.

**Fix:** Add a task-identity token (`batchID: Int`) that is incremented on every `compress()` call and captured before the Task launches. At every point where the Task will modify shared state, check that the captured ID still matches the current ID:

```swift
private var currentBatchID: Int = 0

func compress(urls: [URL], quality: Double) {
    task?.cancel()
    currentBatchID &+= 1
    let batchID = currentBatchID
    rows = urls.map { CompressRow(sourceURL: $0, format: .from(url: $0)) }
    isCompressing = true
    let capturedOnSave = onSaveHistory

    task = Task { [weak self] in
        for (i, url) in urls.enumerated() {
            guard !Task.isCancelled else { break }
            await MainActor.run { [weak self] in
                guard let self, self.currentBatchID == batchID else { return }
                if i < self.rows.count { self.rows[i].state = .compressing }
            }
            guard !Task.isCancelled else { break }

            let result = await Task.detached(priority: .userInitiated) {
                autoreleasepool { ImageCompressTransformer.compress(url: url, quality: quality) }
            }.value

            // Check cancellation AND batch identity after the non-cancellable ImageIO work
            guard !Task.isCancelled else { break }
            await MainActor.run { [weak self] in
                guard let self, self.currentBatchID == batchID else { return }
                if i < self.rows.count { self.rows[i].apply(result) }
            }
        }

        await MainActor.run { [weak self] in
            guard let self, self.currentBatchID == batchID else { return }
            self.isCompressing = false
            // ... history logic unchanged ...
        }
    }
}
```

---

## Warnings

### WR-01: Missing `Task.isCancelled` check after the detached ImageIO task resumes

**File:** `Tools/ImageCompress/ImageCompressViewModel.swift:173-185`

**Issue:** Between `await Task.detached { ... }.value` (line 173) and `await MainActor.run { self.rows[i].apply(result) }` (line 180), there is no cancellation check. The `Task.detached` child task runs ImageIO work that is not itself cancellable; when it returns, the parent Task applies the result to `self.rows[i]` even if the batch was cancelled in the interim. In isolation (before CR-02 is fixed) this writes a stale image compression result into the live rows array. After CR-02 is fixed with a batch-ID guard this check is partially mitigated, but a standalone `guard !Task.isCancelled else { break }` after the `await .value` line is the minimal correct fix and should be added regardless.

**Fix:** Insert between lines 177 and 179:
```swift
}.value

guard !Task.isCancelled else { break }

await MainActor.run { [weak self] in
```

---

### WR-02: `NSImage(contentsOf:)` in `thumbnailView` performs synchronous disk I/O on the main thread with no caching

**File:** `Tools/ImageCompress/ImageCompressView.swift:221-234`

**Issue:** `thumbnailView(for:)` calls `NSImage(contentsOf: url)` unconditionally on every SwiftUI render pass. This is synchronous, blocking, main-thread disk I/O. In a batch of N images, every per-row state transition (`.pending` → `.compressing` → `.done`) triggers a full SwiftUI body re-evaluation that re-calls this function for every row, re-reading every source image from disk. For a batch of 10 images averaging 5 MB each, each state transition causes 50 MB of disk reads on the main thread. For large HEIC or TIFF files, this will noticeably stall the UI during compression — undermining the "zero friction" guarantee.

The result is never cached, so the same file is read tens of times over the course of a batch.

**Fix:** Cache the `NSImage` result in a `@State` or `@StateObject` dictionary keyed by URL, populated once (lazily or via `.task(id: url)`). A minimal approach using `.task`:

```swift
// In CompressRow view or wrapper:
@State private var thumbnails: [URL: NSImage] = [:]

// In rowView, trigger async load once:
.task(id: row.sourceURL) {
    if thumbnails[row.sourceURL] == nil {
        thumbnails[row.sourceURL] = await Task.detached {
            NSImage(contentsOf: row.sourceURL)
        }.value
    }
}
```

---

### WR-03: `quality` from `@AppStorage` is never clamped before use

**File:** `Tools/ImageCompress/ImageCompressView.swift:17,57,318`

**Issue:** `@AppStorage("imageCompressQuality") private var quality: Double = 75` is read and divided by 100.0 at the call site (`quality / 100.0`) without range validation. If the UserDefaults value is corrupted or manually set outside the `0...100` range (e.g., `150.0`, `-10.0`), the resulting quality passed to `ImageCompressTransformer.compress` is outside the documented `0.0–1.0` range for `kCGImageDestinationLossyCompressionQuality`. ImageIO's behavior for out-of-range quality values is undocumented and implementation-dependent; empirically it clamps, but this is not guaranteed. The `Slider` view enforces `in: 0...100` at interaction time, but `@AppStorage` bypasses this constraint.

**Fix:** Clamp before dividing:
```swift
// In onDrop group.notify block and chooseImages():
let capturedQuality = (quality.clamped(to: 0...100)) / 100.0
```

Or add a computed property:
```swift
private var clampedQuality: Double { quality.clamped(to: 0...100) / 100.0 }
```

where `clamped(to:)` is `max(range.lowerBound, min(range.upperBound, self))`.

---

_Reviewed: 2026-06-30_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
