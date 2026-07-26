# GoSAAD — Deployment Lokal dengan Docker

Repository ini menjalankan **GoSAAD** dan **PostgreSQL** secara lokal memakai Docker Compose. Setelah layanan siap, buka [http://localhost:8080](http://localhost:8080).

> [!IMPORTANT]
> Port aplikasi hanya dipublikasikan ke komputer lokal (`127.0.0.1:8080`). Aplikasi tidak dapat diakses dari perangkat lain dalam jaringan tanpa mengubah konfigurasi Docker Compose secara sengaja.

## Pilih cara instalasi

| Cara | Cocok untuk | Perintah utama |
| --- | --- | --- |
| **Otomatis** | Linux, macOS, atau WSL yang ingin dibantu memasang dan menyiapkan Docker | `bash autosetup.sh` |
| **Manual** | Windows dengan Docker Desktop, atau pengguna yang ingin mengatur setiap langkah sendiri | `docker compose up -d` |

## Prasyarat

- [Docker](https://www.docker.com/products/docker-desktop/) sedang berjalan. Di Windows dan macOS, gunakan Docker Desktop.
- Docker Compose v2 tersedia. Pastikan dengan:

  ```sh
  docker compose version
  ```

- Git diperlukan untuk mengambil repository jika belum tersedia.
- Port `8080` pada komputer lokal belum digunakan aplikasi lain.

## Cara 1 — Instalasi otomatis

Jalankan pilihan ini di **Linux, macOS, atau WSL dengan integrasi Docker Desktop aktif**. Skrip akan memeriksa Docker dan Docker Compose, membuat `.env` dengan nilai rahasia acak bila Anda setuju, lalu menawarkan untuk memulai layanan.

```sh
git clone https://github.com/gosaad/gosaad-releases.git
cd gosaad-releases
bash autosetup.sh
```

Ikuti pertanyaan yang muncul di terminal. Pada Linux, skrip mungkin meminta `sudo` bila Docker belum terpasang.

> [!NOTE]
> Skrip ini tidak mendukung Git Bash, MSYS, Cygwin, atau lingkungan Bash native Windows. Di Windows, gunakan [cara manual](#cara-2--instalasi-manual) atau jalankan skrip dari WSL yang telah terhubung ke Docker Desktop.

## Cara 2 — Instalasi manual

### 1. Ambil repository dan buat file konfigurasi

Gunakan perintah sesuai terminal Anda.

<details>
<summary><strong>PowerShell (Windows)</strong></summary>

```powershell
git clone https://github.com/gosaad/gosaad-releases.git
Set-Location gosaad-releases
Copy-Item .env.example .env
```

</details>

<details>
<summary><strong>Bash (Linux, macOS, atau WSL)</strong></summary>

```sh
git clone https://github.com/gosaad/gosaad-releases.git
cd gosaad-releases
cp .env.example .env
```

</details>

### 2. Isi nilai rahasia di `.env`

Buka file `.env` dengan editor teks. Isi empat nilai berikut dengan nilai acak yang **berbeda satu sama lain**:

| Variabel | Wajib | Keterangan |
| --- | --- | --- |
| `APP_VERSION` | Ya | Versi image GoSAAD yang digunakan. Skrip instalasi tidak pernah mengubah nilai ini secara otomatis. |
| `POSTGRES_PASSWORD` | Ya | Kata sandi administrator PostgreSQL. |
| `APP_DB_PASSWORD` | Ya | Kata sandi akun database aplikasi. |
| `JWT_SECRET` | Ya | Rahasia untuk token akses aplikasi. |
| `JWT_REFRESH_SECRET` | Ya | Rahasia untuk token pembaruan aplikasi. |

Di Bash, buat satu nilai aman dengan perintah berikut. Jalankan empat kali untuk memperoleh empat nilai berbeda.

```sh
openssl rand -hex 32
```

Di PowerShell, gunakan perintah berikut empat kali bila `openssl` tidak tersedia.

```powershell
$bytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
```

Contoh struktur `.env` setelah diisi:

```dotenv
APP_VERSION=0.0.1
POSTGRES_PASSWORD=<nilai-acak-pertama>
APP_DB_NAME=gosaad
APP_DB_USER=gosaad_app
APP_DB_PASSWORD=<nilai-acak-kedua>
JWT_SECRET=<nilai-acak-ketiga>
JWT_REFRESH_SECRET=<nilai-acak-keempat>
```

Ubah `APP_VERSION` secara manual hanya ketika Anda memang ingin memperbarui versi aplikasi. Biarkan konfigurasi `SYSTEM_RESTORE_*` seperti semula kecuali fitur pemulihan basis data memang akan digunakan. File `.env` sudah diabaikan oleh Git; jangan membagikan isinya atau memasukkannya ke repository.

### 3. Jalankan layanan

```sh
docker compose up -d
docker compose ps
```

Tunggu hingga status layanan menjadi `healthy`, lalu buka [http://localhost:8080](http://localhost:8080). Saat startup pertama, Docker perlu mengunduh image sehingga proses dapat memerlukan waktu lebih lama.

Jika halaman belum tersedia, pantau log aplikasi:

```sh
docker compose logs --follow gosaad-core
```

Tekan <kbd>Ctrl</kbd> + <kbd>C</kbd> untuk berhenti melihat log; layanan tetap berjalan di latar belakang.

## Operasi harian

| Kebutuhan | Perintah |
| --- | --- |
| Melihat status layanan | `docker compose ps` |
| Melihat log aplikasi | `docker compose logs --follow gosaad-core` |
| Memulai kembali layanan yang berhenti | `docker compose up -d` |
| Menghentikan layanan | `docker compose down` |
| Memperbarui release | lihat langkah berikut |

### Memperbarui GoSAAD

Edit `APP_VERSION` di `.env` secara manual ke versi tujuan, lalu jalankan dari folder repository:

```sh
git pull --ff-only
docker compose pull
docker compose up -d
docker compose ps
```

`docker compose pull` mengunduh image yang tepat sesuai `APP_VERSION`, sedangkan `docker compose up -d` menerapkan perubahan tanpa perlu menjalankan container di terminal. Skrip instalasi tidak mengubah `APP_VERSION`.

## Data dan penghapusan

Basis data dan runtime aplikasi disimpan dalam volume Docker, sehingga perintah berikut **tidak menghapus data**:

```sh
docker compose down
```

> [!CAUTION]
> Jangan menjalankan `docker compose down -v` kecuali Anda benar-benar ingin menghapus seluruh basis data lokal dan data runtime. Tindakan ini tidak dapat dibatalkan melalui Docker.

## Pemecahan masalah

<details>
<summary><strong><code>docker compose</code> tidak ditemukan atau Docker tidak dapat dihubungi</strong></summary>

Pastikan Docker Desktop sudah dibuka dan statusnya berjalan, lalu ulangi:

```sh
docker compose version
docker info
```

Di WSL, aktifkan integrasi distribusi WSL di pengaturan Docker Desktop.

</details>

<details>
<summary><strong>Port <code>8080</code> sudah digunakan</strong></summary>

Hentikan aplikasi lain yang memakai port tersebut, kemudian jalankan ulang `docker compose up -d`. Jika port perlu diubah, ubah pemetaan port pada `docker-compose.yml` dan gunakan alamat baru yang sesuai.

</details>

<details>
<summary><strong>Compose menolak konfigurasi <code>.env</code></strong></summary>

Pastikan keempat variabel wajib tidak kosong dan tidak mengandung nilai contoh seperti `<nilai-acak-pertama>`. Setelah memperbaiki file, jalankan:

```sh
docker compose up -d
docker compose logs --follow gosaad-core
```

</details>

<details>
<summary><strong>Aplikasi belum dapat dibuka</strong></summary>

Periksa status dan log:

```sh
docker compose ps
docker compose logs --tail=100 gosaad-core
docker compose logs --tail=100 database
```

Database harus siap lebih dahulu; container aplikasi memang menunggu health check database sebelum mulai berjalan.

</details>

## Struktur deployment

| Komponen | Peran |
| --- | --- |
| `gosaad-core` | Menjalankan aplikasi GoSAAD pada port lokal `8080`. |
| `database` | Menjalankan PostgreSQL pada jaringan internal Docker. |
| `postgres-data` | Volume persisten untuk data PostgreSQL. |
| `api-runtime` | Volume persisten untuk runtime aplikasi. |

Untuk perubahan konfigurasi, edit `.env` atau `docker-compose.yml` sesuai kebutuhan, lalu terapkan dengan `docker compose up -d`.
