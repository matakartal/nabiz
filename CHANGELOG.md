# Changelog

## Unreleased

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
