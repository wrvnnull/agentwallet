# Tutorial: Transfer CASH Token via AgentWallet (Gratis / Sponsored Gas)

Tutorial lengkap dari cek saldo sampai transfer CASH token di Solana menggunakan AgentWallet API — tanpa bayar gas sendiri.

---

## Prasyarat

- Akun AgentWallet aktif (sudah punya `apiToken`, `username`, `solanaAddress`)
- Terminal dengan `curl` tersedia
- Wallet tujuan sudah punya token account CASH (jika belum, perlu dibuat dulu)

---

## Langkah 1 — Cek Saldo

Cek saldo semua akun untuk tahu berapa CASH yang tersedia.

```bash
curl https://frames.ag/api/wallets/{USERNAME}/balances \
  -H "Authorization: Bearer {API_TOKEN}"
```

**Contoh response yang ada CASH:**
```json
{
  "solanaWallets": [{
    "address": "5Zgc8Y4...",
    "balances": [{
      "chain": "solana",
      "asset": "cash",
      "rawValue": "200000",
      "decimals": 6,
      "displayValues": { "native": "0.2", "usd": "0.199913" }
    }]
  }]
}
```

> **Catat:** `rawValue` adalah jumlah yang akan dipakai saat transfer (dalam unit terkecil, 6 desimal).  
> Contoh: `200000` = 0.2 CASH

---

## Langkah 2 — Coba Transfer Langsung (Endpoint Standar)

AgentWallet endpoint standar **tidak mendukung** asset `cash` — hanya `sol` dan `usdc`.

```bash
# ❌ INI AKAN GAGAL
curl -X POST "https://frames.ag/api/wallets/{USERNAME}/actions/transfer-solana" \
  -H "Authorization: Bearer {API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"to":"{DESTINATION}","amount":"200000","asset":"cash","network":"mainnet"}'
```

**Error yang muncul:**
```json
{
  "error": "Invalid request",
  "details": {
    "fieldErrors": {
      "asset": ["Invalid enum value. Expected 'sol' | 'usdc', received 'cash'"]
    }
  }
}
```

> Karena `cash` bukan asset standar, harus pakai **SPL Token contract-call** secara manual.

---

## Langkah 3 — Cari Token Account Address

CASH adalah SPL Token 2022. Setiap wallet punya **token account** terpisah untuk masing-masing token.  
Kita perlu `pubkey` dari token account source (pengirim) dan destination (penerima).

**Mint address CASH token:**
```
CASHx9KJUStyftLFWGvEVf59SGeG9sh5FfcnZMVPCASH
```

### 3a. Cari token account milik pengirim

```bash
curl -s https://api.mainnet-beta.solana.com \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getTokenAccountsByOwner",
    "params": [
      "{SOLANA_ADDRESS_PENGIRIM}",
      {"mint": "CASHx9KJUStyftLFWGvEVf59SGeG9sh5FfcnZMVPCASH"},
      {"encoding": "jsonParsed"}
    ]
  }'
```

### 3b. Cari token account milik penerima

```bash
curl -s https://api.mainnet-beta.solana.com \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "getTokenAccountsByOwner",
    "params": [
      "{SOLANA_ADDRESS_PENERIMA}",
      {"mint": "CASHx9KJUStyftLFWGvEVf59SGeG9sh5FfcnZMVPCASH"},
      {"encoding": "jsonParsed"}
    ]
  }'
```

**Dari response, ambil nilai `pubkey`:**
```json
{
  "result": {
    "value": [{
      "pubkey": "EQVkBUPo87VE9DNBAy14HAbnqBav1k2YCffoUiXPHWx",  // ← ini yang dipakai
      "account": {
        "data": {
          "parsed": {
            "info": {
              "tokenAmount": { "amount": "200000", ... }
            }
          }
        }
      }
    }]
  }
}
```

> Catat dua `pubkey`:
> - **Source token account** = token account milik pengirim
> - **Destination token account** = token account milik penerima

---

## Langkah 4 — Transfer via Contract-Call

Gunakan instruksi `transferChecked` dari program **SPL Token 2022**.

### Encode data instruksi

Format data untuk `transferChecked` (12 bytes, little-endian):
- Byte 0: `0x0C` (discriminator = 12)
- Byte 1–8: amount dalam uint64 little-endian
- Byte 9: decimals (= 6 untuk CASH)

Untuk **200000** (0.2 CASH), data base64-nya adalah:
```
DEANAwAAAAAAAABg==
```

> **Cara hitung manual (Node.js):**
> ```js
> const buf = Buffer.alloc(10);
> buf.writeUInt8(12, 0);                        // discriminator transferChecked
> buf.writeBigUInt64LE(BigInt(200000), 1);       // amount
> buf.writeUInt8(6, 9);                          // decimals
> console.log(buf.toString('base64'));
> ```

### Jalankan contract-call

```bash
curl -X POST "https://frames.ag/api/wallets/{USERNAME}/actions/contract-call" \
  -H "Authorization: Bearer {API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "chainType": "solana",
    "instructions": [{
      "programId": "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
      "accounts": [
        {"pubkey": "{SOURCE_TOKEN_ACCOUNT}",      "isSigner": false, "isWritable": true},
        {"pubkey": "CASHx9KJUStyftLFWGvEVf59SGeG9sh5FfcnZMVPCASH", "isSigner": false, "isWritable": false},
        {"pubkey": "{DESTINATION_TOKEN_ACCOUNT}", "isSigner": false, "isWritable": true},
        {"pubkey": "{SOLANA_ADDRESS_PENGIRIM}",   "isSigner": true,  "isWritable": false}
      ],
      "data": "DEANAwAAAAAAAABg=="
    }],
    "network": "mainnet"
  }'
```

**Response sukses:**
```json
{
  "actionId": "...",
  "status": "confirmed",
  "txHash": "...",
  "explorer": "https://solscan.io/tx/..."
}
```

---

## Langkah 5 — Jika Gagal: Gas Not Sponsored (Akun Baru)

Jika muncul error seperti ini:

```json
{
  "error": "Transaction failed",
  "details": "Attempt to debit an account but found no record of a prior credit.",
  "gasSponsored": false,
  "gasMessage": "Gas fees are not sponsored for new accounts. Sponsorship activates 24 hours after account creation (~22h remaining)."
}
```

**Artinya:** Akun terlalu baru, gas sponsorship belum aktif.

### Solusi

| Opsi | Cara | Biaya |
|------|------|-------|
| ⏳ **Tunggu** | Tunggu hingga 24 jam setelah akun dibuat, lalu jalankan ulang command yang sama | Gratis |
| 💸 **Kirim SOL** | Transfer ~0.000005 SOL ke alamat Solana pengirim dari exchange/wallet lain | Butuh sedikit SOL |

Setelah gas aktif atau SOL terkirim, **jalankan ulang command di Langkah 4 persis sama** — tidak perlu langkah tambahan.

---

## Ringkasan Alur

```
Cek saldo
    ↓
Endpoint transfer standar → GAGAL (cash tidak didukung)
    ↓
Query token account (source + destination) via Solana RPC
    ↓
Contract-call transferChecked (SPL Token 2022)
    ↓
Sukses? → Selesai ✅
    ↓ (jika gagal)
Gas not sponsored? → Tunggu 24 jam atau kirim SOL
    ↓
Jalankan ulang → Selesai ✅
```

---

## Referensi Cepat

| Item | Value |
|------|-------|
| CASH Mint Address | `CASHx9KJUStyftLFWGvEVf59SGeG9sh5FfcnZMVPCASH` |
| SPL Token 2022 Program | `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb` |
| Solana Public RPC | `https://api.mainnet-beta.solana.com` |
| AgentWallet Base URL | `https://frames.ag/api` |
| Decimals CASH | 6 (1 CASH = 1_000_000 rawValue) |
| Gas Sponsorship | Aktif otomatis 24 jam setelah akun dibuat |
