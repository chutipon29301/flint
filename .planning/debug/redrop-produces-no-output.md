---
status: diagnosed
trigger: "Compressing the same source twice writes photo-compressed then photo-compressed-1 without overwriting. Re-drop shows NOTHING new in table AND writes NO second file. Tested immediately after Test 9 (stuck-Cancel)."
created: 2026-07-01T00:00:00Z
updated: 2026-07-01T00:00:00Z
---

## Current Focus

hypothesis: DOWNSTREAM of Test-9 — clean re-drop produces output, but stale in-flight non-cancellable ImageIO from Test 9 masks/collides with the second batch.
test: static trace of compress→cancel→compress concurrency + onDrop provider handling
expecting: determine whether second compress reaches disk write
next_action: finalize verdict (diagnose-only)

## Symptoms

expected: Second drop of same image writes photo-compressed-1 and shows a new result row.
actual: Re-drop shows NOTHING new in table AND writes NO second file. Re-drop appears to do nothing.
errors: (none reported)
reproduction: UAT Test 10. Drop image, let finish. Drop SAME image again. Tested IMMEDIATELY AFTER Test 9 (stuck-Cancel bug). ViewModel may be in poisoned state.
started: Discovered Phase 05 UAT, right after Test 9 cancel bug.

## Eliminated

- hypothesis: disambiguatedCompressedURL is broken (would write -compressed but never -compressed-1)
  evidence: Transformer.swift lines 198-217 — fileExists loop is correct; produces -compressed then -compressed-1 deterministically. Not the failure.
  timestamp: 2026-07-01

- hypothesis: Orphaned Task1.detached writes its stale result onto Task2's rows[0], overwriting the fresh row
  evidence: Task1 resumes after its detached work at line 181 `guard !Task.isCancelled` — Task1 IS cancelled, so it breaks BEFORE the apply MainActor.run (line 184). Task1 never touches rows after cancellation (WR-01/CR-02 guards working). So Task2's rows are not corrupted by Task1.
  timestamp: 2026-07-01

- hypothesis: ViewModel software-state is poisoned (task=nil / isCompressing=false blocks a fresh batch)
  evidence: compress() unconditionally rebuilds `rows = urls.map{...}` (line 146), sets isCompressing=true (147), assigns a brand-new uncancelled `task = Task2` (156). task?.cancel() at line 143 being a no-op (task already nil) is harmless. A fresh compress() with non-empty urls always supersedes prior state.
  timestamp: 2026-07-01

## Evidence

- timestamp: 2026-07-01
  checked: ImageCompressViewModel.compress() lines 141-156 and cancel() lines 235-239
  found: cancel() sets task=nil. Second compress() line 143 `task?.cancel()` is therefore a NO-OP — but harmless: the only thing it would cancel (Task1) already self-terminated via its own isCancelled guards. compress() then unconditionally rebuilds rows, sets isCompressing=true, assigns a brand-new task=Task2 whose Task.isCancelled is false. No mechanism makes Task2 inherit Task1's cancelled state.
  implication: A second compress() with non-empty urls WILL run Task2 to completion and WILL reach the disk write. Re-drop "does nothing" is NOT explained by ViewModel software-state poisoning.

- timestamp: 2026-07-01
  checked: ImageCompressView.onDrop handler lines 43-69
  found: onDrop iterates ALL providers, appends URLs via a serial queue, then group.notify → Task{ compress(...) }. No dedupe, no "ignore while compressing" guard. A genuine second drop yields a non-empty urls array → compress runs → disk write at -compressed-1 on a clean run.
  implication: For a CLEAN second drop (fresh launch), output IS produced (-compressed-1) and a new row IS shown. The reported "nothing happens" does NOT match the clean-launch code path → the symptom is tied to the Test-9 residue, not the drop handler.

- timestamp: 2026-07-01
  checked: Test-9 → Test-10 ordering, same source file, isCompressing button state
  found: Test 10 re-dropped the SAME image that Test 9 left stuck. Test 9's orphaned non-cancellable Task.detached is STILL running slow ImageIO/PNG-quantization on that source when Test 10's drop occurs (that slow synchronous work is exactly why Test 9's row is stuck). On the second drop, compress() replaces `rows` with ONE fresh .pending row for the SAME filename — visually indistinguishable from the stuck spinner row.
  implication: "Shows nothing new in the table" is a VISUAL artifact — same filename + row replacement landing on an identical-looking row (spinner → spinner).

- timestamp: 2026-07-01
  checked: disk-write reachability while Task1's detached ImageIO is mid-flight on the same source (TOCTOU, Transformer comment line 196)
  found: Two Task.detached jobs run ImageCompressTransformer.compress(url:) on the SAME source concurrently. Both call disambiguatedCompressedURL(for: A). In the TOCTOU window photo-compressed.jpg may not yet exist for either, so BOTH resolve to the SAME destURL and the -compressed-1 disambiguation never triggers. While both are still in slow quantization at observation time, no NEW file has appeared yet.
  implication: "No second file" is explained by (a) slow in-progress quantization at observation time and/or (b) a TOCTOU collision where both batches target photo-compressed.jpg, so -compressed-1 never materializes. Trigger is the Test-9 slow non-cancellable work — not an independent drop-handler defect.

## Resolution

root_cause: |
  DOWNSTREAM SYMPTOM of the Test-9 cancel bug — not an independent drop-handler defect.

  The ViewModel does NOT carry poisoned software-state across compress() calls: a
  fresh compress() rebuilds `rows` and assigns a brand-new uncancelled Task, so a
  clean second drop reliably runs to completion and reaches disambiguatedCompressedURL
  (which is correct in isolation).

  The Test-10 symptom is produced by the Test-9 bug's RUNTIME residue:
  1. Test 9 left a non-cancellable Task.detached still grinding slow PNG quantization
     on the SAME source file (why the row is stuck and the file isn't written yet).
  2. Test 10 re-drops that SAME file; compress() replaces `rows` with one fresh row
     for the SAME filename — visually identical to the stuck row → "nothing new in table."
  3. Two Task.detached jobs now run ImageIO on the same source concurrently. Both hit
     disambiguatedCompressedURL in the TOCTOU window where photo-compressed.jpg doesn't
     yet exist, so both target photo-compressed.jpg (-compressed-1 never triggers), and
     while both are still in slow quantization no second file has appeared — "no second file."

  Disambiguation (D-07/D-08) is correct and reachable on a clean re-drop. The defect
  surfaces only because the Test-9 work is non-cancellable and slow, leaving stale
  in-flight ImageIO that masks/collides with the new batch.
fix: (diagnose-only — not applied)
verification: (diagnose-only)
files_changed: []
