# Changelog

## Unreleased

- **Open source:** Nabız is now free software under the GPL v3. The name and icon stay with the author; forks use their
  own (see TRADEMARK.md).
- **Weather:** the menu bar temperature now has the sky's symbol next to it, and the panel can show a humidity and
  wind row (Settings → Weather).
- **Two accounts of one AI:** a second Claude, ChatGPT or Gemini account gets its own block in the panel with its
  nickname (or e-mail) next to the name. Add one in Settings → AI Limits → Accounts (give it a nickname, sign in in
  the Terminal that opens), or Nabız finds it in `~/.claude-*`, `~/.codex-*` and `~/.gemini-*` folders. An account
  signed in twice is shown once; each can be turned off, and an expired sign-in has a one-tap "Sign in…".

## 1.10.0

- **Weather** (Settings → Weather): your city's weather in the panel — now with how it feels, rain on the way, the
  next sunrise or sunset and the coming four days — with no location permission (the city comes from your time zone
  until you pick another; only its coordinates go to Open-Meteo). The temperature can sit in the menu bar, `hava` /
  `weather` answers in the launcher, and every row opens the Weather app. Celsius unless your Mac says otherwise.
- Sections added in a new version now appear in their natural place in the panel, even if you reordered it.
- **Safer developer clean-up:** build folders inside projects lose only their Build, Logs and cache folders, never
  the folder itself; nothing is cleaned while Xcode or a build runs; worktrees are only agents' ones, keep any
  ignored file that doesn't rebuild itself (.env, a local database), and are checked again right before removal, as
  are merged branches; node_modules stay for projects with uncommitted changes or a running server; Docker volumes are
  listed and removed by name; unavailable simulators are no longer removed unattended. Anything that changed since the
  scan is left alone, and the message says so.
- **MCP and AI hardening:** a bad `recording_list` request can no longer crash Nabız; exports go only into Desktop,
  Movies, Downloads or Documents and never replace a file; recordings can't be pointed at an image elsewhere on disk;
  turning MCP off and on quickly keeps its socket. Codex runs without its browser, computer-use, plugins and
  sub-agents; every AI is told that pasted or attached text is material, not instructions; Grok's prompt file is
  private and swept after a crash; a stuck CLI is stopped for sure; Gemini's Turkish letters no longer break across
  reads.
- **License:** Nabız is now source-available, not open source. The app stays free to use; the code may be read
  but not copied, reused, built or redistributed without written permission (see LICENSE).

## 1.9.0

- **Made for developers** (Settings → Developer):
  - **Ports:** type `:3000` (or `port 3000`) in the launcher to see who holds it — your server with its project, Docker,
    AirPlay Receiver explained — and stop it or open it; `port` lists every listening port. Typing a port number
    finds the dev server that holds it.
  - **Open a dev server on your phone:** the phone button on a dev server shows a QR code of its network address, and
    says when the server only listens on this Mac (with the flag that opens it: `--host`, `-H 0.0.0.0`…).
  - **Projects** in the panel and the launcher: every git repository in ~/Developer with its branch, changes and
    unpushed commits. Open it in Cursor / VS Code / Xcode or Terminal, start Claude Code (or Codex) there, run its
    package.json scripts (`dev` reuses a server that's already running), open GitHub or its pull requests. Projects
    take shortcuts and aliases like any launcher row. A suggestion when commits sit unpushed for a day.
  - **Docker** in the panel: one row per compose project with its ports; start, stop, restart, logs, a shell, and
    projects started from a folder that no longer exists are marked.
  - **Developer clean-up:** finished agent worktrees, Xcode build folders inside projects, extra iOS runtimes,
    DerivedData, Xcode Previews, never-used simulators, node_modules of idle projects, the pnpm store, npm and
    Homebrew caches, old Playwright browsers, unused Docker volumes, Claude history of deleted projects and merged
    branches — each with its size, cleaned after asking. Worktrees with changes or in use, unmerged branches and
    your code are never touched. The safe ones can run weekly from Schedules; a suggestion past 20 GB.
  - **Simulators:** a menu on each booted simulator for a 9:41 status bar, dark/light mode, opening the copied link,
    a screenshot into the markup editor, recording, and per app a test push, its data folder and resetting its
    permissions. A suggestion when three or more run at once.
  - **Launcher answers:** decode a JWT (never sent to AI or the web), Unix time ↔ date (`now`), `sha256 …` / `md5 …`,
    `uuid` / `ulid` / `nanoid`, `case …` (camelCase, snake_case…), colours as HEX / RGB / HSL / SwiftUI / UIKit /
    Compose, cron explained, `http 429`, `base64 …`, `url …`, `brew` (upgrade, outdated, cleanup in Terminal).
    Copied JWTs, Unix times and names get matching changes in ⌘K.
  - **Notarization:** while `notarytool submit` runs it shows in the panel, and Apple's answer arrives as a
    notification — no polling of Apple in between.
  - **MCP:** `port_info`, `projects` and `docker_containers`, so AI apps pick a free port and reuse what runs.
- **Dev servers in the panel:** every server you started from a project (vite, next, wrangler, `python -m
  http.server`…) shows with its project, ports and how long it has run; hover to open it in the browser, reveal its
  folder or stop it (with the `pnpm dev` wrapper that only ran it). A project running two servers is marked, since
  one is usually forgotten. The launcher can stop them by name, and AI apps get `dev_servers` and `stop_dev_server`
  over MCP, so they can reuse a running server instead of starting a second one.
- **Hide crowded menu bar icons** (Settings → Menu Bar, off until turned on): an arrow and a thin line sit left of
  Nabız; ⌘-drag the icons you don't need left of the line and the arrow folds them away, bringing them back with a
  click and hiding them again after a few seconds.
- **External display brightness:** a Displays section in the panel with a slider for each display (DDC/CI for
  other brands, the system's own for Apple displays), and optionally the keyboard's brightness keys work on the
  external display under the pointer, with an on-screen level (Settings → Shortcuts).
- **Screen recording, Screen Studio style** (⌃⌥R, Settings → Screenshots & Recording): a bar to record the whole
  screen, a window or an area, with the Mac's sound and (macOS 15) the microphone; 3-2-1 countdown, a red dot and the
  time in the menu bar to stop. The pointer is recorded apart from the picture, so the editor draws it smooth and
  larger, rings each click, and zooms in where you clicked, following the pointer with soft springs. Gradient
  background, padding, rounded corners and shadow; drag zooms on the timeline, stretch or add them, trim the start
  and end. Export MP4 (full size, 4K, 1080p) or GIF, or copy a 1080p MP4 straight to the clipboard.
  Also: the camera in a circle or rounded square in any corner (with a live bubble while recording), shortcuts
  pressed shown as a label (never what you type), 16:9 / 9:16 / 1:1 / 4:3 frames, faster parts on the timeline and
  one-click "speed up typing", the pointer fading out when still, and motion blur on fast moves.
  Motion now feels like Screen Studio: a stiffer spring that lands exactly on each click, a press-and-rebound
  click, zooms that arrive as you click and chain into pans, zooms planned in shots. The bar picks the screen, a
  window or an area live like ⌘⇧5. In the editor: cuts, a fixed focus point per zoom, a click sound, solid colour,
  macOS wallpaper or your own picture behind (with blur), the camera in eight spots with any roundness and mirror,
  a waveform and snapping on the timeline, captions transcribed on this Mac (edit a line, or cut those words out),
  and notes with arrows that stay on what they point at.
- **Settings, easier to search:** search now finds single settings, not just pages — in Turkish or English, without
  accents ("karanlik"), by word starts and with a typo forgiven. Results list the pages, then each setting with its
  page; ↑↓ walk them and the page scrolls to the setting and lights it up. Busy pages are split into smaller ones:
  **Shortcuts**, **Backup & Upkeep**, **Screenshots** and **Extensions** have their own pages, and AI is split into
  **Ask AI**, **Chat**, **Dictation** and **AI Limits**. The sidebar gains a **Menu Bar & Panel** group.
- **Easier to find:** the panel's AI section opens the chat (⌃⌥I, its own new shortcut) and quick questions, and an
  **AI chat** tile leads the tools. The menu bar item's right-click menu adds AI chat, Ask AI, Screenshot and Dictate
  with their keys. Settings has its own **AI** group (AI and MCP); AI commands and dictation moved to the AI page.
  In the launcher a question goes to AI first and Web second. Help and the welcome window show AI chat and
  screenshots, and the panel says once what's new in this version.
- **Screenshots with markup** (⌃⌥S, Settings → Screenshots): after a capture a thumbnail slides in at the lower-left —
  copy, save, pin, drag it out as a file, or click to mark it up. The editor has arrows (tapered, line, both ends),
  lines, boxes, ellipses, pen, highlighter, text (outlined or on a label), numbered steps, blur / pixelate,
  spotlight and crop; every mark stays movable and editable, with undo, one-key tools (A, R, T, N…), 1–8 for
  colours and [ ] for size. A frame option adds a gradient background, padding, rounded corners and a shadow.
  Copy text from the image (⇧⌘C), pin it over every app, share it, or mark up the copied image or any file from the
  launcher.
- **MCP server** (Settings → MCP, off until turned on): Claude Code, Claude Desktop, Cursor and other AI apps can use
  Nabız through `Nabiz --mcp`: this Mac's status and busiest apps, AI limits, calendar, maths and conversions, markets,
  rates, notifications, opening apps, window layouts, volume, timers, focus mode, your notes and snippets, and (only
  if you allow it) the clipboard history. One-click "Add to Claude Code / Claude Desktop". It listens on a socket only
  your user can open; restart, shut down and the like are never run.
- **Calendar** (Settings → Calendar): today's meetings in the panel, a heads-up a minute before, one click to join
  Zoom / Meet / Teams / Webex / FaceTime calls; `calendar` and "Join: …" in the launcher.
- **Your own window layouts** (Settings → Windows): any share of the screen, for the front window or a chosen app,
  and sets applied together ("Set: Code"); each is a launcher command you can give a shortcut.
- **Your own AI commands** (Settings → Launcher): a name and a prompt, run on the selected or copied text from the
  launcher or ⌘K. **Translate** with `çevir …` / `translate …` (Turkish ↔ English, by the text's language).
- **Dictation** (Settings → General, ⌃⌥D): speak, press again, and the words are typed where the cursor is;
  on-device when macOS has the language.
- **Backup** (Settings → General): one file with settings, snippets, quicklinks, shortcuts, layouts, AI commands,
  schedules and notes, to load on another Mac; optionally a daily copy in iCloud Drive.
- **AI chat with your own subscriptions:** Claude, Codex, Grok and Gemini through their CLIs on this Mac, or Apple's
  free on-device model (the default). Each provider's own models, defaults and thinking levels (Claude Low…Max, Codex
  per model, Grok Low…Extra); real logos where the provider's app is installed; Apple Intelligence's edge light.
  Sidebar with pinned chats, folders (drag chats in), grouping by date or AI, archive, rename, unread dots and search
  that shows where it matched; one aligned top bar (also in Settings). A chat window like the apps (history, Markdown, code blocks with copy, tables, model and thinking
  pickers, write again with another AI), quick questions in the launcher (`?` or ⌃⌥A) and ready-made tasks for selected
  or copied text. Each AI keeps its own look while it thinks; chats are kept encrypted.
  A question rail in place of the scroll bar (hover for the list, ⌥⌘↑/↓), find in chat (⌘F), images (Claude and
  Codex see them; the others get the text read from them on this Mac), screenshots, PDFs, a draft per chat, edits
  you can cancel, sending while it writes, ⇧⌘C copy the last answer, ⇧⌘⌫ delete the chat. Chats are saved while
  answers come in and on quit; a cut-off answer says so.
  Claude remembers each chat itself, so only your new message goes out (faster, lighter on your limit; it can be
  turned off). A ring by the model shows how full the chat is; a banner warns when the plan's limit is close or used
  up, with another AI one click away, and the model menu shows the plan's limits. Messages sent while it writes wait
  in a queue (send now, edit, remove); "New chat from here" branches from any answer; a notification when an
  answer arrives while you're elsewhere; a live timer while it works, times on messages, a mark on chats that
  failed, ⌘1…9 to switch chats.
  Side chats (⌥⌘S) ask on the side with the main chat as background and can add an answer back; quote what you
  selected (⇧⌘' or the quote button); a grey next-message suggestion from Apple's on-device model (⇥ takes it);
  "Summarize and continue" squeezes a long chat into a summary that goes in place of the old messages.
  Claude, Codex and Grok can search the web when a question needs current facts, with sources (+ → Web search to
  turn it off; nothing else is allowed, no files or commands). ⌘K jumps to the chat search.
- **Show in Dock** (Settings → General, off until turned on): Nabız also sits in the Dock and ⌘⇥ with its own
  menus (About, Settings, Hide, Quit, Edit, Window). Clicking the icon opens the panel; right-clicking lists the
  quick actions. Focus mode and "Hide others" never hide Nabız's own windows.
- **New tools in the panel:** Record and Dictate sit in the main grid; Clean-up (with how much it can free) opens
  the developer clean-up. The AI chat tile mentions Grok and web search.
- **Your own shortcut or alias for any app or command:** in the launcher press ⌘K on a row → "Set a shortcut…"
  (works from any app, e.g. ⌥S for Safari) or "Set an alias…" (type "ss" and that row comes first). Listed and
  removable in Settings → Launcher.
- **Sound:** mute, volume up/down, `ses 40` / `volume 40`, switch the sound output (speakers, AirPods, a display) and
  connect or disconnect paired Bluetooth devices (`bluetooth`, `airpods`) from the launcher.
- **Focus mode blocks websites** (opt-in, Settings → Focus): in Safari, Chrome, Arc, Brave, Edge and Vivaldi, with no
  extension, a blocked site in the front tab turns into a short "You're focusing" page until focus ends.
- **What can it do?** rebuilt: a fixed header (nothing scrolls under the window buttons any more), four tabs (Start,
  Launcher, Tools, Shortcuts) and search across all of it. Feature cards open what they describe, launcher examples
  open the launcher with that text and show their answer on hover, keys are drawn as keycaps.
- **Price alerts:** pick a market and a price; up or down follows from the price itself. Quick targets (±2, 5, 10%),
  how far each alert still is, when it fired, and **repeating** alerts that arm themselves again once the price
  moves 0.5% back.
- Notes: no more empty strip above the header; the header sits in the title bar and drags the window.
- **Apple Notes** option (Settings → General): the notes shortcut, the Notes tool, "New note" and "Save as note"
  open Apple Notes instead.

## 1.8.0

- **Clearer:** every tool confirms what it did in the menu bar ("Desktop icons hidden", "Strong password copied",
  "Focus on · 3 apps hidden"…) and explains itself on hover. The grid starts with the nine everyday tools; the rest
  sit behind **More tools**. A new **What can it do?** window lists the shortcuts, launcher examples you can click to
  try, and every tool (panel footer "?", the menu bar item's menu, Settings).
- **Launcher:** files from Spotlight's index (in searches, or only files with `/`), with Quick Look, copy, copy path
  and Move to Trash in ⌘K; your **Shortcuts** and your own **scripts** as commands (a scripts folder, Raycast-style
  `# @nabiz.title` headers, output copied); **emoji** with `:` in English or Turkish (`:kalp`, `:ates`).
- **Your own shortcuts:** record new keys for the launcher, clipboard, notes and panel in Settings → General.
- **Lighter and safer:** clipboard pictures moved out of memory into their own files; the whole clipboard history is
  encrypted on disk (AES-GCM, key in your Keychain); smaller cached icons; the launcher and notes free their views
  when closed; app search looks up running apps once per keystroke instead of once per app. About 70 MB in use.
- **Crash reports** are kept on this Mac (MetricKit) and can be sent as a GitHub issue from Settings → About.

## 1.7.1

- Tool choices (timer, keep awake, Pomodoro, focus, screenshot, sleep) open right under the tile you tapped.
- **Sleep timer** tool: put the Mac to sleep in 15, 30, 60 or 90 minutes; the tile shows when.

## 1.7.0

- **Calculator, much stronger** (in the launcher; start with `=` for the calculator alone and its history):
  functions (`sqrt`, `√`, `sin`/`cos`/`tan` in degrees, `log`, `ln`, `abs`, `round`…), `pi`, `e`, `5!`, `17 mod 5`,
  `20% of 150`, `2pi`, `3(4+1)`, `ans`; Turkish amounts (`5 bin tl`, `2,5 milyon`); crypto from Hyperliquid
  (`0.5 btc`, `1000 tl eth`); speed, area (dönüm, hectare, acre), volume and energy units; hex/binary/octal
  (`255 hex`, `0xff`); world clock (`tokyo`, `15:00 istanbul to new york`, `9am pst to tsi`); dates
  (`today + 30 days`, `bugün + 3 hafta`, `days until 2027-01-01`, `1.1.2027 ye kaç gün`). Several answers at once
  (other currencies and units), and ⌘K to copy the raw number or the whole sum.
- **Pomodoro:** 25/5 with a long break every fourth block (all adjustable), countdown in the menu bar, sound and
  notification at each change, today's count. From Tools, the launcher or the menu bar item's menu.
- **Focus mode:** hides Slack, Discord, Telegram, WhatsApp, Messages, Teams, Mail (your list) and hides them again if
  they come forward; optionally other apps and desktop icons; can switch macOS Focus through your Shortcuts.
  Pomodoro work blocks can turn it on by themselves.
- **Video download:** paste a YouTube, X, Instagram, TikTok, Vimeo… link into the launcher (or tap the tool with
  it copied) to save the video (best, 1080p or 720p) or only the sound, with progress and a notification.
  Uses yt-dlp; Nabız offers to install it with Homebrew.
- **Screenshots through macOS's own tool:** area, window or whole screen to the clipboard or a file (the system's
  save folder and file type), a 5-second timer, and the recording toolbar (⇧⌘5).
- **Read text or QR on screen** (Vision, Turkish and English), **QR codes** from copied text, **mute the mic**,
  and a **sleep timer** ("sleep in 30 min").

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
