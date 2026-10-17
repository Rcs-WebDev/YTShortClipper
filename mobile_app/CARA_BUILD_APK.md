# PANDUAN LENGKAP: BUILD APK & PENGGUNAAN APLIKASI
## YT Short Clipper AI (Full Standalone Android APK)

Aplikasi ini adalah implementasi Flutter Android mandiri (**Full Standalone APK**) dari `YTShortClipperV2` yang dilengkapi **Pre-Render Studio Editor** (seperti pada platform AutoKlip di video YouTube Aji Prakoso).

---

### FITUR UTAMA DALAM APLIKASI:

1. **AI Highlight & Virality Scorer**:
   - Menganalisis video YouTube dan otomatis memotong bagian terbaik dengan skor viral (0 - 10).
   - Menampilkan alasan retensi dan hook pembuka.

2. **Studio Pre-Render Editor (Fitur Kunci Sebelum Render)**:
   - **Canvas Live 9:16**: Melihat preview langsung di layar HP sebelum rendering dimulai.
   - **Timeline Trimming**: Geser slider detik mulai dan detik selesai secara presisi.
   - **Layout Selector**:
     - *Blur Background*: Video landscape di tengah dengan latar belakang blur 9:16.
     - *Center Crop*: Menutupi layar 9:16 penuh dengan slider pan wajah.
     - *Split Screen*: 2 pembicara bertumpuk (Podcast mode).
   - **Subtitle Hormozi & Karaoke Highlight**:
     - Preset gaya Alex Hormozi (kuning emas, stroke hitam tebal), Neon Green, Retro Pop, dan Clean Minimal.
     - Animasi kata per kata menyala saat diucapkan.
     - **Modal Edit Teks Transkrip**: Bisa langsung mengoreksi kata jika ada typo dari AI.
   - **Hook Headline Banner**:
     - Banner teks judul di bagian atas layar (contoh: *"RAHASIA SUKSES DI USIA 20! 😱"*) dengan pilihan warna mencolok.

3. **On-Device FFmpeg Rendering**:
   - Seluruh proses render video MP4 dijalankan langsung di HP menggunakan engine FFmpeg Kit Android tanpa perlu menyewa server VPS backend.
   - Otomatis tersimpan ke Galeri HP (Album: `YTShortClipper`) dan tersedia tombol Share langsung ke TikTok, Instagram Reels, dan YouTube Shorts.

---

### CARA BUILD FILE APK DI LAPTOP / KOMPUTER:

Jika laptop Anda sudah memiliki **Flutter SDK** dan **Android SDK / Android Studio**:

1. Buka Terminal / PowerShell di folder proyek ini:
   ```bash
   cd "c:\Users\MyBook SAGA 12\.gemini\antigravity-ide\scratch\YTShortClipperV2_2.0.7-beta_x64_portable\mobile_app"
   ```

2. Ambil seluruh package dependency:
   ```bash
   flutter pub get
   ```

3. Jalankan perintah kompilasi APK rilis:
   ```bash
   flutter build apk --release
   ```

4. File APK siap install akan berada di:
   ```
   mobile_app/build/app/outputs/flutter-apk/app-release.apk
   ```

5. Kirim file `app-release.apk` tersebut ke smartphone Android Anda (via kabel USB, WhatsApp, atau Google Drive), lalu buka dan klik **Install**.

---

### CARA PENGGUNAAN DI HP ANDROID:

1. **Buka Aplikasi di HP**:
   - Buka menu **Pengaturan (Ikon Gir di kanan atas)** jika ingin memasukkan OpenAI / Gemini / Groq API Key (opsional, jika tidak dimasukkan aplikasi memiliki sistem pemotong otomatis cerdas bawaan).
2. **Tempel Link YouTube**:
   - Salin link video YouTube apa saja dari aplikasi YouTube, lalu klik tombol **Paste** di aplikasi.
   - Klik **"PROSES & CARI KLIP VIRAL"**.
3. **Pilih Klip Rekomendasi**:
   - Lihat daftar klip yang ditemukan lengkap dengan Virality Score-nya.
   - Klik **"BUKA STUDIO EDITOR (PRE-RENDER)"** pada klip yang Anda inginkan.
4. **Edit Klip Anda di Studio Pre-Render**:
   - Sesuaikan trim detik awal dan akhir.
   - Pilih layout tampilan (Blur Background / Center Crop / Split).
   - Pilih preset subtitle dan koreksi kata jika perlu.
   - Aktifkan Headline Banner di atas video.
5. **Render & Bagikan**:
   - Klik tombol kuning **"RENDER & EKSPOR VIDEO (MP4)"**.
   - Tunggu proses render FFmpeg selesai di HP Anda (progress 0% - 100%).
   - Klik **"Share Video"** untuk langsung upload ke TikTok, Instagram Reels, atau YouTube Shorts!
