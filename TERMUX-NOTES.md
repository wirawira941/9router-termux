# 9Router di Termux — catatan port

Ringkasan hasil bedah paket npm `9router` v0.5.104 (tarball resmi registry,
sha1 terverifikasi `4d4e8fbd0d9cddb8e8b9a2e13a79deabc5843257`) pada
2026-10-20, dan keputusan port-nya.

## Bentuk distribusi

- Paket npm Node.js murni: `bin: cli.js`, `engines: node >= 18`, lisensi MIT.
- Dependensi langsung semuanya JS murni (react, react-dom, confbox, enquirer,
  node-forge, node-machine-id, ora). Server + dashboard terbundel di `app/`
  (55 MB unpacked, 3461 file). **Tidak ada binary yang perlu di-compile** —
  port ini murni soal perilaku runtime di Android.
- Termux menyediakan Node 22/24 LTS resmi → syarat engine terpenuhi.

## Titik gesek (dari kode paketnya)

1. **SQLite** — `better-sqlite3` sengaja TIDAK dibundel. `hooks/postinstall.js`
   + `hooks/sqliteRuntime.js` memasangnya ke `~/.9router/runtime/node_modules`:
   - Node ≥ 22 → better-sqlite3 13.0.3 (N-API, prebuild di dalam paket,
     dipasang dengan `--ignore-scripts`). Prebuild-nya per platform:
     `prebuilds/<platform>-<arch>.node`. Di Termux `process.platform` adalah
     `android` → `android-arm64.node` tidak ada → validasi binary gagal →
     dianggap tidak tersedia.
   - Itu **aman**: komentar di kodenya sendiri bilang better-sqlite3 hanya
     optimasi kecepatan. Fallback-nya: `node:sqlite` (bawaan Node ≥ 22) dan
     sql.js (WASM, terbundel di `app/node_modules`, diverifikasi/dipasang
     ulang oleh runtime bila hilang).
   - Efek samping kecil: karena binary dianggap tidak valid, start berikutnya
     mungkin mengulang percobaan `npm install` better-sqlite3 (cepat, gagal
     validasi lagi, lanjut fallback). Bukan error.
2. **Postinstall non-fatal** — `hooks/postinstall.js` membungkus semua
   warm-up dengan try/catch dan selalu `process.exit(0)`. `npm install -g`
   tidak akan gagal gara-gara warm-up.
3. **Systray** — `systray2` di-lazy-install untuk tray desktop macOS/Linux;
   binary Linux-nya binary Go glibc, tidak jalan di Android. Tray hanya aktif
   lewat flag `--tray`, atau otomatis bila `--skip-update` + stdin bukan TTY.
   Installer tidak memakai keduanya → tray tidak tersentuh. **Jangan pakai
   `--tray` di Termux.**
4. **CLI flags yang relevan** (dari `cli.js` v0.5.104):
   `-p/--port` (default 20128), `-H/--host` (default `0.0.0.0`!),
   `-n/--no-browser`, `-l/--log`, `--skip-update`, `-t/--tray`.
   Server di-spawn dengan `--max-old-space-size=6144` (cap saja, bukan
   alokasi) dan `--dns-result-order=ipv4first`.
5. **Keamanan** — default host `0.0.0.0` = terlihat dari LAN, dan password
   dashboard fresh install `123456`. Installer menyarankan bind
   `127.0.0.1` + ganti password.
6. **Data dir** — `~/.9router` (DB SQLite di `~/.9router/db/data.sqlite`),
   bisa dipindah lewat env `DATA_DIR`. Runtime deps di `~/.9router/runtime/`.

## Keputusan

- Pin versi `0.5.104` di installer (reproducible); update manual via npm.
- **Patch heap 512 MB** (diminta user 2026-10-20): `cli.js:633` me-spawn server
  dengan `--max-old-space-size=6144` (6 GB, angka desktop; satu-satunya batas
  heap di paket — config Next.js hanya punya cache 50 MB). Installer me-rewrite
  flag itu di cli.js hasil install menjadi `NODE_HEAP_MB` (default 512) via
  `sed s/--max-old-space-size=[0-9]*/.../` — terbukti di file asli dan
  idempotent. `NODE_OPTIONS` tidak bisa meng-override flag spawn eksplisit.
  Patch hilang bila paket di-reinstall/update → jalankan ulang installer.
  Bila crash "heap out of memory" saat beban berat, naikkan (768/1024).
- Installer: cek/install Node → `npm install -g 9router@0.5.104` → verifikasi
  `9router --version` → smoke test terbatas (server di 127.0.0.1:20128,
  probe HTTP via fetch Node, lalu matikan lagi; bisa dilewati `SKIP_SMOKE=1`).
- Status: installer siap, menunggu uji di HP user (Termux asli tidak bisa
  dites dari VM Muse).
