// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit

/// System Settings pages the launcher can open straight away ("wifi", "ekranlar", "privacy"), in both languages.
/// They open by their extension's id through the x-apple.systempreferences: address macOS itself uses.
struct SystemPane: Identifiable, Sendable {
    let id: String
    let tr: String
    let en: String
    /// Other words people type for it, in either language.
    let words: String

    var title: String { L(tr, en) }
    var url: URL? { URL(string: "x-apple.systempreferences:\(id)") }
    /// Both names and the extra words, for matching whatever language is typed.
    var keywords: String { "\(tr) \(en) \(words)" }

    func open() {
        if let url { NSWorkspace.shared.open(url) }
    }

    static let all: [SystemPane] = [
        SystemPane(id: "com.apple.wifi-settings-extension", tr: "Wi-Fi", en: "Wi-Fi", words: "wifi kablosuz wireless internet"),
        SystemPane(id: "com.apple.Network-Settings.extension", tr: "Ağ", en: "Network", words: "ethernet internet ip dns"),
        SystemPane(id: "com.apple.BluetoothSettings", tr: "Bluetooth", en: "Bluetooth", words: "bt kulaklık headphones"),
        SystemPane(id: "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", tr: "VPN", en: "VPN", words: "vpn"),
        SystemPane(id: "com.apple.Displays-Settings.extension", tr: "Ekranlar", en: "Displays", words: "monitor ekran çözünürlük resolution night shift parlaklık brightness"),
        SystemPane(id: "com.apple.Sound-Settings.extension", tr: "Ses", en: "Sound", words: "hoparlör speaker mikrofon microphone volume çıkış output"),
        SystemPane(id: "com.apple.Battery-Settings.extension", tr: "Pil", en: "Battery", words: "enerji energy power şarj charge"),
        SystemPane(id: "com.apple.Notifications-Settings.extension", tr: "Bildirimler", en: "Notifications", words: "uyarı alert"),
        SystemPane(id: "com.apple.Focus-Settings.extension", tr: "Odak", en: "Focus", words: "rahatsız etmeyin do not disturb dnd"),
        SystemPane(id: "com.apple.Screen-Time-Settings.extension", tr: "Ekran Süresi", en: "Screen Time", words: "süre limit"),
        SystemPane(id: "com.apple.systempreferences.GeneralSettings", tr: "Genel", en: "General", words: "general"),
        SystemPane(id: "com.apple.Appearance-Settings.extension", tr: "Görünüş", en: "Appearance", words: "karanlık koyu dark light açık tema theme vurgu accent"),
        SystemPane(id: "com.apple.Accessibility-Settings.extension", tr: "Erişilebilirlik", en: "Accessibility", words: "voiceover zoom büyüt"),
        SystemPane(id: "com.apple.ControlCenter-Settings.extension", tr: "Denetim Merkezi", en: "Control Centre", words: "control center menü çubuğu menu bar"),
        SystemPane(id: "com.apple.Siri-Settings.extension", tr: "Siri", en: "Siri", words: "apple intelligence"),
        SystemPane(id: "com.apple.Spotlight-Settings.extension", tr: "Spotlight", en: "Spotlight", words: "arama search"),
        SystemPane(id: "com.apple.settings.PrivacySecurity.extension", tr: "Gizlilik ve Güvenlik", en: "Privacy & Security", words: "privacy gizlilik security güvenlik izin permission filevault"),
        SystemPane(id: "com.apple.Desktop-Settings.extension", tr: "Masaüstü ve Dock", en: "Desktop & Dock", words: "dock stage manager sahne yöneticisi mission control"),
        SystemPane(id: "com.apple.Wallpaper-Settings.extension", tr: "Duvar Kâğıdı", en: "Wallpaper", words: "duvar kagidi arka plan background"),
        SystemPane(id: "com.apple.Lock-Screen-Settings.extension", tr: "Kilit Ekranı", en: "Lock Screen", words: "ekran koruyucu screen saver uyku sleep"),
        SystemPane(id: "com.apple.Touch-ID-Settings.extension", tr: "Touch ID ve Parola", en: "Touch ID & Password", words: "parmak izi fingerprint şifre password"),
        SystemPane(id: "com.apple.Users-Groups-Settings.extension", tr: "Kullanıcılar ve Gruplar", en: "Users & Groups", words: "kullanıcı user hesap account"),
        SystemPane(id: "com.apple.Internet-Accounts-Settings.extension", tr: "İnternet Hesapları", en: "Internet Accounts", words: "mail e-posta email google"),
        SystemPane(id: "com.apple.systempreferences.AppleIDSettings", tr: "Apple Hesabı", en: "Apple Account", words: "icloud apple id"),
        SystemPane(id: "com.apple.Family-Settings.extension", tr: "Aile", en: "Family", words: "family"),
        SystemPane(id: "com.apple.WalletSettingsExtension", tr: "Cüzdan ve Apple Pay", en: "Wallet & Apple Pay", words: "cüzdan wallet"),
        SystemPane(id: "com.apple.Keyboard-Settings.extension", tr: "Klavye", en: "Keyboard", words: "kısayol shortcut dikte dictation"),
        SystemPane(id: "com.apple.Mouse-Settings.extension", tr: "Fare", en: "Mouse", words: "mouse"),
        SystemPane(id: "com.apple.Trackpad-Settings.extension", tr: "İzleme Dörtgeni", en: "Trackpad", words: "trackpad dokunmatik"),
        SystemPane(id: "com.apple.Print-Scan-Settings.extension", tr: "Yazıcılar ve Tarayıcılar", en: "Printers & Scanners", words: "yazıcı printer tarayıcı scanner"),
        SystemPane(id: "com.apple.Software-Update-Settings.extension", tr: "Yazılım Güncelleme", en: "Software Update", words: "güncelle update macos"),
        SystemPane(id: "com.apple.settings.Storage", tr: "Depolama", en: "Storage", words: "disk alan space"),
        SystemPane(id: "com.apple.Date-Time-Settings.extension", tr: "Tarih ve Saat", en: "Date & Time", words: "saat dilimi time zone"),
        SystemPane(id: "com.apple.Localization-Settings.extension", tr: "Dil ve Bölge", en: "Language & Region", words: "dil language bölge region"),
        SystemPane(id: "com.apple.Sharing-Settings.extension", tr: "Paylaşma", en: "Sharing", words: "paylaşım airplay dosya file screen sharing ekran paylaşma"),
        SystemPane(id: "com.apple.AirDrop-Handoff-Settings.extension", tr: "AirDrop ve Handoff", en: "AirDrop & Handoff", words: "airdrop handoff"),
        SystemPane(id: "com.apple.LoginItems-Settings.extension", tr: "Giriş Öğeleri", en: "Login Items", words: "başlangıç startup açılış"),
        SystemPane(id: "com.apple.Time-Machine-Settings.extension", tr: "Time Machine", en: "Time Machine", words: "yedek backup"),
        SystemPane(id: "com.apple.Startup-Disk-Settings.extension", tr: "Başlangıç Diski", en: "Startup Disk", words: "startup disk"),
        SystemPane(id: "com.apple.Transfer-Reset-Settings.extension", tr: "Aktar veya Sıfırla", en: "Transfer or Reset", words: "sıfırla reset sil erase"),
        SystemPane(id: "com.apple.Game-Center-Settings.extension", tr: "Game Center", en: "Game Center", words: "oyun game"),
        SystemPane(id: "com.apple.SystemProfiler.AboutExtension", tr: "Hakkında", en: "About", words: "about this mac bu mac sürüm version seri serial"),
        // Privacy pages people are sent to most often.
        SystemPane(id: "com.apple.preference.security?Privacy_Accessibility", tr: "Gizlilik: Erişilebilirlik", en: "Privacy: Accessibility",
                   words: "izin permission"),
        SystemPane(id: "com.apple.preference.security?Privacy_ScreenCapture", tr: "Gizlilik: Ekran Kaydı", en: "Privacy: Screen Recording",
                   words: "izin permission ekran kaydı screen recording"),
        SystemPane(id: "com.apple.preference.security?Privacy_AllFiles", tr: "Gizlilik: Tam Disk Erişimi", en: "Privacy: Full Disk Access",
                   words: "izin permission disk"),
        SystemPane(id: "com.apple.preference.security?Privacy_Microphone", tr: "Gizlilik: Mikrofon", en: "Privacy: Microphone",
                   words: "izin permission mic"),
        SystemPane(id: "com.apple.preference.security?Privacy_Camera", tr: "Gizlilik: Kamera", en: "Privacy: Camera", words: "izin permission"),
        SystemPane(id: "com.apple.preference.security?Privacy_LocationServices", tr: "Gizlilik: Konum Servisleri", en: "Privacy: Location Services",
                   words: "izin permission konum location gps"),
    ]
}
