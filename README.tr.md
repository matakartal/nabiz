<div align="center">

<img src="Resources/AppIcon-1024.png" width="112" alt="Nabız simgesi">

# Nabız

**Her geliştiricinin Mac'inde olması gereken menü çubuğu uygulaması — vibecoder'lar için de en kullanışlısı.**

macOS için küçük, yerel ve açık kaynak bir menü çubuğu uygulaması: tek tuşla çözüm sunan sistem izleyici, kendi
aboneliklerinle ya da Apple'ın ücretsiz cihaz içi modeliyle AI sohbeti, başlatıcı, ekran görüntüsü ve ekran kaydı, hava
durumu, geliştirici araçları.

<a href="../../releases/latest"><img src="https://img.shields.io/badge/%C4%B0ndir-Nab%C4%B1z%201.10.0-1DB954?style=for-the-badge&logo=apple&logoColor=white" alt="Nabız'ı indir"></a>

[English](README.md) · [简体中文](README.zh-CN.md) · [X'te takip et: @mehmetatakartal](https://x.com/mehmetatakartal)

<br>

<img src="docs/hero.jpg" alt="Nabız: menü çubuğu, panel, AI sohbet penceresi ve başlatıcı">

</div>

## AI ile üretenler için

Sen yazıyorsun, ajanlar kuruyor, Mac'in sessizce doluyor. Nabız bu çalışma şekline ayak uydurur:

- **Unutulan sunucular ve port çakışmaları:** ajanların açtığı her sunucu projesi ve portuyla; tek tıkla durdur ya da
  `:3000` yazıp portu kimin tuttuğunu gör. Claude Code ve Cursor da **MCP** ile sorar, ikinci sunucu açmaz.
- **AI limitlerin bitmeden:** Claude, Codex ve Gemini limitleri menü çubuğunda; hızlı biterken uyarı.
- **Ajanların bıraktığı dağınıklık:** bitmiş worktree'ler, build klasörleri, eski `node_modules`, fazla simülatörler —
  boyutlarıyla listelenir, sorulmadan silinmez.
- **Yayınla ve göster:** notarize bitince bildirim, oklu ekran görüntüleri ve yakınlaşan, paylaşmaya hazır ekran
  kayıtları.

## Neler var

- **Panel:** menü çubuğunda CPU, RAM, GPU, ağ, disk, pil, AI limiti, piyasa ya da döviz. Canlı grafikler. Bellek
  dolunca neyin doldurduğunu söyler ve en çok yer açan adımı tek tuşla yapar. Geçmiş, harici ekran parlaklığı,
  takvim, Hyperliquid piyasaları ve döviz kurları da burada. İstersen Dock'ta da görünür.
- **Hava durumu:** şehrinde şu an, yaklaşan yağmur, gün doğumu/batımı ve önümüzdeki günler. Konum izni istemez;
  sıcaklık istersen menü çubuğunda da durur.
- **Cihaz içi AI:** varsayılan olarak Apple'ın modeli çalışır: ücretsiz, hesap istemez, hiçbir şey Mac'ten çıkmaz,
  internetsiz de çalışır (Apple Intelligence, macOS 26). Sohbetlere ad verir ve sıradaki mesajını önerir.
- **AI sohbet (⌃⌥I):** istersen Claude, Codex, Grok ya da Gemini'ye kendi aboneliğinle geç. Claude, Codex ve Grok
  gerekince web'de arar ve kaynak gösterir. Sabitlenmiş sohbetler, klasörler, arama (⌘K), görsel ve PDF, yan sohbet,
  alıntı, dallanma. Sohbetler şifreli saklanır. Hızlı soru (⌃⌥A), dikte (⌃⌥D) ve AI limitleri.
- **Ekran görüntüsü (⌃⌥S):** ok, kutu, yazı, numara, bulanıklaştırma, kırpma ve renkli çerçeve.
- **Ekran kaydı (⌃⌥R):** imleci yumuşatan, tıkladığın yere yakınlaşan, altyazıyı Mac'te çıkaran editör; 4K'ya kadar
  MP4 ya da GIF.
- **Başlatıcı (⌃⌥Boşluk):** uygulama, dosya, komut, hesap ve çeviri (`100 usd`, `5 bin tl`), parçacıklar, pano
  geçmişi (⌃⌥V), ses ve Bluetooth, her satıra kendi kısayolun.
- **Geliştiriciler için:** portlar (`:3000`), çalışan sunucular (telefonda QR ile aç), projeler ve gönderilmemiş
  commit'ler, Docker, simülatörler, sorarak yapılan temizlik, notarize takibi ve MCP sunucusu.
- **Günlük araçlar:** Pomodoro ve odak modu, uyanık kal, zamanlayıcı, notlar (⌃⌥M), pencere düzenleri, renk al,
  ekrandan metin oku, hız testi, şifre üret, zamanlanmış görevler ve yedek.

<p align="center">
  <img src="docs/panel.png" width="300" alt="Panel">
  &nbsp;
  <img src="docs/tools.png" width="300" alt="Araçlar">
</p>

## Kurulum

```bash
brew tap matakartal/nabiz https://github.com/matakartal/nabiz && brew install --cask matakartal/nabiz/nabiz
```

Ya da:

1. [Releases](../../releases/latest) sayfasından `Nabiz-x.y.z.dmg` dosyasını indir.
2. Aç ve Nabız'ı Programlar klasörüne sürükle.
3. Nabız'ı aç; kısa bir karşılama ekranı her şeyin yerini gösterir.

Sürümler imzalı ve Apple onaylıdır, uyarısız açılır. Yeni sürüm çıkınca panelde **Güncelle** düğmesi belirir.
macOS 14 veya üstü gerekir; Apple Silicon ve Intel'de çalışır.

## Gizlilik

Mac'inle ilgili her şey Mac'in içinde ölçülür; analitik ve hesap yoktur. İnternete yalnızca şunlar için çıkar:
döviz kurları, Hyperliquid fiyatları, hava durumu (yalnızca şehrin koordinatları), güncelleme kontrolü, açtığın AI sağlayıcılarının kendi sunucuları ve senin
istediğin işler (web araması, video indirme, hız testi). Apple'ın cihaz içi modeli Mac'ten hiç çıkmaz. Pano geçmişi
ve AI sohbetleri diskte şifrelidir.

## Geliştiren

**Mehmet Ata Kartal** — güncellemeler için [X'te @mehmetatakartal](https://x.com/mehmetatakartal).

Nabız ücretsiz. Kripto alım satımı yapıyorsan [Bybit'e referans bağlantımla](https://www.bybit.com/register?affiliate_id=971&group_id=971&group_type=1) kaydolarak gelişimine destek olabilirsin
(referans bağlantısıdır; sana ek bir maliyeti yoktur).

## Lisans

Nabız [GNU GPL v3 veya sonrası](LICENSE) lisanslı özgür yazılımdır: kullan, incele, değiştir, paylaş — ondan türeyip
dağıtılan her şey de GPL ile açık kalır. Ad ve simge lisansa dahil değildir; fork'lar kendi adını ve simgesini kullanır
([TRADEMARK.md](TRADEMARK.md)).

© 2026 Mehmet Ata Kartal.
