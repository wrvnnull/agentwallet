# 🤖 AgentWallet CASH Runner

Automation bot untuk menjalankan **x402 micropayments** di semua jaringan blockchain menggunakan [AgentWallet](https://frames.ag) — berjalan otomatis via **GitHub Actions** setiap 5 menit.

---

## ✨ Fitur

- ✅ Mendukung **9 jaringan blockchain**: Solana, Solana Devnet, Base, Base Sepolia, Ethereum, Optimism, Polygon, Arbitrum, BNB Chain, Gnosis, Sepolia
- ✅ Mendukung **3 token**: CASH, USDC, USDT
- ✅ **60+ layanan API** dibayar via x402 (CoinGecko, Jupiter, Exa, Twitter, OpenRouter, AI Gen, AgentMail, Wordspace)
- ✅ Notifikasi real-time via **Telegram Bot**
- ✅ Pengecekan balance otomatis sebelum eksekusi (mencegah kegagalan)
- ✅ **Dry run** sebelum setiap pembayaran untuk verifikasi
- ✅ Cache balance antar run via GitHub Actions Cache
- ✅ Update policy otomatis untuk mengizinkan semua chain

---

## 🏗️ Struktur Repository

```
.
├── .github/
│   └── workflows/
│       └── run_cash.yml       # GitHub Actions workflow
├── cash_all.sh                # Script utama bot
└── README.md
```

---

## ⚙️ Setup

### 1. Fork / Clone Repository

```bash
git clone https://github.com/USERNAME/REPO_NAME.git
cd REPO_NAME
```

### 2. Tambahkan GitHub Secrets

Buka **Settings → Secrets and variables → Actions → New repository secret**, lalu tambahkan:

| Secret | Keterangan |
|--------|------------|
| `AGENTWALLET_API_TOKEN` | API token dari [frames.ag](https://frames.ag) |
| `AGENTWALLET_USERNAME` | Username AgentWallet kamu |
| `TELEGRAM_BOT_TOKEN` | Token bot Telegram (opsional, untuk notifikasi) |
| `TELEGRAM_CHAT_ID` | Chat ID Telegram kamu (opsional) |

> 💡 `TELEGRAM_BOT_TOKEN` dan `TELEGRAM_CHAT_ID` bersifat opsional. Jika tidak diisi, notifikasi Telegram akan dilewati.

### 3. Aktifkan GitHub Actions

Pastikan tab **Actions** di repository sudah diaktifkan. Workflow akan berjalan otomatis setiap 5 menit sesuai jadwal cron.

---

## 🚀 Cara Kerja

```
┌──────────────────────────────────────────────────────┐
│                  GitHub Actions (cron)               │
│                  Setiap 5 menit                      │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │  Cek CASH balance      │
           │  wallet reward         │
           └────────────┬───────────┘
                        │ ≥ 0.05 CASH?
                        ▼
           ┌────────────────────────┐
           │  Cek balance semua     │
           │  wallet (Solana + EVM) │
           └────────────┬───────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │  Update policy wallet  │
           │  (izinkan semua chain) │
           └────────────┬───────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │  Sign message (EVM +   │
           │  Solana) + Faucet SOL  │
           └────────────┬───────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │  Loop 60+ x402         │
           │  payments (dry run →   │
           │  eksekusi → feedback)  │
           └────────────┬───────────┘
                        │
                        ▼
           ┌────────────────────────┐
           │  Kirim summary         │
           │  Telegram              │
           └────────────────────────┘
```

---

## 🌐 Jaringan & Token yang Didukung

| Jaringan | Chain ID | Token |
|----------|----------|-------|
| Solana Mainnet | — | CASH, USDC, USDT |
| Solana Devnet | EtWTRABZaYq6iMfeYKouRu166VU2xqa1 | USDC |
| Base | 8453 | USDC, USDT |
| Base Sepolia | 84532 | USDC |
| Ethereum | 1 | USDC, USDT |
| Optimism | 10 | USDC |
| Polygon | 137 | USDC |
| Arbitrum | 42161 | USDC |
| BNB Chain | 56 | USDC |
| Gnosis | 100 | USDC |
| Sepolia | 11155111 | USDC |

---

## 🧰 Layanan API yang Digunakan

| Layanan | Endpoint |
|---------|----------|
| **CoinGecko** | Price, Markets, Search, Token Info |
| **Jupiter** | Price, Tokens |
| **Exa** | Search, Answer, Find Similar |
| **Twitter** | Search Tweets, Trends, User Tweets |
| **OpenRouter** | GPT-4o, Claude 3 Haiku |
| **AI Gen** | DALL-E 3, Veo 3, Sora 2, Minimax Music |
| **AgentMail** | Create Inbox, Send Email |
| **Wordspace** | Agent (story generation) |

---

## 📬 Notifikasi Telegram

Bot mengirim notifikasi Telegram untuk event berikut:

- 🚀 **Run dimulai** — info rank, streak, balance, active agents
- ✅ **Pembayaran berhasil** — nominal, chain, sisa balance
- ❌ **Pembayaran gagal** — error message
- 💸 **Saldo habis** — notifikasi stop otomatis
- ⏸ **CASH kurang** — skip run jika < 0.05 CASH
- 📥 **CASH masuk** — deteksi otomatis saldo bertambah

---

## 📋 Environment Variables

| Variable | Sumber | Keterangan |
|----------|--------|------------|
| `AGENTWALLET_API_TOKEN` | GitHub Secret | API token AgentWallet |
| `AGENTWALLET_USERNAME` | GitHub Secret | Username AgentWallet |
| `TELEGRAM_BOT_TOKEN` | GitHub Secret | Token bot Telegram (opsional) |
| `TELEGRAM_CHAT_ID` | GitHub Secret | Chat ID Telegram (opsional) |

---

## ⏱️ Jadwal Otomatis

Workflow berjalan otomatis setiap **5 menit** via GitHub Actions cron:

```yaml
schedule:
  - cron: "*/5 * * * *"
```

Bisa juga dijalankan manual lewat tab **Actions → Run workflow**.

---

## 🔒 Keamanan

- ⚠️ **Jangan pernah** commit API token atau credentials langsung ke repository
- Gunakan selalu **GitHub Secrets** untuk menyimpan kredensial
- Script melakukan **dry run** terlebih dahulu sebelum eksekusi pembayaran nyata
- Ada pengecekan **minimum balance** (0.05 CASH) sebelum memulai

---

## 📊 Output Contoh

```
============================================================
  AgentWallet - ALL Networks + ALL Tokens v4.0
  Time : 2025-03-15 10:00:00 UTC | User: myuser
  Jeda : 60s
============================================================
  Rank: #42 | Streak: 7d | Pts: 1500 | Refs: 3 | Tier: silver
  Active Agents: 1234

[1] Jupiter: Price [SOL/CASH]
  Dry  : 0.001 CASH | chain=solana | policy=True
  OK   : 0.001 CASH @ solana

============================================================
  SELESAI | 2025-03-15 11:00:00 UTC
  OK    : 58/62
  GAGAL : 4/62
============================================================
```

---

## 📄 Lisensi

MIT License — bebas digunakan dan dimodifikasi.
