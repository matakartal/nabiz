# Nabız design rules

Nabız should feel like a **native macOS menu that grew up**: the same material, insets, row height and hover as the
system's own menus, plus a few extras (meters, inline actions, summaries) that never break that grid. Everything is
built from a handful of components. A new section is a list of `PanelRow`s, not new layout code.

The source of truth is the code: tokens in `Sources/Nabiz/DesignSystem/Theme.swift`, panel components in
`Sources/Nabiz/Views/Panel.swift`. When a rule here and the code disagree, fix one of them in the same pull request.

## 1. One grid, copied from native menus

- Panel width **320** (300 or 360 by setting). Icons start **16 pt** in (`Theme.menuInset`), text **40 pt** in
  (`Theme.menuTextInset`), values end **16 pt** before the edge.
- The hover highlight is inset **6 pt** (`menuHighlightInset`) with radius **6** (`fieldRadius`), exactly like an
  `NSMenu` item.
- Row height **24** (22 compact, 28 roomy: `Theme.menuRow`). Heading lines **20** (`menuLine`).
- The icon column is 16 pt: an SF Symbol in `Theme.body`, muted; an app's own icon; or a 6 pt dot for a status.
- Never nudge one element with a magic number. Derive it from the grid tokens; if it still looks wrong, fix the token
  or the component so every row follows.

## 2. Every row is one line

- `PanelRow(icon:title:subtitle:)`: the subtitle sits on the same line, `Theme.small`, muted, truncating first, with
  the full text as a tooltip. No second line, no per-row vertical padding.
- Anything longer (paths, durations, explanations) goes in `.help(…)`.

## 3. The trailing column: a value, or actions on hover

- `Value(text, color:)`: `Theme.body`, `.monospacedDigit()`, muted unless the value *means* something.
- `TwoColumns(a, b)` keeps numbers aligned across rows.
- Rows that act: hover swaps the value for `InlineButton`s, 12 pt apart. Green text for actions, red only for
  destructive ones. Order: open/reveal first, destructive last. More actions go in a "⋯" menu.
- A whole-row tap only when there is one obvious thing to do. Busy: a mini `ProgressView` and no hover.
- A section with more than one item ends with a "do it to all" row ("Shut down all").

## 4. Sections

- `CollapsibleSection` = `PanelDivider` + `SectionHeader` + rows. Closed, the header shows a **one-line summary** on
  the right, orange when it needs attention, muted otherwise. Nothing important disappears when folded.
- **Hide a section that has nothing to show.** No "No simulators" rows.
- Every section can be shown, hidden and reordered in Settings → Panel, and remembers if it is open.

## 5. Colour

- Surfaces near-white / near-black (`surface`, `surfaceRaised`, `field`); text `text` / `textMuted`; lines
  `hairline`; fills `hover` and `track`.
- **One accent** (`Theme.accent`, picked by the user, green by default). It means good or on. Read it live; never
  store it.
- **Orange means running low** (`Theme.warning`). **Red means alarm or destructive**, nothing else. Neither is ever an
  accent choice.
- Brand colours only for brand marks (AI providers' real logos), never a provider's first colour alone.

## 6. Type

- Two sizes per surface: **13** (`Theme.body`, `bodyStrong`) and **11** (`small`, `smallStrong`); **15** semibold
  `title` for page titles only; **20** `input` for the launcher field. Always the `Theme` fonts — never
  `.system(size:)` — because the user can pick text size and typeface.
- Every number is `.monospacedDigit()`. Headings are sentence case. Weight, not colour, makes hierarchy.

## 7. Spacing and shape

- Spacing only `4 · 8 · 12 · 16 · 24 · 32` (`Theme.Spacing.xs … xxl`).
- Radii only **10** (`radius`: windows, panel, big tiles) and **6** (`fieldRadius`: highlights, fields, buttons);
  capsules for pills and chips. Always `style: .continuous`.
- No cards in the panel, no drop shadows on content, no borders except a 1 pt `hairline`.

## 8. Material and windows

- The panel is a non-activating `KeyPanel` on the menu material (`MenuMaterial`). **Frosted by default; opaque only
  by the user's setting** (`panelStyle`) — use `.appearanceRoot()`, never a hard-coded opaque background.
- Big windows (Settings, AI chat, editors): one top bar level with the window buttons (`WindowChrome.apply`), a
  resizable sidebar, Settings pages as `Form { … }.formStyle(.grouped)` with a `PageHeader` and `SettingsSection`s,
  each listed in `SettingsSearch.swift` so search can find it.
- Light and dark, frosted and opaque, compact and roomy, large text: all must stay on the grid.

## 9. Menu bar

- Stacked by default: a 9 pt label over an 11 pt semibold tabular value, drawn as one template image so macOS tints
  it. Labels at most 6 characters; values short. Colour only for real states and only when the user turned it on.
- Routine confirmations flash in place of the values for 1.5 s — no alerts or notifications for routine actions.

## 10. Motion

Small and native: chevron rotation, 0.15–0.25 s ease-out fades. No shimmer over text, no whole-window glow. Respect
Reduce Motion.

## 11. Words

- Every user-facing string is bilingual: `L("Türkçe", "English")`. Data (names, numbers) uses `Text(verbatim:)`.
- Plain, short words for people who aren't technical. "…" ends an item that opens more UI.
- One-tap fixes in place (Shut down, Stop, Quit). Never send the user to Activity Monitor or Terminal to do it.
- Accessibility: tappable rows are buttons, icon-only buttons have labels, anything shortened has `.help`.

## Checking a change

```bash
python3 scripts/lint-ui.py <changed files>        # must report 0 for code you touched
build/Nabiz.app/Contents/MacOS/Nabiz --snapshot out.png --dark          # the panel, live data
build/Nabiz.app/Contents/MacOS/Nabiz --snapshot out.png --settings --page general --chrome
```

In the snapshot check that icons sit on one vertical line, titles on the 40 pt line, values on one right edge, every
row the same height, chevrons in one column, and no two controls touching. Look at light and dark, Turkish and
English. The screenshot editor, the recording editor and the AI chat still carry some sizes of their own (known
debt): don't copy those into the panel, and don't add new ones.
