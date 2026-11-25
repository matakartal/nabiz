<p align="center"><img src="Resources/AppIcon-1024.png" width="128" alt="Nabız icon"></p>

<h1 align="center">Nabız</h1>

<p align="center">Your Mac's pulse in the menu bar. A small, native, open-source system monitor for macOS, with the tools you reach for every day.</p>

<p align="center"><img src="docs/menubar.png" width="131" alt="Nabız in the menu bar: CPU, RAM and Claude limit, two lines"></p>

<p align="center">
  <img src="docs/panel.png" width="320" alt="The panel: meters, system, suggestions with one-tap fixes, markets">
  &nbsp;
  <img src="docs/tools.png" width="320" alt="The panel with the tools grid open">
</p>

<p align="center"><img src="docs/launcher.png" width="620" alt="The launcher finding apps and commands for &quot;sa&quot;"></p>

<p align="center"><img src="docs/settings.png" width="760" alt="Settings: the Markets page with every Hyperliquid market"></p>

<p align="center"><i>Türkçe aşağıda.</i></p>

## Install

Download the latest `Nabiz-x.y.z.dmg` from [Releases](../../releases), open it and drag Nabız to Applications. The release builds are not notarized yet, so the first time you open Nabız, right-click it and choose **Open**. It needs macOS 14 or later and runs natively on Apple silicon and Intel.

On first launch, a short welcome explains where things are and offers to open Nabız at login.

## What it does

- **Menu bar:** the values you pick, either two lines (a small label over a bold value, like the system's own items) or a single line. You can show:
  - CPU, RAM, GPU
  - swap, network speed, free disk, battery
  - an AI limit
  - a market price
  - an exchange rate
- **Live meters:** CPU, RAM and GPU, each with a two-minute graph. Memory pressure, swap, disk, network and battery sit under them.
- **Suggestions with one-tap fixes:** when memory runs out, Nabız tells you what is using it and offers the single step that frees the most. That means shutting down the simulators or quitting the biggest app. Claude and Finder are never offered for quitting. Nabız also warns you when the disk is almost full, the battery is low or the Mac is hot.
- **Simulators:** shut down running iOS simulators one by one or all at once.
- **Top apps:** the apps using the most memory and CPU, grouped by app (helpers count toward their parent). Hover a row to quit the app or show it in Finder.
- **AI limits (opt-in):** Claude, ChatGPT/Codex and Gemini subscription windows, with time to reset:
  - 5-hour
  - weekly
  - per-model weekly
- **Markets (Hyperliquid):** live price and 24-hour change for any Hyperliquid perpetual:
  - about 180 crypto markets on the main dex,
  - the stocks, indices and commodities on every HIP-3 dex (XYZ, Paragon, EntropyIO…).

  Search, pick and order them in Settings. Click one to open it on Hyperliquid. No account or key needed.
- **History:** CPU, RAM, GPU and AI usage for the last hour, day or week. Click the meters to open it.
- **Price alerts:** get a notification when a Hyperliquid market crosses a price you set.
- **Docker and Android:** idle Docker gets a one-tap Quit, and Android emulators sit next to the iOS simulators.
- **Updates:** a new release shows an **Update** button that installs it and reopens Nabız.
- **Exchange rates:** your chosen currencies in your main currency, with the daily change. Click to copy.
- **Tools:** one-tap tiles:
  - calculator
  - keep awake
  - pick a colour
  - screenshot to clipboard
  - display off
  - dark mode
  - internet speed test
  - copy IP
  - password and UUID generators
  - eject disks
  - clean Xcode's DerivedData
  - show hidden files
  - hide desktop icons
  - clear clipboard
  - Activity Monitor
- **Launcher** (⌃⌥Space from anywhere): one field for everything, keyboard first (↑↓, ↩, ⌘↩ for the second action):
  - apps: type a few letters ("saf", "vsc"), ↩ opens, ⌘↩ quits a running one
  - commands: lock screen, sleep, display off, hide other apps, empty Trash, restart, shut down…
  - maths, currencies and units: `12*4`, `200 + %18`, `100 usd`, `250 € tl`, `5 km mi`, `2 gb mb`
  - timers: `25 dk` / `25 min`; keep awake for an hour or indefinitely
  - quicklinks: `g words` searches Google, `gh`, `yt`, `w`, `hl`, `cl`, `gpt`… (edit your own with `{query}`)
  - snippets: saved text with `{date}`, `{time}` and `{clipboard}`, pasted by keyword
  - recent items when the field is empty
- **Clipboard history** (⌃⌥V): text, links, colours, files and images, searchable, with a preview. Pin what you
  keep using. ↩ pastes straight into the app you were in (with Accessibility permission), ⌘↩ only copies. Password
  managers' secret copies and apps you exclude are never recorded; everything stays on your Mac.
- **Window layouts:** halves, thirds, centre, maximize, next display. Opt-in shortcuts ⌃⌥←→↑↓, ⌃⌥↩, ⌃⌥C.
- **Floating note:** a small note above every app and Space, saved as you type.
- **Personalization:** 17 accent colours plus the system accent and a colour of your own, light/dark/system theme,
  standard, rounded or monospaced type, compact/normal/roomy rows, thin or thick bars, frosted or opaque panel,
  panel width, menu bar icon, and the panel's section order.
- **Settings:** a sidebar of pages:
  - General: language (Türkçe / English / system), open at login, refresh rate, shortcut
  - Menu Bar
  - Appearance: colours, theme, typeface, density
  - Panel: sections and their order, folding, accordion mode, tools
  - Launcher, Clipboard, Snippets, Windows
  - Schedules
  - Markets
  - Currency
  - AI Limits

The panel uses the native menu material and the native menu grid: icons 16 pt in, text 40 pt in, values 16 pt from the edge. Sections fold, and a closed section shows a one-line summary. The panel opens without stealing focus and closes on Escape or a click outside. Idle, Nabız uses about 0–1% CPU and 70–100 MB of memory.

## Privacy

Everything about your Mac is measured locally, and Nabız has no analytics. It makes three kinds of network request:

- **Exchange rates:** the European Central Bank's daily reference rates from [frankfurter.dev](https://frankfurter.dev). No data about you is sent.
- **Market prices:** fetched from Hyperliquid's public info API (`api.hyperliquid.xyz`). No account and no data about you are involved.
- **AI limits:** these requests are made only for providers you turn on. Nabız calls that provider's own usage endpoint with the sign-in its official CLI already keeps on your Mac. It never stores, refreshes or forwards that sign-in. macOS asks before Nabız reads Claude Code's Keychain item.

Nabız reads only your own user's processes and never asks for administrator rights. Some tools trigger a macOS prompt once:

- Screenshot asks for screen recording.
- Dark mode asks for control of System Events.
- Pasting from the launcher and window layouts ask for Accessibility. Without it, items are only copied.

## Build

You need macOS 14 or later and Swift 6 (Xcode 16 or later).

```bash
./build.sh            # build/Nabiz.app, universal
./build.sh install    # also copies it to ~/Applications and opens it
./build.sh dmg        # also packages build/Nabiz-<version>.dmg
```

Run `swift test` for the unit tests. Builds are ad-hoc signed by default; `./release.sh publish` signs with your
Developer ID, notarizes and publishes the release in one go. To publish a build that opens without warnings on other Macs, sign it with a Developer ID and notarize it:

```bash
xcrun notarytool store-credentials nabiz        # once
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=nabiz ./build.sh dmg
```

The GitHub workflow builds the universal app and the DMG on every push and pull request, checks the calculator, and keeps the DMG as a build artifact.

To regenerate the app icon, run `swift scripts/make-icon.swift`.

There are two development helpers:

- `Nabiz --snapshot out.png [--dark] [--settings]` renders the panel or Settings with live data, for layout checks;
  `--launcher "100 usd"` (add `--clipboard` for the clipboard list) renders the launcher.
- `Nabiz --calc "5 km mi"` prints what the calculator would show.

## Project layout

| Path | What |
| --- | --- |
| `Sources/Nabiz/App.swift` | Status item, panel window, snapshot renderer |
| `Sources/Nabiz/Views/Panel.swift` | Panel sections and the menu-grid components |
| `Sources/Nabiz/Views/SettingsView.swift` | Settings window |
| `Sources/Nabiz/Views/CalculatorPanel.swift` | Spotlight-style calculator and its global shortcut |
| `Sources/Nabiz/Views/WelcomeWindow.swift` | First-launch welcome |
| `Sources/Nabiz/Monitor/` | CPU, memory, GPU, process, network, battery and simulator samplers |
| `Sources/Nabiz/Tools/` | Calculator, exchange rates, Hyperliquid markets, AI limits, tools |
| `Sources/Nabiz/Support/` | Settings keys, the `L("tr", "en")` helper, menu bar text |
| `Sources/Nabiz/DesignSystem/Theme.swift` | Colours, type, spacing, menu grid |

Every user-facing string is written in both languages, side by side: `L("Türkçe", "English")`.

## License

MIT. See [LICENSE](LICENSE).

---

## Türkçe

Nabız, Mac'inin nabzını menü çubuğunda tutan küçük, yerel (native) ve açık kaynak bir sistem izleyicisi. Her gün işine yarayacak araçlarla birlikte gelir.

**Kurulum:** [Releases](../../releases) sayfasından `Nabiz-x.y.z.dmg` dosyasını indir, aç ve Nabız'ı Programlar klasörüne sürükle. macOS 14 veya üstü gerekir; Apple Silicon ve Intel'de çalışır.

**Neler var:**

- **Menü çubuğu:** seçtiğin değerler iki satır ya da tek satır görünür:
  - CPU, RAM, GPU
  - takas alanı, ağ, disk, pil
  - AI limiti
  - piyasa fiyatı
  - döviz
- **Tek tuşla çözüm:** bellek dolunca neyin doldurduğunu söyler ve en çok yer açan adımı tek tuşla yapar.
- **AI limitleri (isteğe bağlı):** Claude, ChatGPT/Codex ve Gemini limitleri ile sıfırlanma süreleri.
- **Piyasalar (Hyperliquid):** ana borsadaki kripto piyasaları ve HIP-3 borsalarındaki hisse, endeks ve emtia piyasaları. Tıklayınca Hyperliquid'de açılır.
- **Araçlar:**
  - hesap makinesi (döviz ve birim çevirir)
  - uyanık kal
  - renk al
  - ekran görüntüsü
  - karanlık mod
  - hız testi
  - şifre üretici
  - disk çıkarma
  - Xcode temizliği
  - ve daha fazlası
- **Başlatıcı (⌃⌥Boşluk):** uygulama aç, komut çalıştır (kilitle, uyut, çöpü boşalt…), hesapla ve çevir (`100 usd`), `25 dk` zamanlayıcı, `g kelime` ile web araması, kısaltmayla parçacık yapıştır.
- **Pano geçmişi (⌃⌥V):** metin, bağlantı, renk, dosya ve görseller; ara, sabitle, ↩ ile doğrudan yapıştır. Şifre yöneticilerinin gizli kopyaları kaydedilmez; her şey Mac'te kalır.
- **Pencere yerleşimi:** yarım, üçte bir, ortala, ekranı kapla, sonraki ekran (isteğe bağlı ⌃⌥ ok tuşları).
- **Yüzen not:** her uygulamanın üstünde duran küçük not.
- **Kişiselleştirme:** 17 vurgu rengi + sistem rengi + kendi rengin, açık/koyu tema, yuvarlak ya da eşit aralıklı yazı, satır sıklığı, çubuk kalınlığı, menü çubuğu simgesi ve panel bölümlerinin sırası.
- **Ayarlar:** kenar çubuklu; Türkçe ve İngilizce.

**Gizlilik:** Mac'inle ilgili her şey Mac'in içinde ölçülür. Analitik yoktur. Dışarıya giden istekler yalnızca şunlardır:

- döviz kurları,
- Hyperliquid fiyatları,
- açtığın AI sağlayıcılarının kendi kullanım sunucuları.
