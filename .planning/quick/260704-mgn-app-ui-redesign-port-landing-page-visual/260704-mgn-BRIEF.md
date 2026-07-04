# Flint — App UI Redesign Brief

**Goal:** bring the native macOS app's visual design up to the standard of the landing page (`docs/index.html`), porting the same identity into native SwiftUI idioms. This is a **visual-layer refactor only** — no functionality, information architecture, or tool behavior changes.

The canonical source of truth for colors and type is the CSS `:root` block in `docs/index.html` in this repo. Read those exact values and mirror them; do not invent new ones.

---

## The identity (the "why")

Flint = a cold, hard flint stone that throws a warm spark when struck. The whole visual language is that tension: a disciplined, cool **graphite** base with a single warm **ember** accent used *sparingly*, only at the moments that matter. The app currently uses stock SwiftUI defaults (system blue, default fonts, system alert red/yellow) and reads as generic. The redesign gives it the same point of view the site has.

**One rule above all others: the ember accent is a scalpel, not a bucket.** Most of the UI stays in cool greyscale. Ember appears only at: the primary action, the selected/active tool, the clipboard "Detected" suggestion, focus rings, and the single most important syntax token. If you find yourself painting large areas orange, stop — that's the failure mode.

---

## Step 1 — Build the design system first

Before touching any view, create a single source of truth, e.g. `DesignSystem.swift` (Color + Font + spacing + radii extensions). Every view must consume these tokens — no hard-coded colors or fonts anywhere else. This central file is what keeps the app and the website in lockstep.

### Color tokens (exact — from the site's CSS `:root`)

| Token | Hex | Use |
|---|---|---|
| `graphite950` | `#14171c` | App/popover background (base). **Not** pure black. |
| `graphite900` | `#1a1e24` | Cards, raised surfaces, detail panels |
| `graphite850` | `#1f242b` | Hover / pressed surface |
| `graphite800` | `#242a32` | Borders, dividers |
| `graphite700` | `#333b45` | Stronger borders, kbd chips |
| `ash` | `#8a94a2` | Secondary/muted text, inactive icons |
| `ashDim` | `#626b78` | Tertiary text, captions, placeholders |
| `chalk` | `#e8ebef` | Primary text (cool white) |
| `spark` | `#ff7a1a` | **The** accent — primary action, active state, detect banner, focus |
| `sparkHot` | `#ffb347` | Ember highlight / hover of accent, key syntax token |

### Syntax-highlighting tokens (for JSON / JWT / code views)

| Token | Hex | Applies to |
|---|---|---|
| `codeKey` | `#ffb347` | JSON keys, JWT claim names |
| `codeString` | `#6fd3b8` | String values |
| `codeNumber` | `#c9a8ff` | Numbers, booleans, timestamps |
| `codePunct` | `#626b78` | Braces, brackets, colons, commas |

> This replaces the default red-strings / blue-numbers scheme currently in the JWT view. Match the site's palette exactly so the code blocks on the site and in the app look identical.

### Semantic states (banners like "Token expired", "Missing claims")

Do **not** use stock system red/yellow — they clash with the ember accent and look default. Use palette-harmonized, desaturated tones on a low-alpha tinted surface, and keep **warning visually distinct from the ember accent** so the accent stays special:

- **Error** (e.g. "Token expired"): rose-red `#e5657f` text/icon on `rgba(229,101,127,0.10)` fill, 1px `rgba(229,101,127,0.28)` border.
- **Warning** (e.g. "Missing claims"): muted gold `#d9a441` (deliberately duller than `spark`) on `rgba(217,164,65,0.10)` fill, matching border.
- **Success / valid**: reuse `codeString` jade `#6fd3b8`.

### Typography

The app is a developer tool, so monospace *is* the vernacular — lean into it the way the site does.

- **Mono** — tool names, section labels, code/data, kbd hints, the search field. Use **SF Mono** via `Font.system(.body, design: .monospaced)` (or `NSFont.monospacedSystemFont`). This is zero-bundle, native, and reads nearly identically to the site's JetBrains Mono. *(Alternative: if you want pixel-exact parity, bundle `JetBrainsMono.ttf` in Resources, register it via `ATSApplicationFontsPath` in Info.plist, and load with `Font.custom`. Default to SF Mono unless parity matters.)*
- **Body / UI prose** — descriptions, helper text. System font (`Font.system`, default design).
- **Scale** — establish a small deliberate scale (e.g. label 11–12 uppercase w/ letter-spacing, body 13, tool title 14, detail heading 16). Section labels are uppercase mono in `ash`, matching the site's `.label` treatment.

### Spacing, radius, elevation

- Corner radius: cards/panels ~11–12pt, controls ~8–9pt, chips ~5–6pt (mirrors the site).
- Borders: 1px `graphite800`, brightening to `spark` on hover for interactive cards.
- Elevation: prefer flat surfaces separated by borders + the graphite scale, not heavy shadows. One soft shadow max, on the popover itself.

---

## Step 2 — Restyle screen by screen

Keep the app compiling after each screen. Suggested order:

**1. Tool launcher / grid**
- Background `graphite950`; each tool a `graphite900` card, 1px `graphite800` border, ~11pt radius.
- Tool icons: monochrome — `ash` at rest, `spark` when the card is hovered/selected. Kill the system-blue icons.
- Hover/selected card: border → `spark`, surface → `graphite850`, subtle 1–2pt lift.
- Search field: `graphite950` inset, `graphite800` border, mono placeholder in `ashDim`, `spark` focus ring.
- Keep the grid layout and all 13 tools exactly as they are.

**2. Clipboard "Detected" banner** — *this is the app's signature moment.*
- This is the equivalent of the site's "spark" — clipboard auto-detect surfacing the right tool. Style it with the ember accent: `spark`-tinted surface, `spark` "Open" button, mono label. This is the one place the accent gets to shine in the launcher.

**3. Tool detail view — JWT Decoder**
- Header: tool title in `chalk`, "All Tools" back link in `spark`, section labels ("JWT Token", "Header", "Payload", "Signature") uppercase mono in `ash`.
- Code blocks: apply the syntax tokens above (keys amber, strings jade, numbers/timestamps purple, punctuation ash). Monospaced, `graphite950` inset background.
- Copy buttons: `ash` icon, `spark` on hover, brief `codeString` "Copied" confirmation.
- Status banners: apply the semantic-state styling above (replace the stock red/yellow).
- Apply the same detail-view pattern to every other tool's screen so they're consistent.

---

## Guardrails — stay native, don't break these

- **Keyboard & focus:** every control keyboard-reachable; visible focus ring (use `spark`). Don't remove focus indicators for aesthetics.
- **VoiceOver:** preserve/adds accessibility labels; don't rely on color alone to convey state (pair the error/warning color with an icon + text, which the current design already does — keep that).
- **Reduce Transparency / Reduce Motion:** respect both. Any hover/transition animation must no-op under Reduce Motion.
- **Menubar constraints:** this is a `MenuBarExtra` popover with a constrained width — test at the real popover size, not a full window. Don't introduce layouts that overflow.
- **Appearance:** the popover is dark, so **ship dark-only for v1** to move fast (state this as an intentional choice). If light mode is in scope later, define a parallel light token set in the same `DesignSystem.swift` — never hard-code, so light mode is a token swap, not a rewrite.
- **No dependency creep:** pure SwiftUI + the fonts already available. No new UI libraries.

---

## Deliverable & process

1. Create `DesignSystem.swift` with all tokens above; confirm values match `docs/index.html`'s `:root`.
2. Refactor views to consume tokens, screen by screen, in reviewable commits (one screen ≈ one commit). Keep the build green throughout.
3. For each restyled screen, capture a before/after screenshot at real popover size.
4. Do **not** change any tool's logic, inputs/outputs, layout structure, or the set of 13 tools. Visual layer only.

**Definition of done:** a developer landing on the site, downloading, and opening the app should feel one continuous product — same graphite base, same ember accent used with the same restraint, same code-syntax colors, same type personality.
