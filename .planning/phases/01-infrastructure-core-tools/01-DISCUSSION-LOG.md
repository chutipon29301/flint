# Phase 1: Infrastructure + Core Tools - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-25
**Phase:** 1-Infrastructure + Core Tools
**Areas discussed:** Popover layout & nav, Detection banner UX, History panel UX, Tool I/O interaction

---

## Popover Layout & Navigation

### Landing view
| Option | Description | Selected |
|--------|-------------|----------|
| Search-first | Autofocused search at top; pinned row + recent below | ✓ |
| Pinned grid | 6 pinned icons front and center; search below | |
| Last tool | Reopen last-used tool with prior state | |

### Empty-state body
| Option | Description | Selected |
|--------|-------------|----------|
| Recent history | Most recent re-openable transformations | ✓ |
| All tools list | Full categorized 7-tool list | |
| Recent + tools toggle | Recent by default, segmented flip to tools | |

### Tool-view navigation
| Option | Description | Selected |
|--------|-------------|----------|
| Back button + Esc | Top-bar back chevron; Esc returns | |
| Search bar always on top | Persistent search inside tools; no back button | ✓ |

### Esc behavior
| Option | Description | Selected |
|--------|-------------|----------|
| Esc → launcher, Esc → close | Two-stage | ✓ |
| Esc always closes | Single-stage; switch via search | |

**User's choice:** Search-first launcher; recent-history empty state; persistent top search bar inside tools; two-stage Esc.
**Notes:** Explicitly Raycast/Spotlight-like model. Esc clarified after choosing "no back button."

---

## Detection Banner UX

### Aggressiveness
| Option | Description | Selected |
|--------|-------------|----------|
| Banner, manual accept | Non-destructive banner with Open/Dismiss | ✓ |
| Auto-open matched tool | Open pre-filled immediately with undo | |

### Re-display after dismissal
| Option | Description | Selected |
|--------|-------------|----------|
| Stay dismissed for that value | Track by changeCount/hash; suppress repeat | |
| Always re-show | Show every focus if clipboard matches | ✓ |

### Multi-match handling
| Option | Description | Selected |
|--------|-------------|----------|
| Single best match only | First-match-wins; one suggestion | ✓ |
| Primary + alternates | Best match + 1–2 alternate chips | |

**User's choice:** Manual-accept non-destructive banner; always re-show; single best match only.
**Notes:** Aligns with INFRA-05 "non-destructive" wording and the ordered first-match predicate chain. Minimal dismissal state.

---

## History Panel UX

### Full-history home
| Option | Description | Selected |
|--------|-------------|----------|
| Tool/view in the list | Reachable via search/pinned slot, same nav model | ✓ |
| Dedicated bottom tab/section | Persistent bottom History affordance | |

### Restore behavior
| Option | Description | Selected |
|--------|-------------|----------|
| Open tool with input, re-run | Restore input, recompute output live | ✓ |
| Restore input + saved output | Restore both verbatim, no recompute | |

### Pins vs cap
| Option | Description | Selected |
|--------|-------------|----------|
| Pins exempt from cap, sort to top | Durable pins; Clear removes unpinned only | ✓ |
| Pins are just a flag/filter | Pins still evictable; Clear wipes all | |

**User's choice:** History as a first-class searchable view; click re-runs from saved input; pins are durable and exempt from the 100-cap.
**Notes:** History treated as a re-runnable feature, not a passive log.

---

## Tool I/O Interaction

### When transform runs
| Option | Description | Selected |
|--------|-------------|----------|
| Live (debounced) | Auto-update on type/paste; heavy ops button-triggered | ✓ |
| Explicit button | User clicks to run | |

### Error rendering
| Option | Description | Selected |
|--------|-------------|----------|
| Inline, keep last good output | Subtle inline error; last valid output dimmed | ✓ |
| Replace output with error | Output replaced by error until valid | |

### Copy behavior
| Option | Description | Selected |
|--------|-------------|----------|
| Per-field copy buttons | Per-row copy + primary Copy all | ✓ |
| Single copy, primary result | One Copy button for main output | |

### Default pinned tools (6 of 7)
| Option | Description | Selected |
|--------|-------------|----------|
| JSON, Base64, JWT, URL, Timestamp, UUID | Drops Hash from default pins | ✓ |
| JSON, Base64, JWT, Hash, Timestamp, UUID | Drops URL from default pins | |
| All 7, reconsider cap | Revisit the 6-pin cap | |

**User's choice:** Live debounced transform (heavy ops button-triggered); inline error keeping last-good output dimmed; per-field copy + copy-all; default pins = JSON, Base64, JWT, URL, Timestamp, UUID (Hash unpinned).
**Notes:** Per-field copy required by HASH-04 and URL-04. Heavy ops (file hash, bulk UUID, file Base64) explicitly excluded from live mode.

---

## Claude's Discretion

- Debounce timing, banner animation, SF Symbol icon choices, spacing, and the dimmed-last-good-output visual treatment.
- Whether the History first-class view occupies a default pinned slot or is search-only (pins are filled by tools regardless).

## Deferred Ideas

- None new — discussion stayed within Phase-1 scope. Pre-existing deferrals remain tracked in STATE.md (JSONPath tab, JSON semantic diff, UUID v7 vetting, App Store sandboxing).
