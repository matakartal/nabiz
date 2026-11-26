# Contributing

Thanks for helping. Nabız is **source-available, not open source**: the code is public so you can see what the app
does, but it may not be copied, reused or redistributed (see [LICENSE](LICENSE)).

## Ways to help

- **Report a bug or ask for a feature** with an issue. Include your macOS version, the Nabız version
  (Settings → About) and what you expected to happen. Crash reports can be sent from Settings → About.
- **Report a security problem** privately, as [SECURITY.md](SECURITY.md) explains.
- **Propose a change** with a pull request. By sending one you agree to the Contributions section of the
  [LICENSE](LICENSE): you keep no rights in Nabız, and the copyright holder may use your change in any way.

## If you send code

- **One thing well.** Nabız stays small, native and calm; a change should fit the panel's grid and its look.
- **Both languages.** Every string the user sees is written as `L("Türkçe", "English")`.
- **Grid and colours.** Use the tokens in `DesignSystem/Theme.swift`. Icons sit 16 pt in, text 40 pt in, values end
  16 pt from the edge. Orange means "running low", red means danger and nothing else.
- **Fixes, not detours.** A suggestion fixes the problem in one tap instead of sending the user to another app.
- **Network only on purpose.** Say in the pull request what is requested, from where, and whether anything about the
  user is sent.
- **Tests pass.** Run `swift test`, and check the layout with
  `build/Nabiz.app/Contents/MacOS/Nabiz --snapshot panel.png --dark`.
