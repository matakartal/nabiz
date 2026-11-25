# Changelog

## 1.6.0

- **Notes, rebuilt** (⌃⌥M): as many notes as you like, the first line is the title. Markdown shows as you type:
  headings, **bold**, _italic_, `code`, quotes and clickable links. Lists and checklists continue on Return and end
  on an empty item; click a box (or ⌘L) to tick it, ⇧⌘L for bullets, ⌘B / ⌘I for bold and italic. ⌘P lists and
  searches every note, ⌘N starts one, ⌘[ ⌘] step through them, ⇧⌘C copies the note. Pin it on top or let it
  behave like a normal window; save any note as a .md file. Word count and checklist progress in the footer.
  Empty notes tidy themselves away; the 1.5 note moves over on its own.
- **Actions palette** (⌘K) in the launcher, for the selected row: open, show in Finder, hide, force quit and copy
  path for apps; pin, open, save as a note or snippet, delete and ten text changes (UPPERCASE, Title Case, one
  line, tidy spaces, pretty JSON, Base64 and URL encode/decode) for clipboard items; paste, copy or delete notes;
  copy and edit quicklinks. Searchable, with its own shortcuts.
- **Favourites** (⇧⌘F): starred apps, commands and quicklinks head the launcher and rank higher.
- **Command mode:** start with `>` to see only commands.
- Notes show up in launcher searches; "New note" and "Notes" commands.
- Launcher rows follow the mouse; fewer stray matches ("saf" finds Safari, not "Display off").
- Releases run the test suite before building.

## 1.5.2

- The launcher looks exactly like the menu bar panel again: the same frosted material, or opaque when the panel is
  set to opaque in Settings → Appearance.

## 1.5.1

- AI limit alerts no longer repeat: each alert goes out once per limit window (matched to the hour, since providers
  report the reset time slightly differently each time), never again within 12 hours, and this survives restarts.
- The launcher is always opaque.
- Weekday chips in Schedules no longer wrap; the next run sits on its own line.

## 1.5.0

- **Launcher** (⌃⌥Space) replaces the quick calculator: apps, system commands (lock, sleep, display off, hide
  others, quit all, empty Trash, restart, shut down, log out — the destructive ones ask first), window layouts,
  every tool, timers ("25 dk"), keep awake, maths/currency/units, quicklinks ("g words", "gh", "yt"… editable with
  `{query}`), snippets and recent items. Arrow keys, ↩ and ⌘↩; Turkish letters match their plain forms.
- **Clipboard history** (⌃⌥V): text, links, colours, files and images up to 3 MB, with search, a preview, pinning
  and delete. ↩ pastes into the app you were in (Accessibility permission), ⌘↩ copies. Concealed/transient copies
  from password managers and excluded apps are never recorded. Up to 50–1000 items, forgotten after 1–90 days or
  never; kept on disk only if you choose.
- **Snippets:** saved text pasted by keyword, with `{date}`, `{time}` and `{clipboard}`.
- **Window layouts:** halves, thirds, centre, maximize, almost maximize, next display; opt-in ⌃⌥ arrow shortcuts.
- **Floating note** above every app and Space.
- **Personalization:** 17 accent colours plus the system accent and a custom colour, light/dark/system theme,
  standard/rounded/monospaced type, compact/normal/roomy rows, thin/thick bars, a menu bar icon of your choice,
  and the panel's section order. "Reset appearance" puts it all back.
- ⌘C, ⌘V, ⌘A and ⌘Z work in Settings and the note.
- **Scheduled tasks:** dark/light mode, stop keeping awake, shut down simulators, quit Docker, clean Rust or Xcode
  caches, clear the clipboard, display off, or a reminder, on chosen days at a set time. A missed task (the Mac
  was asleep) catches up within 6 hours. Ready-made presets; "Run now"; next run shown. Settings → Schedules, or
  right-click the menu bar item.
- **Appearance:** accent colour (orange and red stay reserved for warnings), frosted or opaque panel,
  narrow/normal/wide panel, normal or large text, and coloured menu bar values (orange/red when something needs
  attention, green/red for market moves).
- **Timer** tool: 5–60 minute countdown shown in the menu bar, with a sound and a notification at the end.
- Tool tiles keep their titles readable; shorter titles for Speed, Xcode and Rust.

## 1.4.0

- **Rust build caches:** finds Cargo `target/` folders (only ones cargo signed with CACHEDIR.TAG) in ~/Developer,
  ~/Projects, ~/code and ~/src. A **Clean Rust** tool lists each project and its size before deleting, and a
  suggestion appears above 10 GB. Optional automatic clean-up deletes caches not built for 3–30 days; a project
  built in the last 10 minutes is always skipped.
- Signed with Developer ID (Finqt Veri Hizmetleri, team 3Q2LK426HF) and notarized by Apple: the DMG opens without warnings.

## 1.3.0

- **History:** CPU, RAM, GPU and the main AI limit, kept for 7 days at one-minute resolution (about 40 KB on disk).
  Click the meters, or right-click the menu bar item, for the last hour, day or week.
- **Price alerts:** "tell me when BTC goes above 65,000". Set them in Settings → Markets or from a market row's
  **Set alert**. Each alert fires once and waits to be re-armed. Prices are read every 30 seconds while one is set.
- **Docker and Android:** a suggestion when Docker uses gigabytes with no container running, with one-tap Quit.
  Android emulators are listed and shut down next to the iOS simulators.
- **Updates:** Nabız checks GitHub Releases once a day. When a new version is out, **Update** downloads it,
  replaces the app and reopens it.
- **Release builds:** `./release.sh` signs with your Developer ID, notarizes, staples and (with `publish`) creates
  the GitHub release.
- **Tests:** calculator, pace model, formats and version comparison (`swift test`, also in CI).

## 1.2.0

- Heat row (macOS thermal state), battery health (capacity and cycle count) and the charger's wattage while charging.
- Security check: FileVault, firewall, Gatekeeper, SIP and automatic updates. Any that are off become a suggestion
  that opens the right Settings pane.
- Smart alerts (with Notifications on): CPU above 90% for 3 minutes, naming the busiest app; disk under 10 GB;
  battery at 10%.
- Lighter when idle: the panel is not drawn while closed, and the per-app scan runs less often in the background
  (about 70 MB, 0% CPU at rest).
- Shorter section titles.

- Burn rate for AI limits: each window shows where an even pace would be, turns orange or red when it is heading
  for the limit, and says when it runs out at the current speed ("out in 3h 20m"). The faster of the window average
  and the last hour's rate drives the projection, so a sudden burst is caught at once.
- "Use it or lose it" when over half of a weekly limit is left with under a day to go.
- Notifications for a limit that starts burning fast (once per burn) and for unused weekly limits.
- A suggestion when an AI limit is burning fast.
- Settings pages have a header with their icon, title and a one-line description.

## 1.1.0

- ⌃⌥N opens the panel from anywhere, and right-clicking the menu bar item shows a short menu (Panel, Calculator, Settings, Quit).
- Opt-in notifications when memory turns critical or an AI limit has less than 10% left, once per episode.
- A confirmation in the menu bar after quitting an app or shutting down simulators.
- Markets and exchange rates show "Couldn't connect · Try again" when offline instead of loading forever.
- The status pill in the header opens Suggestions.
- "Reset all settings…" in Settings → General; wider Settings sidebar.
- Section headings are plain again (thin dividers, no cards).

## 1.0.0

First release.

- Menu bar values in two-line or one-line style: CPU, RAM, GPU, swap, network, disk, battery, AI limit, market price, exchange rate.
- Panel on the native menu material, with sections that fold, an accordion mode and summaries on closed headings.
- Suggestions with one-tap fixes: shut down simulators, quit the biggest app, manage storage.
- AI limits for Claude, ChatGPT/Codex and Gemini (opt-in), read with the sign-in their CLIs keep on the Mac.
- Hyperliquid markets: crypto on the main dex and stocks, indices and commodities on every HIP-3 dex.
- Exchange rates with daily change, from the European Central Bank.
- Tools:
  - Spotlight-style calculator with currency and unit conversion (⌃⌥Space)
  - keep awake
  - pick a colour
  - screenshot
  - display off
  - dark mode
  - speed test
  - password and UUID generators
  - eject disks
  - clean Xcode
  - hidden files
  - hide desktop icons
  - clear clipboard
- Settings with a sidebar; Turkish and English.
- Universal build (Apple silicon and Intel); DMG packaging with optional Developer ID signing and notarization.
