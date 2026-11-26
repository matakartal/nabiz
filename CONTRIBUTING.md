# Contributing

Thanks for helping. Nabız is open source under the [GPL v3 or later](LICENSE); the name and icon are kept apart
([TRADEMARK.md](TRADEMARK.md)).

## Ways to help

- **Report a bug or ask for a feature** with an issue. Include your macOS version, the Nabız version
  (Settings → About) and what you expected. Crash reports can be sent from Settings → About.
- **Report a security problem** privately, as [SECURITY.md](SECURITY.md) explains — never in a public issue.
- **Propose a change** with a pull request. By sending one you agree that it is your own work (or you may send it)
  and that it is licensed under the GPL v3 or later, like the rest of Nabız.

Open an issue before a large change, so we can agree on it before you spend time on it. Pull requests that don't
follow these rules are closed or sent back; that's not personal.

## What Nabız is (and isn't)

- **Small, native, calm.** One app in the menu bar that people forget is there until it helps. No feature that needs
  a server, an account or a subscription of ours.
- **Fixes, not just numbers.** A new reading earns its place by leading to something the user can do in one tap.
- **For non-technical people too.** Plain words, no jargon in the UI, safe defaults; developer features stay out of
  the way of people who don't need them.
- **Not wanted:** analytics or tracking, ads, telemetry, wallets, trading or moving money, anything that runs with
  administrator rights, kernel or system extensions, background downloads the user didn't ask for.

## Design

Every visible change follows [docs/DESIGN.md](docs/DESIGN.md): the menu grid, one-line rows, one accent, orange only
for running low, red only for danger, two type sizes, `Theme` tokens only, frosted by default. Include before/after
screenshots in light and dark mode.

## Code

- **Swift 6, SwiftUI + AppKit, macOS 14+.** No third-party dependencies: no Swift packages, no CocoaPods, no
  bundled binaries. Use what macOS ships.
- **Layout:** `Monitor/` reads the Mac, `Tools/` holds features, `Views/` the UI, `Support/` settings keys and helpers,
  `DesignSystem/Theme.swift` every colour, size and spacing. Put code where its neighbours are.
- **Threads:** UI and stores are `@MainActor` / `@Observable`. Blocking work (shell commands, disk walks, network)
  runs off the main thread (`Task.detached`, `nonisolated`), and nothing runs while the panel is closed unless the
  menu bar shows it.
- **Shell commands:** always `Shell.run` / `Process` with an argument array, never a shell string. Never put user
  text into a command's arguments.
- **Light on the Mac:** idle CPU stays near 0%. Poll only as often as the data changes; cache what can be cached.
- **No force unwraps or `try!`** on anything that comes from the system, a file, the network or a CLI. Parse
  defensively; a broken answer shows a message, never a crash.
- **Comments** say *why*, in plain sentences, above the code they explain. No commented-out code.
- **Copyright header:** every new source file starts with the same one-line header as the others.
- **Settings:** a new preference gets a key in `Prefs`, a default in `registerDefaults`, a control on its Settings
  page and an entry in `SettingsSearch.swift`. Off by default if it sends anything over the network or touches
  something outside Nabız.

## Words and languages

- Every user-facing string is written in both languages, side by side: `L("Türkçe", "English")`. Names and numbers
  use `Text(verbatim:)`. Check both with `-language tr` / `-language en`.
- Short, plain and friendly. Say what happens, not how it works. Sentence case. No exclamation marks.
- New features are listed in `CHANGELOG.md` under the next version, written for users.

## Privacy and safety

- **Nothing leaves the Mac without a reason the user can see.** Any new network request is named in the pull
  request (what, to where, what is sent), listed in the README's Privacy table, and opt-in unless it carries nothing
  about the user.
- No analytics, no identifiers, no logging of what people type, copy or say.
- Anything that deletes, quits or stops something asks first, names what it acts on, and checks again right before
  acting. Prefer the Trash to deleting. Never touch the user's code, uncommitted work, or files outside the folders
  a feature is about.
- Secrets stay where their owner keeps them (the Keychain, a CLI's own sign-in). Never store, log or forward them.
- AI features: pasted, copied or attached text is material, never instructions; AI CLIs get no file or command tools.

## Tests

- `swift test` passes, and new logic comes with tests: parsing, rules, anything that decides what to delete or
  show. UI is checked with snapshots instead (see docs/DESIGN.md).
- A bug fix includes a test that fails without the fix where that's possible.

## Commits and pull requests

- One topic per pull request, small enough to review in one sitting. Rebase on `main`; no merge commits.
- Commit messages: `feat: …`, `fix: …`, `docs: …`, `chore: …`, then a short plain sentence about the user-visible
  effect ("fix: the weather no longer asks the server every few seconds while offline").
- The pull request says what changes and why, how you checked it, and shows screenshots for anything visible.
- Releases, version numbers and signing are done by the maintainer.

## Checking your change

```bash
./build.sh                                   # builds without warnings
swift test                                   # all tests pass
python3 scripts/lint-ui.py <changed files>   # 0 design findings in code you touched
build/Nabiz.app/Contents/MacOS/Nabiz --snapshot panel.png --dark
```
