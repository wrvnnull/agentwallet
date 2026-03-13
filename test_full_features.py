#!/usr/bin/env python3
"""
=============================================================
AgentWallet Full Feature Test — MAX REWARD v2.2 NONSTOP
=============================================================
Fixes dari v2.1:
  🔧 Policy parsing diperbaiki (handle semua format response)
  🔧 Parallel workers dikurangi 20→8 (anti rate-limit)
  🔧 x402 dry runs dibagi batch kecil + delay antar batch
  🔧 Faucet/manual sign pakai timeout lebih besar (45s)
  🔧 Transfer NONSTOP: Base+Solana jalan malam, full 9 chain siang
  🔧 Retry lebih pintar: timeout error → retry 3x, 4xx → skip
  🔧 Contract call error diabaikan (ℹ️ bukan ❌)

Reward farming nonstop 24 jam:
  ⏰ 00–06 UTC (malam WIB siang): Base USDC + Solana transfer
  ⏰ 06–24 UTC (siang WIB sore) : semua 9 EVM chain + Solana
  📋 Feedback tiap 6 jam        : +CASH cashback
  💸 x402 real payment          : +CASH cashback
  🚰 Faucet devnet SOL          : 3x/hari gratis
  ✍️  Sign message 24x/hari      : aktivitas harian
=============================================================
"""

import json
import requests
import time
import os
import sys
from pathlib import Path
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed

# =============================================================
# RETRY HELPER
# - timeout/conn error → retry sampai max_retries
# - 4xx (client error) → langsung return, tidak retry
# =============================================================
def retry_call(method, url, headers=None, data=None,
               max_retries=3, delay=3, timeout=20):
    err = {"error": "max_retries_exceeded"}
    for attempt in range(max_retries):
        try:
            kwargs = {"headers": headers or {}, "timeout": timeout}
            if data is not None:
                kwargs["json"] = data
            resp = requests.request(method, url, **kwargs)
            if resp.status_code == 429:
                time.sleep(delay * 3)
                continue
            if 400 <= resp.status_code < 500:
                try:
                    return resp.json()
                except Exception:
                    return {"error": f"HTTP {resp.status_code}", "body": resp.text[:200]}
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.Timeout:
            err = {"error": "timeout"}
        except requests.exceptions.ConnectionError as e:
            err = {"error": f"conn_err: {str(e)[:60]}"}
        except Exception as e:
            err = {"error": str(e)[:150]}
        if attempt < max_retries - 1:
            wait = delay * (attempt + 1)  # backoff: 3s, 6s
            time.sleep(wait)
    return err

# =============================================================
# KONFIGURASI
# =============================================================
api_token      = os.environ.get("AGENTWALLET_API_TOKEN")
username       = os.environ.get("AGENTWALLET_USERNAME")
telegram_token = os.environ.get("TELEGRAM_BOT_TOKEN")
telegram_chat  = os.environ.get("TELEGRAM_CHAT_ID")

if not api_token or not username:
    config_path = Path.home() / ".agentwallet" / "config.json"
    if config_path.exists():
        cfg = json.loads(config_path.read_text())
        api_token = api_token or cfg.get("apiToken")
        username  = username  or cfg.get("username")

if not api_token or not username:
    print("❌ Missing AGENTWALLET_API_TOKEN or AGENTWALLET_USERNAME")
    sys.exit(1)

BASE    = f"https://frames.ag/api/wallets/{username}"
HEADERS = {"Authorization": f"Bearer {api_token}", "Content-Type": "application/json"}

# =============================================================
# SCHEDULING
# =============================================================
now          = datetime.now(timezone.utc)
current_hour = now.hour
is_daytime   = 6 <= current_hour < 24   # full 9 chain transfer
is_every_6h  = current_hour % 6 == 0   # feedback + real payment
is_midnight  = current_hour == 0       # daily telegram report

# =============================================================
# HELPERS
# =============================================================
def call(method, path, data=None, timeout=20):
    return retry_call(method, f"{BASE}/{path}", HEADERS, data, timeout=timeout)

def call_public(method, url, data=None, timeout=15):
    return retry_call(method, url, {"Content-Type": "application/json"}, data, timeout=timeout)

def ok(r):
    return isinstance(r, dict) and "error" not in r

def safe_get(d, *keys, default="N/A"):
    for k in keys:
        if not isinstance(d, dict):
            return default
        d = d.get(k, default)
        if d == default:
            return default
    return d

def fmt_addr(addr, n=20):
    if not addr or addr == "N/A":
        return "N/A"
    return (addr[:n] + "...") if len(addr) > n else addr

def parse_policy(p):
    """
    Parse policy response — handle berbagai format:
    Format 1: {"max_per_tx_usd": "25", "allow_chains": [...]}
    Format 2: {"data": {"max_per_tx_usd": "25", ...}}
    Format 3: {"success": true, "data": {...}}
    """
    if not isinstance(p, dict):
        return {}, "N/A", "N/A"
    # unwrap data jika ada
    inner = p.get("data", p)
    if not isinstance(inner, dict):
        inner = p
    max_tx  = inner.get("max_per_tx_usd",  p.get("max_per_tx_usd",  "N/A"))
    chains  = inner.get("allow_chains",    p.get("allow_chains",    "N/A"))
    return inner, max_tx, chains

def send_telegram(msg):
    if not telegram_token or not telegram_chat:
        return False
    try:
        r = requests.post(
            f"https://api.telegram.org/bot{telegram_token}/sendMessage",
            json={"chat_id": telegram_chat, "text": msg, "parse_mode": "HTML"},
            timeout=15,
        )
        return r.status_code == 200
    except Exception:
        return False

# =============================================================
# CONSTANTS
# =============================================================
TRANSFER_USD = 0.10
DRY_URL      = "https://registry.frames.ag/api/service/exa/api/search"
DRY_BODY     = {"query": "AI agents x402", "numResults": 1}

# Chain configs
# is_daytime  → semua 9 chain
# !is_daytime → hanya Base (policy nighttime allow Base+Solana)
EVM_CHAINS_DAY = [
    ("Base",         8453,     "usdc"),
    ("Ethereum",     1,        "usdc"),
    ("Optimism",     10,       "usdc"),
    ("Polygon",      137,      "usdc"),
    ("Arbitrum",     42161,    "usdc"),
    ("BSC",          56,       "usdc"),
    ("Gnosis",       100,      "usdc"),
    ("Sepolia",      11155111, "usdc"),
    ("Base Sepolia", 84532,    "usdc"),
]
EVM_CHAINS_NIGHT = [
    ("Base",         8453,     "usdc"),  # Base selalu jalan
]

X402_NETWORKS = [
    ("EVM Auto",          {"preferredChain": "auto"}),
    ("Base USDC",         {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 8453}),
    ("Ethereum USDC",     {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 1}),
    ("Optimism USDC",     {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 10}),
    ("Polygon USDC",      {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 137}),
    ("Arbitrum USDC",     {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 42161}),
    ("BSC USDC",          {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 56}),
    ("Gnosis USDC",       {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 100}),
    ("Sepolia USDC",      {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 11155111}),
    ("Base Sepolia USDC", {"preferredChain": "evm", "preferredToken": "USDC",  "preferredChainId": 84532}),
    ("Base USDT",         {"preferredChain": "evm", "preferredToken": "USDT",  "preferredChainId": 8453}),
    ("Ethereum USDT",     {"preferredChain": "evm", "preferredToken": "USDT",  "preferredChainId": 1}),
    ("Solana USDC",       {"preferredChain": "solana", "preferredToken": "USDC"}),
    ("Solana USDT",       {"preferredChain": "solana", "preferredToken": "USDT"}),
    ("Solana CASH",       {"preferredChain": "solana", "preferredToken": "CASH"}),
]

# =============================================================
# RESULTS STORAGE
# =============================================================
results = {
    "timestamp":         now.isoformat(),
    "schedule":          {"hour": current_hour, "daytime": is_daytime},
    "connection":        {},
    "network_pulse":     {},
    "balances":          {},
    "stats":             {},
    "referrals":         {},
    "wallets":           {},
    "wallet_create":     {},
    "policy":            {},
    "activity":          {},
    "x402_dry_runs":     [],
    "x402_real_payment": {},
    "x402_manual_sign":  {},
    "sign_message":      {},
    "faucet":            {},
    "evm_transfers":     [],
    "evm_contract_call": {},
    "sol_transfers":     [],
    "sol_contract_call": {},
    "feedback":          {},
    "errors":            [],
    "timings":           {},
}

evm_ok = evm_fail = sol_ok = sol_fail = dry_ok = sign_ok = 0

# =============================================================
# HEADER
# =============================================================
t_start = time.time()
EVM_CHAINS = EVM_CHAINS_DAY if is_daytime else EVM_CHAINS_NIGHT
mode_str   = "DAYTIME (9 chains)" if is_daytime else "NIGHTTIME (Base only)"

print("=" * 65)
print("  AGENTWALLET FULL FEATURE TEST — MAX REWARD v2.2 NONSTOP")
print(f"  Time  : {now.strftime('%Y-%m-%d %H:%M:%S')} UTC")
print(f"  User  : {username}")
print(f"  Mode  : {mode_str} | every6h={is_every_6h} | midnight={is_midnight}")
print("=" * 65)

# =============================================================
# FASE 1 — PARALLEL READS (8 workers, aman dari rate limit)
# =============================================================
print("\n── FASE 1: PARALLEL READS ───────────────────────────────")
t0 = time.time()

read_tasks = {
    "connection": lambda: call_public("GET", f"https://frames.ag/api/wallets/{username}"),
    "balances":   lambda: call("GET", "balances"),
    "stats":      lambda: call("GET", "stats"),
    "referrals":  lambda: call("GET", "referrals"),
    "wallets":    lambda: call("GET", "wallets"),
    "activity":   lambda: call("GET", "activity?limit=50"),
    "policy":     lambda: call("GET", "policy"),
    "pulse":      lambda: call_public("GET", "https://frames.ag/api/network/pulse"),
    "prices":     lambda: call_public(
        "GET",
        "https://api.coingecko.com/api/v3/simple/price?ids=solana,ethereum&vs_currencies=usd",
        timeout=10,
    ),
}

read_results = {}
with ThreadPoolExecutor(max_workers=8) as pool:
    futures = {pool.submit(fn): name for name, fn in read_tasks.items()}
    for future in as_completed(futures):
        name = futures[future]
        try:
            read_results[name] = future.result()
        except Exception as e:
            read_results[name] = {"error": str(e)[:100]}

print(f"  ✅ Done in {time.time()-t0:.1f}s")
results["timings"]["parallel_reads"] = round(time.time() - t0, 2)

# ── Unpack ──────────────────────────────────────────────────
conn         = read_results.get("connection", {})
balances     = read_results.get("balances", {})
stats        = read_results.get("stats", {})
refs         = read_results.get("referrals", {})
wallets_resp = read_results.get("wallets", {})
activity     = read_results.get("activity", {})
policy       = read_results.get("policy", {})
pulse        = read_results.get("pulse", {})
prices_r     = read_results.get("prices", {})

# Prices
prices = {"sol": 140.0, "eth": 2000.0}
if ok(prices_r):
    prices["sol"] = float(prices_r.get("solana", {}).get("usd", 140))
    prices["eth"] = float(prices_r.get("ethereum", {}).get("usd", 2000))

USDC_AMOUNT = str(int(TRANSFER_USD * 1_000_000))
SOL_AMOUNT  = str(int(TRANSFER_USD / prices["sol"] * 1e9))

# Connection
connected   = ok(conn) and conn.get("connected", False)
evm_address = conn.get("evmAddress", "")   if ok(conn) else ""
sol_address = conn.get("solanaAddress", "") if ok(conn) else ""
results["connection"] = {
    "status": "OK" if connected else "FAIL",
    "evmAddress": evm_address, "solanaAddress": sol_address,
}
if not connected:
    results["errors"].append("connection_failed")
print(f"  Connection : {'✅ OK' if connected else '❌ FAIL'}")
print(f"  EVM        : {fmt_addr(evm_address, 42)}")
print(f"  Solana     : {fmt_addr(sol_address, 44)}")

# Pulse
results["network_pulse"] = pulse
pulse_ok = ok(pulse)
print(f"  Pulse      : {'✅' if pulse_ok else '❌'} | "
      f"Agents={pulse.get('activeAgents','N/A')} | "
      f"Txns={pulse.get('transactionCount','N/A')}")

# Balances
results["balances"] = balances
sol_main = eth_base = usdc_base = 0.0
if ok(balances):
    for w in balances.get("solanaWallets", []):
        for b in w.get("balances", []):
            if "devnet" not in b.get("chain","") and b.get("asset") == "sol":
                sol_main += float(safe_get(b, "displayValues", "native", default=0))
    for w in balances.get("evmWallets", []):
        for b in w.get("balances", []):
            ch = b.get("chain","")
            if ch == "base" and b.get("asset") == "eth":
                eth_base  = float(safe_get(b, "displayValues", "native", default=0))
            if ch == "base" and b.get("asset","").lower() == "usdc":
                usdc_base = float(safe_get(b, "displayValues", "native", default=0))
    print(f"  SOL        : {sol_main:.6f} (~${sol_main*prices['sol']:.3f})")
    print(f"  ETH Base   : {eth_base:.6f} (~${eth_base*prices['eth']:.3f})")
    print(f"  USDC Base  : {usdc_base:.4f}")
else:
    results["errors"].append(f"balances: {balances.get('error','?')}")
    print(f"  Balances   : ❌ {balances.get('error','?')}")

# Stats & Referrals
results["stats"]     = stats
results["referrals"] = refs
rank      = stats.get("rank", "N/A")         if ok(stats) else "N/A"
streak    = stats.get("streakDays", 0)        if ok(stats) else 0
volume    = stats.get("totalVolume", "N/A")   if ok(stats) else "N/A"
ref_count = refs.get("referralCount", 0)      if ok(refs)  else 0
ref_pts   = refs.get("airdropPoints", 0)      if ok(refs)  else 0
ref_tier  = refs.get("tier", "bronze")        if ok(refs)  else "bronze"
print(f"  Stats      : Rank=#{rank} | Streak={streak}d | Vol={volume}")
print(f"  Referrals  : {ref_count} refs | {ref_pts} pts | {ref_tier}")

# Wallets
results["wallets"] = wallets_resp
wallet_tier = "N/A"
if ok(wallets_resp):
    wallet_tier = wallets_resp.get("tier", "N/A")
    limits      = wallets_resp.get("limits", {})
    counts      = wallets_resp.get("counts", {})
    wallet_list = wallets_resp.get("wallets", [])
    evm_limit   = limits.get("ethereum", 1)
    sol_limit   = limits.get("solana", 1)
    evm_count   = counts.get("ethereum", 0)
    sol_count   = counts.get("solana", 0)
    print(f"  Wallets    : tier={wallet_tier} | EVM {evm_count}/{evm_limit} | SOL {sol_count}/{sol_limit}")
    for w in wallet_list:
        st = "🔴FROZEN" if w.get("frozen") else "🟢"
        print(f"    {st} [{w.get('chainType','?')}] {fmt_addr(w.get('address',''), 28)}")
else:
    results["errors"].append(f"wallets: {wallets_resp.get('error','?')}")
    print(f"  Wallets    : ❌ {wallets_resp.get('error','?')}")

# Activity
event_count = 0
event_types = {}
if ok(activity):
    events      = activity.get("events", [])
    event_count = len(events)
    for ev in events:
        t = ev.get("type", "unknown")
        event_types[t] = event_types.get(t, 0) + 1
    top3 = sorted(event_types.items(), key=lambda x: -x[1])[:3]
    print(f"  Activity   : {event_count} events | top: {top3}")
results["activity"] = {"count": event_count, "types": event_types}

# Policy — FIXED PARSING
results["policy"]["raw"] = policy
policy_inner, max_tx_cur, chains_cur = parse_policy(policy)
print(f"  Policy     : max_per_tx=${max_tx_cur} | chains={chains_cur}")

# =============================================================
# FASE 2 — WRITE SETUP (policy update + wallet create)
# =============================================================
print("\n── FASE 2: WRITE SETUP ──────────────────────────────────")
t0 = time.time()

if is_daytime:
    policy_payload = {
        "max_per_tx_usd": "0.10",
        "allow_chains": ["base","solana","ethereum","optimism",
                         "polygon","arbitrum","bsc","gnosis"],
    }
    mode_label = "daytime — all chains, max $0.10"
else:
    policy_payload = {
        "max_per_tx_usd": "0.10",   # tetap $0.10 malam, Base+SOL jalan
        "allow_chains": ["base","solana"],
    }
    mode_label = "nighttime — Base+SOL, max $0.10"

def do_policy_update():
    return call("PATCH", "policy", policy_payload)

def do_wallet_create():
    if not ok(wallets_resp):
        return {"skipped": "wallets_resp_failed"}
    ec = wallets_resp.get("counts", {}).get("ethereum", 0)
    el = wallets_resp.get("limits", {}).get("ethereum", 1)
    sc = wallets_resp.get("counts", {}).get("solana", 0)
    sl = wallets_resp.get("limits", {}).get("solana", 1)
    if ec < el:
        return call("POST", "wallets", {"chainType": "ethereum"})
    elif sc < sl:
        return call("POST", "wallets", {"chainType": "solana"})
    return {"skipped": f"limit_reached (tier={wallet_tier})"}

with ThreadPoolExecutor(max_workers=2) as pool:
    f_pol = pool.submit(do_policy_update)
    f_wal = pool.submit(do_wallet_create)
    policy_upd    = f_pol.result()
    wallet_create = f_wal.result()

results["policy"]["update"]  = policy_upd
results["wallet_create"]     = wallet_create

# Parse policy update response juga
_, max_tx_new, chains_new = parse_policy(policy_upd)
pu_ok = ok(policy_upd)
if not pu_ok:
    results["errors"].append(f"policy_update: {policy_upd.get('error','?')}")

wc = wallet_create
if "skipped" in wc:
    wc_label = f"⏸ {wc['skipped']}"
elif ok(wc):
    wc_label = f"✅ {fmt_addr(wc.get('address',''), 25)}"
else:
    wc_label = f"ℹ️ {wc.get('error','?')[:40]}"

print(f"  Policy : {'✅' if pu_ok else '❌'} ({mode_label})")
if pu_ok:
    print(f"           max_per_tx=${max_tx_new} | chains={chains_new}")
print(f"  Wallet : {wc_label}")
print(f"  Done in {time.time()-t0:.1f}s")
results["timings"]["write_setup"] = round(time.time() - t0, 2)

# =============================================================
# FASE 3 — x402 DRY RUNS (batch 5, delay 1s antar batch)
# 20 workers → 8 workers, dibagi 3 batch @ 5 network
# Ini fix utama untuk max_retries_exceeded
# =============================================================
print("\n── FASE 3: x402 DRY RUNS (15 networks, batched) ────────")
t0 = time.time()

def do_x402_dry(name, extra):
    payload = {"url": DRY_URL, "method": "POST", "body": DRY_BODY, "dryRun": True}
    payload.update(extra)
    return name, call("POST", "actions/x402/fetch", payload, timeout=25)

# Bagi jadi 3 batch @ 5 network, jalan paralel per batch
BATCH_SIZE = 5
dry_results_map = {}
for i in range(0, len(X402_NETWORKS), BATCH_SIZE):
    batch = X402_NETWORKS[i:i+BATCH_SIZE]
    with ThreadPoolExecutor(max_workers=BATCH_SIZE) as pool:
        futures = {pool.submit(do_x402_dry, name, extra): name
                   for name, extra in batch}
        for future in as_completed(futures):
            try:
                name_ret, res = future.result()
                dry_results_map[name_ret] = res
            except Exception as e:
                nm = futures[future]
                dry_results_map[nm] = {"error": str(e)[:80]}
    # delay 1s antar batch supaya tidak rate-limit
    if i + BATCH_SIZE < len(X402_NETWORKS):
        time.sleep(1)

for name, extra in X402_NETWORKS:
    r    = dry_results_map.get(name, {"error": "not_found"})
    cost = (safe_get(r, "payment", "amountFormatted", default="error")
            if ok(r) else f"FAIL:{r.get('error','?')[:20]}")
    pol  = safe_get(r, "payment", "policyAllowed", default="?") if ok(r) else "?"
    icon = "✅" if ok(r) else "❌"
    if ok(r):
        dry_ok += 1
    else:
        results["errors"].append(f"dry_{name}: {r.get('error','?')[:40]}")
    results["x402_dry_runs"].append({"network": name, "cost": cost, "policyAllowed": pol})
    print(f"  {icon} {name:<24}: {cost:<18} policy={pol}")

print(f"  → {dry_ok}/{len(X402_NETWORKS)} OK | {time.time()-t0:.1f}s")
results["timings"]["x402_dry_runs"] = round(time.time() - t0, 2)

# =============================================================
# FASE 4 — PARALLEL: sign EVM + sign SOL + manual sign + faucet
# Timeout lebih besar untuk manual sign (45s) dan faucet (45s)
# =============================================================
print("\n── FASE 4: SIGN + FAUCET (parallel) ─────────────────────")
t0 = time.time()

sign_msg = f"AgentWallet | {now.isoformat()} | {username}"

def do_sign_evm():
    return call("POST", "actions/sign-message",
                {"message": sign_msg, "chain": "ethereum"}, timeout=20)

def do_sign_sol():
    return call("POST", "actions/sign-message",
                {"message": sign_msg, "chain": "solana"}, timeout=20)

def do_manual_sign():
    return call("POST", "actions/x402/pay", {
        "requirement": {
            "scheme":            "exact",
            "network":           "eip155:8453",
            "maxAmountRequired": "10000",
            "resource":          DRY_URL,
            "description":       "Manual x402 sign test",
            "mimeType":          "application/json",
            "payTo":             "0x0000000000000000000000000000000000000000",
            "maxTimeoutSeconds": 300,
            "asset":             "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            "extra":             {"name": "USDC", "version": "2"},
        },
        "preferredChain": "evm",
        "preferredToken": "USDC",
        "dryRun": True,
    }, timeout=45)  # ← timeout besar untuk manual sign

def do_faucet():
    return call("POST", "actions/faucet-sol", {}, timeout=45)  # ← timeout besar

with ThreadPoolExecutor(max_workers=4) as pool:
    f_sevm = pool.submit(do_sign_evm)
    f_ssol = pool.submit(do_sign_sol)
    f_man  = pool.submit(do_manual_sign)
    f_fau  = pool.submit(do_faucet)
    sign_evm_r = f_sevm.result()
    sign_sol_r = f_ssol.result()
    manual_r   = f_man.result()
    faucet_r   = f_fau.result()

sign_evm_ok = ok(sign_evm_r) and ("signature" in sign_evm_r or "status" in sign_evm_r)
sign_sol_ok = ok(sign_sol_r) and ("signature" in sign_sol_r or "status" in sign_sol_r)
sign_ok     = sum([sign_evm_ok, sign_sol_ok])
results["sign_message"] = {"ethereum": {"ok": sign_evm_ok}, "solana": {"ok": sign_sol_ok}}

manual_ok = ok(manual_r)
results["x402_manual_sign"] = manual_r

results["faucet"] = faucet_r
faucet_icon   = "✅"
faucet_status = "N/A"
if ok(faucet_r):
    faucet_status = f"OK — {faucet_r.get('amount','?')} (remaining {faucet_r.get('remaining','?')}/3)"
    print(f"  Faucet : ✅ {faucet_status}")
    print(f"    TxHash: {faucet_r.get('txHash','N/A')}")
else:
    err_str = str(faucet_r.get("error", ""))
    if "429" in err_str or "rate" in err_str.lower():
        faucet_status = "rate_limited (3x/day habis)"; faucet_icon = "⏸"
        print(f"  Faucet : ⏸ {faucet_status}")
    else:
        faucet_status = f"FAIL: {faucet_r.get('error','?')[:40]}"; faucet_icon = "❌"
        results["errors"].append(f"faucet: {faucet_r.get('error','?')}")
        print(f"  Faucet : ❌ {faucet_status}")

print(f"  Sign EVM    : {'✅' if sign_evm_ok else '❌'}")
print(f"  Sign Solana : {'✅' if sign_sol_ok else '❌'}")
if not sign_evm_ok:
    results["errors"].append(f"sign_evm: {sign_evm_r.get('error','?')}")
if not sign_sol_ok:
    results["errors"].append(f"sign_sol: {sign_sol_r.get('error','?')}")

print(f"  Manual Sign : {'✅' if manual_ok else '❌'}" +
      (f" header={safe_get(manual_r,'usage','header',default='?')}" if manual_ok
       else f" {manual_r.get('error','?')[:50]}"))
if not manual_ok:
    results["errors"].append(f"x402_manual: {manual_r.get('error','?')}")

print(f"  Done in {time.time()-t0:.1f}s")
results["timings"]["sign_faucet"] = round(time.time() - t0, 2)

# =============================================================
# FASE 5 — x402 REAL PAYMENT (tiap 6 jam kalau saldo cukup)
# =============================================================
print("\n── FASE 5: x402 REAL PAYMENT ────────────────────────────")
real_pay_result = "skipped"
real_pay_amt    = "-"
real_pay_chain  = "-"
real_pay_time   = "-"
evm_usd = eth_base * prices["eth"] + usdc_base

# Real payment jalan tiap 6 jam (is_every_6h) dan saldo cukup
if is_every_6h and evm_usd > 0.05:
    t0   = time.time()
    real = call("POST", "actions/x402/fetch", {
        "url": DRY_URL, "method": "POST",
        "body": {"query": "AgentWallet cashback", "numResults": 1},
    }, timeout=30)
    results["x402_real_payment"] = real
    elapsed = time.time() - t0
    if ok(real):
        real_pay_result = "✅ OK"
        real_pay_amt    = safe_get(real, "payment", "amountFormatted", default="?")
        real_pay_chain  = safe_get(real, "payment", "chain", default="?")
        real_pay_time   = f"{real.get('duration','?')}ms"
        print(f"  ✅ {real_pay_amt} | {real_pay_chain} | "
              f"attempts={real.get('attempts','?')} | [{elapsed:.1f}s]")
    else:
        real_pay_result = "❌ FAIL"
        results["errors"].append(f"x402_real: {real.get('error','?')}")
        print(f"  ❌ {real.get('error','?')}")
else:
    reason = (f"next at jam {(current_hour // 6 + 1) * 6 % 24:02d}:00 UTC"
              if not is_every_6h else f"balance ${evm_usd:.3f} < $0.05")
    print(f"  ⏸ Skipped ({reason})")

# =============================================================
# FASE 6 — EVM TRANSFERS
# Siang (06-24 UTC): 9 chain
# Malam (00-06 UTC): Base saja (tetap jalan, tidak skip!)
# =============================================================
chain_count = len(EVM_CHAINS)
print(f"\n── FASE 6: EVM TRANSFERS ({chain_count} chain @ ${TRANSFER_USD} USDC) ──────────")
evm_rows = []
t0 = time.time()

if not evm_address:
    results["errors"].append("evm_transfer: no_evm_address")
    evm_rows = [("❌", n, "no_address") for n, _, _ in EVM_CHAINS]
    print("  ❌ No EVM address")
else:
    for chain_name, chain_id, asset in EVM_CHAINS:
        r = call("POST", "actions/transfer", {
            "to": evm_address, "amount": USDC_AMOUNT,
            "asset": asset, "chainId": chain_id,
        }, timeout=30)
        if ok(r):
            evm_ok  += 1
            detail   = fmt_addr(r.get("txHash","N/A"), 22)
            icon     = "✅"
            print(f"  ✅ {chain_name:<14}: {detail}")
        else:
            evm_fail += 1
            detail   = r.get("error","?")[:45]
            icon     = "❌"
            results["errors"].append(f"evm_{chain_name}: {detail}")
            print(f"  ❌ {chain_name:<14}: {detail}")
        evm_rows.append((icon, chain_name, detail))
        results["evm_transfers"].append({
            "chain": chain_name, "chainId": chain_id,
            "status": "OK" if ok(r) else "FAIL",
        })
        time.sleep(0.5)

    print(f"  → {evm_ok}/{chain_count} OK | {evm_fail} FAIL | {time.time()-t0:.1f}s")

results["timings"]["evm_transfers"] = round(time.time() - t0, 2)

# =============================================================
# FASE 7 — EVM CONTRACT CALL (simulate)
# =============================================================
print("\n── FASE 7: EVM CONTRACT CALL (simulate) ─────────────────")
cc_evm_icon = "⏸"
if evm_address:
    padded = evm_address[2:].lower().zfill(64)
    cc_evm = call("POST", "actions/contract-call", {
        "chainType": "ethereum",
        "to":        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "data":      "0x70a08231" + padded,
        "value":     "0",
        "chainId":   8453,
    }, timeout=30)
    results["evm_contract_call"] = cc_evm
    cc_evm_icon = "✅" if ok(cc_evm) else "ℹ️"
    msg_cc = cc_evm.get("txHash", cc_evm.get("error","?"))[:60]
    print(f"  {cc_evm_icon} {msg_cc}")
else:
    print("  ⏸ Skipped: no EVM address")

# =============================================================
# FASE 8 — SOL TRANSFERS
# Devnet selalu jalan (gratis), mainnet hanya kalau saldo cukup
# =============================================================
print(f"\n── FASE 8: SOL TRANSFERS (mainnet & devnet @ ${TRANSFER_USD}) ──")
sol_rows = []
sol_configs = [
    ("Solana Mainnet", "mainnet", TRANSFER_USD + 0.01),
    ("Solana Devnet",  "devnet",  0.0),
]
t0 = time.time()

if not sol_address:
    results["errors"].append("sol_transfer: no_sol_address")
    sol_rows = [("❌", n, "no_address") for n, _, _ in sol_configs]
    print("  ❌ No Solana address")
else:
    for name, network, min_usd in sol_configs:
        sol_usd = sol_main * prices["sol"]
        if network == "mainnet" and sol_usd < min_usd:
            skip_msg = f"low_bal ${sol_usd:.3f}"
            print(f"  ⏸ SKIP {name}: {skip_msg}")
            sol_rows.append(("⏸", name, skip_msg))
            results["sol_transfers"].append({"network": name, "status": "skipped_low_balance"})
            continue

        r = call("POST", "actions/transfer-solana", {
            "to": sol_address, "amount": SOL_AMOUNT,
            "asset": "sol", "network": network,
        }, timeout=30)
        if ok(r):
            sol_ok += 1
            detail  = fmt_addr(r.get("txHash","N/A"), 22)
            icon    = "✅"
            print(f"  ✅ {name}: {detail}")
        else:
            sol_fail += 1
            detail  = r.get("error","?")[:45]
            icon    = "❌"
            results["errors"].append(f"sol_{name}: {detail}")
            print(f"  ❌ {name}: {detail}")
        sol_rows.append((icon, name, detail))
        results["sol_transfers"].append({
            "network": name, "status": "OK" if ok(r) else "FAIL",
        })
        time.sleep(0.5)

    print(f"  → {sol_ok}/2 OK | {time.time()-t0:.1f}s")

results["timings"]["sol_transfers"] = round(time.time() - t0, 2)

# =============================================================
# FASE 9 — SOL CONTRACT CALL (devnet, simulate)
# =============================================================
print("\n── FASE 9: SOL CONTRACT CALL (simulate, devnet) ─────────")
cc_sol_icon = "⏸"
if sol_address:
    cc_sol = call("POST", "actions/contract-call", {
        "chainType": "solana",
        "instructions": [{
            "programId": "11111111111111111111111111111111",
            "accounts": [
                {"pubkey": sol_address, "isSigner": True,  "isWritable": True},
                {"pubkey": sol_address, "isSigner": False, "isWritable": True},
            ],
            "data": "AAAAAAAAAAA=",
        }],
        "network": "devnet",
    }, timeout=30)
    results["sol_contract_call"] = cc_sol
    cc_sol_icon = "✅" if ok(cc_sol) else "ℹ️"
    msg_cs = cc_sol.get("txHash", cc_sol.get("error","?"))[:60]
    print(f"  {cc_sol_icon} {msg_cs}")
else:
    print("  ⏸ Skipped: no Solana address")

# =============================================================
# FASE 10 — FEEDBACK (tiap 6 jam)
# =============================================================
print("\n── FASE 10: FEEDBACK ────────────────────────────────────")
feedback_id     = "-"
feedback_status = "skipped"

if is_every_6h:
    fb = call("POST", "feedback", {
        "category": "other",
        "message": (
            f"Run {current_hour:02d}:00 UTC | Mode={mode_str} | "
            f"x402DR={dry_ok}/{len(X402_NETWORKS)} | "
            f"Sign={sign_ok}/2 | EVM={evm_ok}/{chain_count} | SOL={sol_ok}/2 | "
            f"Rank=#{rank} | Streak={streak}d | Pts={ref_pts} | Err={len(results['errors'])}"
        ),
        "context": {
            "hour": current_hour, "rank": rank, "streak": streak,
            "dry_ok": dry_ok, "sign_ok": sign_ok,
            "evm_ok": evm_ok, "sol_ok": sol_ok,
            "points": ref_pts, "tier": ref_tier,
            "errors": len(results["errors"]),
            "mode": mode_str,
        },
    }, timeout=20)
    results["feedback"] = fb
    if ok(fb):
        feedback_id     = safe_get(fb, "data", "id", default="N/A")
        feedback_status = "✅ OK"
        print(f"  ✅ Submitted | ID: {feedback_id}")
    else:
        feedback_status = f"❌ {fb.get('error','?')}"
        results["errors"].append(f"feedback: {fb.get('error','?')}")
        print(f"  ❌ {fb.get('error','?')}")
else:
    nxt = 6 - (current_hour % 6)
    print(f"  ⏸ Next in {nxt}h (jam {(current_hour+nxt)%24:02d}:00 UTC)")

# =============================================================
# FASE 11 — TELEGRAM
# =============================================================
print("\n── FASE 11: TELEGRAM ────────────────────────────────────")

overall_ok  = connected and dry_ok >= 10 and sign_ok == 2
health_icon = "✅ HEALTHY" if overall_ok else "⚠️ CHECK LOGS"
total_time  = round(time.time() - t_start, 1)

evm_icons = "".join(ic for ic, _, _ in evm_rows) or "⏸"
sol_icons = "".join(ic for ic, _, _ in sol_rows) or "⏸"

evm_table = "".join(f"  {ic} {nm:<14} {dt[:22]}\n" for ic, nm, dt in evm_rows) or "  (no data)\n"
sol_table = "".join(f"  {ic} {nm} {dt[:22]}\n"     for ic, nm, dt in sol_rows) or "  (no data)\n"

x402_table = "".join(
    f"  {'✅' if 'FAIL' not in str(e['cost']) else '❌'} "
    f"{e['network']:<24}: {e['cost']}\n"
    for e in results["x402_dry_runs"]
) or "  (no data)\n"

err_lines = "\n".join(f"  {i}. {e[:55]}"
                      for i, e in enumerate(results["errors"][:6], 1))
if len(results["errors"]) > 6:
    err_lines += f"\n  ... +{len(results['errors'])-6} more"
err_summary = err_lines or "  (none)"

if is_midnight:
    # ── MIDNIGHT: Laporan harian penuh ───────────────────────
    tg_msg = (
        f"<b>📊 AgentWallet — Daily Report</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"👤 <b>User</b>    : {username}\n"
        f"🏆 <b>Rank</b>    : #{rank}\n"
        f"🎯 <b>Tier</b>    : {ref_tier} ({ref_pts} pts | {ref_count} refs)\n"
        f"🔥 <b>Streak</b>  : {streak} hari\n"
        f"📦 <b>Volume</b>  : {volume}\n"
        f"⏱  <b>Runtime</b> : {total_time}s\n"
        f"\n"
        f"💰 <b>SALDO</b>\n"
        f"  SOL  : {sol_main:.6f} (~${sol_main*prices['sol']:.4f})\n"
        f"  ETH  : {eth_base:.6f} (~${eth_base*prices['eth']:.4f})\n"
        f"  USDC : {usdc_base:.4f}\n"
        f"\n"
        f"🌐 <b>NETWORK</b>\n"
        f"  Pulse    : {'✅' if pulse_ok else '❌'} | "
        f"Agents: {pulse.get('activeAgents','N/A')}\n"
        f"  Activity : {event_count} events\n"
        f"  Policy   : {'✅' if ok(policy_upd) else '❌'} ({mode_label})\n"
        f"\n"
        f"🧪 <b>x402 DRY RUN</b> ({dry_ok}/{len(X402_NETWORKS)} OK)\n"
        f"{x402_table}"
        f"\n"
        f"💸 <b>x402 REAL PAY</b> : {real_pay_result} {real_pay_amt} "
        f"[{real_pay_chain}] {real_pay_time}\n"
        f"🔏 <b>x402 MANUAL</b>  : {'✅ OK' if manual_ok else '❌ FAIL'}\n"
        f"\n"
        f"✍️  <b>SIGN</b> : EVM={'✅' if sign_evm_ok else '❌'} | "
        f"SOL={'✅' if sign_sol_ok else '❌'}\n"
        f"🚰 <b>Faucet</b>  : {faucet_icon} {faucet_status}\n"
        f"\n"
        f"💸 <b>EVM TRANSFER</b> ({evm_ok}/{chain_count})\n"
        f"{evm_table}"
        f"🔧 EVM Contract : {cc_evm_icon}\n"
        f"\n"
        f"💸 <b>SOL TRANSFER</b> ({sol_ok}/2)\n"
        f"{sol_table}"
        f"🔧 SOL Contract : {cc_sol_icon}\n"
        f"\n"
        f"💬 <b>Feedback</b> : {feedback_status} | ID: {feedback_id}\n"
        f"\n"
        f"🪙 <b>WALLET</b>\n"
        f"  EVM    : {fmt_addr(evm_address, 22)}\n"
        f"  Solana : {fmt_addr(sol_address, 22)}\n"
        f"  Tier   : {wallet_tier}\n"
        f"  Ref    : https://frames.ag/connect?ref={username}\n"
        f"\n"
        f"❗ <b>ERRORS</b> ({len(results['errors'])} total)\n"
        f"{err_summary}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🏁 <b>{health_icon}</b> | {now.strftime('%Y-%m-%d %H:%M')} UTC"
    )
else:
    # ── HOURLY RINGKASAN ─────────────────────────────────────
    tg_msg = (
        f"{'✅' if overall_ok else '⚠️'} <b>AgentWallet</b> "
        f"{current_hour:02d}:00 UTC [{mode_str}]\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"👤 {username} | #{rank} | {ref_tier}({ref_pts}pts) | 🔥{streak}d\n"
        f"💰 SOL ${sol_main*prices['sol']:.3f} | "
        f"ETH ${eth_base*prices['eth']:.3f} | USDC ${usdc_base:.2f}\n"
        f"⏱ {total_time}s\n"
        f"\n"
        f"🧪 x402 DryRun={dry_ok}/{len(X402_NETWORKS)} | "
        f"Pay={real_pay_result} {real_pay_amt} | "
        f"Manual={'✅' if manual_ok else '❌'}\n"
        f"✍️  Sign EVM={'✅' if sign_evm_ok else '❌'} "
        f"SOL={'✅' if sign_sol_ok else '❌'} | "
        f"🚰 Faucet={faucet_icon}\n"
        f"\n"
        f"💸 <b>EVM ({evm_ok}/{chain_count})</b>\n"
        f"{evm_table}"
        f"🔧 EVM CC={cc_evm_icon}\n"
        f"\n"
        f"💸 <b>SOL ({sol_ok}/2)</b>\n"
        f"{sol_table}"
        f"🔧 SOL CC={cc_sol_icon}\n"
        f"\n"
        f"🌐 Pulse={'✅' if pulse_ok else '❌'} | "
        f"Policy={'✅' if ok(policy_upd) else '❌'} | "
        f"Activity={event_count} | Err={len(results['errors'])}\n"
        f"💬 Feedback: {feedback_status[:30]}\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"🏁 {health_icon} | {now.strftime('%H:%M:%S')} UTC"
    )

sent = send_telegram(tg_msg)
print(f"  {'✅ Sent OK' if sent else '⏸ No token' if not telegram_token else '❌ FAIL'}")

# =============================================================
# SAVE
# =============================================================
print("\n── SAVE RESULTS ─────────────────────────────────────────")
results["timings"]["total"] = round(time.time() - t_start, 2)
try:
    with open("test_results.json", "w") as f:
        json.dump(results, f, indent=2, default=str)
    print("  ✅ test_results.json saved")
except Exception as e:
    print(f"  ❌ {e}")

# =============================================================
# FINAL SUMMARY
# =============================================================
err_cnt    = len(results["errors"])
total_time = results["timings"]["total"]
print("\n" + "=" * 65)
print(f"  SELESAI — {total_time}s | {now.strftime('%Y-%m-%d %H:%M:%S')} UTC")
print(f"  {'─'*62}")
print(f"  Mode          : {mode_str}")
print(f"  Connection    : {results['connection']['status']}")
print(f"  Rank          : #{rank} | Streak={streak}d | {ref_pts}pts | {ref_tier}")
print(f"  Policy        : {'OK' if ok(policy_upd) else 'FAIL'} ({mode_label})")
print(f"  Activity      : {event_count} events")
print(f"  x402 DryRuns  : {dry_ok}/{len(X402_NETWORKS)} OK")
print(f"  x402 RealPay  : {real_pay_result} ({real_pay_amt})")
print(f"  x402 Manual   : {'OK' if manual_ok else 'FAIL'}")
print(f"  Sign          : {sign_ok}/2 OK")
print(f"  Faucet        : {faucet_status[:50]}")
print(f"  EVM Transfers : {evm_ok}/{chain_count} OK | {evm_fail} FAIL")
print(f"  EVM Contract  : {cc_evm_icon}")
print(f"  SOL Transfers : {sol_ok}/2 OK | {sol_fail} FAIL")
print(f"  SOL Contract  : {cc_sol_icon}")
print(f"  Feedback      : {feedback_status}")
print(f"  Telegram      : {'Sent ✅' if sent else 'Not sent'}")
print(f"  Errors        : {err_cnt}")
print(f"  {'─'*62}")
print(f"  ⏱  TIMINGS:")
for k, v in results["timings"].items():
    print(f"     {k:<28}: {v}s")
print(f"  {'─'*62}")
print(f"  STATUS : {'✅  ALL GOOD' if err_cnt == 0 and overall_ok else '⚠️   CHECK LOGS'}")
print("=" * 65)
