# ⚡ YTShortClipper

> **AI-Powered YouTube Short Clipper & Pre-Render Video Studio for Android**  
> *Otomatis potong video panjang menjadi konten viral YouTube Shorts, TikTok, dan Instagram Reels dengan Subtitle Kata-demi-Kata On-Device (100% Offline Tanpa Token & Tanpa API Key).*

🌐 **Website Resmi & Landing Page:** [https://rcs-webdev.github.io/YTShortClipper/](https://rcs-webdev.github.io/YTShortClipper/)

---

## 🌟 Fitur Unggulan

- 🎙️ **On-Device Neural Speech Recognizer (100% Offline):** Mengintegrasikan engine C++ inferensi neural network `sherpa_onnx` (arsitektur Whisper Tiny int8) langsung di HP. Menghasilkan kata demi kata dengan timing detik akurat tanpa memerlukan API key eksternal maupun token berbayar.
- ⚡ **AI Viral Highlight Detection:** Menganalisis densitas emosi kata kunci, tensi narasi, dan retensi audiens untuk mendeteksi klip terbaik.
- 🎯 **Dua Alur Klip:**
  - **Auto Klip AI:** Otomatis menghasilkan 3–10 klip dengan virality score, hook headline, dan ringkasan momen.
  - **Klip By Request:** Tentukan sendiri menit mulai dan selesai secara presisi.
- 🎬 **Pre-Render Studio Editor:**
  - **Style Tab:** Preset gaya subtitle (BEAST, Retro, Bold), pemilihan font Google Fonts (Anton, Bebas Neue, Montserrat, Poppins), dan rentang font minimal hingga 5px.
  - **Captions Tab:** Generator caption mandiri otomatis, edit kata/baris subtitle langsung, dan transisi teks (fade, wipe, zoom, slide).
  - **AI Tools Tab:** Dynamic auto punch-in zoom, deteksi hook, dan speech enhancer.
  - **Komposisi Tab:** Format vertikal 9:16 layar penuh, split screen, pengaturan watermark dinamis, dan Hook Headline Banner animasi.
- 📱 **Dukungan Dua Sumber Video:** Download otomatis dari link YouTube (termasuk transkrip closed-caption) atau unggah video langsung dari Galeri HP Anda.

---

## 📦 Download APK

File APK rilis terbaru dapat diunduh langsung dari halaman [GitHub Releases](https://github.com/Rcs-WebDev/YTShortClipper/releases).

---

## 🛠️ Cara Build APK Sendiri

Pastikan Flutter SDK dan Android NDK/SDK telah terpasang di sistem Anda.

```bash
# 1. Pindah ke direktori aplikasi mobile
cd mobile_app

# 2. Ambil seluruh dependencies
flutter pub get

# 3. Build Release APK
flutter build apk --release
```

Output APK akan berada di:  
`mobile_app/build/app/outputs/flutter-apk/app-release.apk`

---

## 📄 Lisensi

Proyek ini dilisensikan di bawah lisensi [MIT](LICENSE).
