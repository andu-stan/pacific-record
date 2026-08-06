# Design System — Music Library Client

Reverse-engineered of Roon from 10 product screenshots (desktop app, tablet, mobile, light + dark).

---

## 1. Foundations

### 1.1 Brand / Primary

The system is built on a single saturated indigo-violet used for the hero banner, all data
visualisation, progress fills, active nav, and links.

| Token | Hex | Use |
|---|---|---|
| `--primary-900` | `#2A1BD1` | Pressed state of the hero banner / primary button |
| `--primary-700` | `#3826EA` | **Light-mode hero banner fill**, primary CTA |
| `--primary-600` | `#4B3FE8` | Primary button default, active nav item (light) |
| `--primary-500` | `#6C63E8` | **Core accent** — progress bars, donut leader arc, active nav (dark) |
| `--primary-400` | `#8F88EE` | Secondary chart segment, hover on dark |
| `--primary-300` | `#B4AFF4` | Tertiary chart segment |
| `--primary-200` | `#D6D3FA` | Quaternary chart segment, progress track (light) |
| `--primary-100` | `#E9E7FC` | Donut track / empty ring (light mode) |

`--primary-500` is the one value that must survive theme switching: it reads on both `#0E0E0E`
and `#FFFFFF` (4.6:1 and 5.1:1 against white text/black text respectively at the sizes used).

### 1.2 Secondary / Accent

| Token | Hex | Use |
|---|---|---|
| `--accent-warm` | `#E8462F` | Underline on the "New releases" tab set — used *once per screen*, never as a fill |
| `--accent-alert` | `#F0453B` | Warning glyph in the top bar |
| `--accent-neutral` | `#6B6B6B` | The "Other" bucket in every chart — deliberately desaturated so it recedes |

There is no true secondary brand colour. Hierarchy is carried by **tints of the primary**, not by
a second hue. Chart series are always ordered: `500 → 400 → 300 → 200 → neutral`.

### 1.3 Surfaces — Dark (default)

| Token | Hex | Notes |
|---|---|---|
| `--bg-canvas` | `#0E0E0E` | App background, behind everything |
| `--bg-chrome` | `#131313` | Left nav rail + top bar (reads as the same black, 1 step up) |
| `--bg-surface` | `#1A1A1A` | Section container ("What you've been listening to") |
| `--bg-surface-2` | `#232323` | Cards nested inside a section (Genres / Top artists / Top albums) |
| `--bg-surface-3` | `#2E2E2E` | Pill buttons ("MORE"), popovers, focus panels |
| `--bg-overlay` | `#3A3A3A` | Modal / dropdown sheet over dimmed content |
| `--scrim` | `rgba(0,0,0,0.55)` | Behind overlays |
| `--border-subtle` | `#2A2A2A` | Card hairlines |
| `--border-rule` | `#3A3A3A` | Full-width divider under section titles |

Nesting rule: **canvas → surface → surface-2 → surface-3**, never skip a step, never more than
three levels deep. Cards on dark are separated by *value*, not by shadow.

### 1.4 Surfaces — Light

| Token | Hex |
|---|---|
| `--bg-canvas` | `#FFFFFF` |
| `--bg-chrome` | `#FAFAFA` |
| `--bg-surface` | `#F4F5F7` |
| `--bg-surface-2` | `#FFFFFF` |
| `--bg-surface-3` | `#E9EBEF` |
| `--border-subtle` | `#E3E5EA` |
| `--border-rule` | `#D9DCE2` |

Note the **inversion**: on dark, nested cards get *lighter*; on light, the section container is
grey (`#F4F5F7`) and the cards inside return to pure white. Elevation always moves *toward* the
opposite pole of the theme.

### 1.5 Text

| Token | Dark | Light | Use |
|---|---|---|---|
| `--text-primary` | `#FFFFFF` | `#111214` | Headers, values, track titles |
| `--text-secondary` | `#B4B4B4` | `#5A5E66` | Artist names, metadata, inactive tabs |
| `--text-tertiary` | `#7C7C7C` | `#8A8F98` | Caption/eyebrow, timestamps, counts |
| `--text-on-primary` | `#FFFFFF` | `#FFFFFF` | Inside the indigo banner |
| `--text-on-primary-dim` | `rgba(255,255,255,0.72)` | — | "Added 6 days ago" inside the banner |

---

## 2. Typography

Two families. A high-contrast **display serif** appears exactly once per screen (the greeting),
everything else is a humanist UI sans.

```
--font-display: "Playfair Display", "Georgia", serif;   /* greeting only */
--font-ui:      "Inter Tight", "Segoe UI", system-ui, sans-serif;
--font-mono:    ui-monospace, "SF Mono", monospace;      /* format badges: FLAC 88/24 */
```

### 2.1 Scale

Base 16px, ratio ≈ 1.25 with hand-tuned steps.

| Role | Size / Line | Weight | Tracking | Example |
|---|---|---|---|---|
| `display` | 56 / 64 | 400 (serif) | −0.02em | "Hi, Mark" |
| `stat` | 40 / 44 | 600 | −0.02em | "66h 47m" |
| `h1` | 24 / 32 | 600 | −0.01em | Page title |
| `h2` | 18 / 24 | 600 | −0.005em | "What you've been listening to" |
| `h3` | 16 / 22 | 600 | 0 | "Genres", "Your top artists" |
| `body` | 14 / 20 | 500 | 0 | Track title, artist row |
| `body-sm` | 13 / 18 | 400 | 0 | Album subtitle, secondary line |
| `caption` | 12 / 16 | 400 | 0 | Timestamps, "Last 4 weeks", counts |
| `overline` | 11 / 14 | 600 | **0.08em**, uppercase | "ARTISTS", "TIME LISTENED LAST 4 WEEKS", "MORE" |

Mobile/tablet reduces `display` to 40/46 and `stat` to 32/36; all other steps are unchanged
across breakpoints.

### 2.2 Pairing rules
- Serif is display-only: never below 32px, never bold, never more than one instance per view.
- Numeric values use tabular figures (`font-variant-numeric: tabular-nums`) in every stat, duration and count.
- Two weights only in the sans: 400/500 for content, 600 for anything structural. No 700.

---

## 3. Design Tokens

### 3.1 Spacing

4px base grid.

```
--s-1: 4    --s-2: 8    --s-3: 12   --s-4: 16
--s-5: 20   --s-6: 24   --s-8: 32   --s-10: 40
--s-12: 48  --s-16: 64
```

| Context | Value |
|---|---|
| Outer screen margin — desktop | `32px` (content column also max-width capped, see §3.7) |
| Outer screen margin — tablet | `28px` |
| Outer screen margin — mobile | `16px` |
| Section container padding | `24px` |
| Card padding | `20px` (16px on mobile) |
| Gap between sibling cards | `16px` |
| Gap between major sections | `48px` |
| List row vertical rhythm | `16px` gap, `12px` internal |
| Label ↔ value gap | `8px` |

### 3.2 Border radius

| Token | Value | Applied to |
|---|---|---|
| `--r-xs` | `2px` | Progress bar fills / tracks (height 4–6px) |
| `--r-sm` | `4px` | Album art thumbnails, chips, legend swatches |
| `--r-md` | `6px` | **Cards and section containers** — the system's dominant radius |
| `--r-lg` | `10px` | Modals, dropdown sheets, focus popovers |
| `--r-pill` | `999px` | **All buttons** ("MORE", "Play now" dropdown, tab-bar pills), avatars, badges |

Rule of thumb: **containers are square-ish (6px), controls are fully round.** There is no
intermediate button radius — a rectangle with an 8px radius does not exist in this system.

### 3.3 Touch targets & control padding

| Control | Padding | Total height | Min hit area |
|---|---|---|---|
| Pill button ("MORE") | `6px 14px` | `28px` | 44×44 (expanded via invisible inset) |
| Primary button ("Play now") | `12px 24px` | `48px` | 48×48 |
| Icon button (top bar) | `12px` | `48px` | 48×48 |
| Nav rail item | `10px 16px` | `44px` | full-width row |
| Tab (underlined) | `8px 4px`, `24px` gap between tabs | `36px` | 44×44 |
| List row (artist / album) | `12px 0` | `64px` (art 48px) / `80px` (art 64px) | full row |
| Transport control | `14px` | `52px` | 52×52 |
| Dropdown trigger ("All time ▾") | `6px 8px` | `32px` | 44×44 |

**Minimum touch target is 44×44 everywhere**, achieved with negative-margin inset padding when
the visual control is smaller (the 28px "MORE" pill is the canonical case).

### 3.4 Bars & fixed chrome

| Element | Desktop | Tablet | Mobile |
|---|---|---|---|
| Top app bar | `56px` | `56px` | `56px` |
| Left nav rail width | `230px` (compact) / `300px` (roomy) | — | — |
| Now-playing / transport bar | `96px` | `88px` | `72px` |
| Bottom tab bar | — | — | `56px` + safe-area inset |
| Section rule below title | `1px`, `--border-rule`, `16px` below baseline |

The now-playing bar is the only element that is *always* one surface step above the canvas and
spans full bleed edge to edge; content areas must reserve its height as bottom padding.

### 3.5 Elevation / shadow

Shadow is used sparingly — dark mode is almost entirely shadowless and relies on surface value.

| Token | Value | Use |
|---|---|---|
| `--e-0` | `none` | Cards on dark (value-separated only) |
| `--e-1` | `0 1px 2px rgba(16,18,24,0.06)` | Cards on light |
| `--e-2` | `0 4px 12px rgba(16,18,24,0.10)` | Hover lift on cards, pill button hover |
| `--e-3` | `0 12px 32px rgba(0,0,0,0.28)` | Dropdowns, popovers, focus panels |
| `--e-4` | `0 24px 64px rgba(0,0,0,0.45)` | Modal sheets over scrim |
| `--e-bar` | `0 -1px 0 var(--border-subtle)` | Now-playing bar top edge (a hairline, not a shadow) |

On dark, `--e-3`/`--e-4` are paired with a `1px` `rgba(255,255,255,0.06)` inset top border so the
overlay edge remains legible against black.

### 3.6 Data visualisation

- Donut: stroke width `28px` at a `220px` diameter (≈12.7% of diameter); round line caps; `4px` gap between segments; hollow centre, never labelled.
- Progress bar: `6px` height, `--r-xs`, track `rgba(255,255,255,0.10)` on dark / `--primary-100` on light, fill `--primary-500`.
- Activity dots: `4px`–`16px` diameter scaled by value, `--primary-500` at 100% for max, stepping to 35% opacity for the smallest.
- Legend: `10px` square swatch at `--r-sm`, `8px` gap to a `12/16` caption label, wrapped in a 3-column grid.

### 3.7 Layout

| Breakpoint | Width | Grid |
|---|---|---|
| `mobile` | < 640 | 1 column, 16px margins |
| `tablet` | 640–1023 | 2 columns, 24px gutter |
| `desktop` | ≥ 1024 | 3 columns, 16px gutter, content max-width `1120px`, centred inside the rail |

The three-card row (Genres / Top artists / Top releases) is the system's signature block: equal
thirds on desktop, stacked full-width below 640, and always inside one grey section container
with its own title row and a right-aligned period dropdown.

---

## 4. Component recipes

**Section container** — `--bg-surface`, `--r-md`, `24px` padding, title `h2` left / dropdown
right on one baseline, `24px` to content.

**Stat card** — `--bg-surface-2`, `--r-md`, `20px 24px`, `24px` icon (1.5px stroke, currentColor
at `--text-secondary`), value `stat`, label `overline` in `--text-tertiary`, `4px` between them.

**Hero banner** — full-bleed `--primary-700`, `--r-md`, `28px` padding, `h2` title with inline
tab set, `MORE` pill in `rgba(255,255,255,0.18)`, artwork row of 5 at `--r-sm` with a `2px`
white-8% ring.

**Media list row** — `48px`(artist, circular) or `64px`(album, `--r-sm`) artwork, `16px` gap,
title `body` 600, subtitle `body-sm` `--text-secondary`, duration `caption` right-aligned on the
title baseline, `6px` progress bar spanning the text column below.

**Pill button** — `--bg-surface-3`, `--r-pill`, `6px 14px`, `overline` type, no border; hover
lightens one surface step, active adds `--e-2`.

---

## 5. Principles observed

1. **Value, not chrome.** Hierarchy comes from surface lightness steps and type weight; borders and shadows are a last resort.
2. **One accent, many tints.** A single indigo carries brand, state, and all data series.
3. **One serif moment.** The greeting is the only expressive typography; everything else is neutral and dense.
4. **Round controls, square containers.** Radius encodes affordance.
5. **Metadata is caption-grade.** Format badges, timestamps and counts never compete with titles — 11–12px, tertiary, uppercase when structural.
