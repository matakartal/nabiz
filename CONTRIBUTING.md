# Contributing

Thanks for helping. Nabız stays small, native and calm. A good change does one thing well and fits the panel's grid.

## Getting started

```bash
git clone https://github.com/matakartal/nabiz.git
cd nabiz
./build.sh install
```

You need macOS 14 or later and Xcode 16 or later. There are no dependencies to install.

## How the code is laid out

- `Monitor/` reads the Mac: CPU, memory, GPU, processes, network, battery, simulators.
- `Tools/` holds features that are not about the Mac itself: calculator, rates, markets, AI limits, the tool grid.
- `Views/` holds the panel, Settings, calculator and welcome window.
- `DesignSystem/Theme.swift` defines every colour, size and spacing. Use its tokens instead of numbers.

## Conventions

- **Language:** every string the user sees is written in both languages: `L("Türkçe", "English")`.
- **Grid:** rows follow the menu grid. Icons sit 16 pt in, text 40 pt in, and values end 16 pt from the edge. `PanelRow`, `SectionHeader` and `TwoColumns` already do this.
- **Accent colours:** use the accent for one thing at a time. Orange means "running low"; red means danger and nothing else.
- **Fixes:** a suggestion should fix the problem in one tap, not send the user to another app.
- **Network:** only on purpose. Say in the PR what is requested, from where, and whether anything about the user is sent.

## Checking your change

```bash
./build.sh
build/Nabiz.app/Contents/MacOS/Nabiz --snapshot panel.png --dark     # renders the panel with live data
build/Nabiz.app/Contents/MacOS/Nabiz --calc "5 km mi"                 # prints the calculator's answer
```

Add `-language en` or `-language tr` to a snapshot to check the other language.
