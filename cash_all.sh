#!/bin/bash
# =============================================================
# AgentWallet — ALL Networks + ALL Tokens v4.0
# Jaringan: Solana (CASH/USDC/USDT), Solana Devnet (USDC),
#           Base (USDC/USDT), Base Sepolia (USDC),
#           Ethereum (USDC/USDT), Optimism, Polygon,
#           Arbitrum, BNB, Gnosis, Sepolia
# Jeda: 60 detik antar request
# =============================================================

TOKEN="${AGENTWALLET_API_TOKEN}"
USER="${AGENTWALLET_USERNAME}"
TG_TOKEN="${TELEGRAM_BOT_TOKEN}"
TG_CHAT="${TELEGRAM_CHAT_ID}"

DELAY=60

if [[ -z "$TOKEN" || -z "$USER" ]]; then
  echo "Missing AGENTWALLET_API_TOKEN or AGENTWALLET_USERNAME"
  exit 1
fi

BASE="https://frames.ag/api/wallets/${USER}/actions/x402/fetch"
NOW=$(date -u '+%Y-%m-%d %H:%M:%S')
TOTAL_OK=0
TOTAL_FAIL=0
TOTAL=0
LOG=""
break_script=0

echo "============================================================"
echo "  AgentWallet - ALL Networks + ALL Tokens v4.0"
echo "  Time : ${NOW} UTC | User: ${USER}"
echo "  Jeda : ${DELAY}s"
echo "============================================================"

# =============================================================
# HELPER: kirim notif Telegram
# =============================================================
send_tg_msg() {
  local TEXT="$1"
  if [[ -z "$TG_TOKEN" || -z "$TG_CHAT" ]]; then return; fi
  TG_TOKEN="$TG_TOKEN" TG_CHAT="$TG_CHAT" TG_TEXT="$TEXT" python3 -c "
import os, json, urllib.request
token = os.environ['TG_TOKEN']
chat  = os.environ['TG_CHAT']
text  = os.environ['TG_TEXT']
data  = json.dumps({'chat_id': chat, 'text': text}).encode('utf-8')
req   = urllib.request.Request(
    'https://api.telegram.org/bot' + token + '/sendMessage',
    data=data,
    headers={'Content-Type': 'application/json; charset=utf-8'})
try:
    urllib.request.urlopen(req, timeout=15)
    print('  TG: sent ok')
except Exception as e:
    print('  TG: error', e)
"
}

# =============================================================
# CEK CASH BALANCE WALLET REWARD
# =============================================================
REWARD_WALLET="CQi9MGyFFR21dsPtHuuQTRfaeu2dT9sS1jTb855ZiicD"
CASH_MINT="CASHx9KJUStyftLFWGvEVf59SGeG9sh5FfcnZMVPCASH"
RPC="https://api.mainnet-beta.solana.com"
CACHE_FILE="/tmp/agentwallet_reward_bal.txt"

echo ""
echo "Cek CASH balance wallet reward..."
RPC_RESP=$(curl -s -X POST "$RPC" \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenAccountsByOwner\",\"params\":[\"${REWARD_WALLET}\",{\"mint\":\"${CASH_MINT}\"},{\"encoding\":\"jsonParsed\"}]}")

CASH_BAL=$(echo "$RPC_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    accounts = d.get('result', {}).get('value', [])
    print(accounts[0]['account']['data']['parsed']['info']['tokenAmount']['uiAmountString'] if accounts else '0')
except: print('0')
" 2>/dev/null)
CASH_BAL="${CASH_BAL:-0}"
LAST_BAL=$(cat "$CACHE_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "  Sebelumnya : ${LAST_BAL} CASH | Sekarang : ${CASH_BAL} CASH"

MIN_CASH="0.05"
IS_ENOUGH=$(python3 -c "print('yes' if ${CASH_BAL} >= ${MIN_CASH} else 'no')" 2>/dev/null || echo "no")
if [[ "$IS_ENOUGH" != "yes" ]]; then
  echo "  SKIP: CASH ${CASH_BAL} < ${MIN_CASH}"
  send_tg_msg "AgentWallet SKIP
CASH reward ${CASH_BAL} < ${MIN_CASH} — belum cukup
User: ${USER} | ${NOW} UTC"
  exit 0
fi
echo "  CASH cukup! Lanjut..."

# =============================================================
# CEK BALANCE SEMUA WALLET (Solana + EVM)
# =============================================================
OWN_CACHE="/tmp/agentwallet_own_cash.txt"
echo ""
echo "Cek balance semua wallet..."
ALL_BAL=$(curl -s "https://frames.ag/api/wallets/${USER}/balances" \
  -H "Authorization: Bearer ${TOKEN}")

# Parsing CASH (Solana mainnet)
OWN_CASH=$(echo "$ALL_BAL" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    for w in d.get('solanaWallets',[]):
        for b in w.get('balances',[]):
            if b.get('asset','').upper()=='CASH' and 'devnet' not in b.get('chain','').lower():
                print(b.get('tokenAmount',{}).get('uiAmountString') or '0'); import sys; sys.exit()
    print('0')
except: print('0')
" 2>/dev/null | tr -d '[:space:]')
OWN_CASH="${OWN_CASH:-0}"

# Parsing USDC Solana
SOL_USDC=$(echo "$ALL_BAL" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    for w in d.get('solanaWallets',[]):
        for b in w.get('balances',[]):
            if b.get('asset','').upper()=='USDC' and 'devnet' not in b.get('chain','').lower():
                print(b.get('tokenAmount',{}).get('uiAmountString') or '0'); import sys; sys.exit()
    print('0')
except: print('0')
" 2>/dev/null | tr -d '[:space:]')

# Parsing USDC Base
BASE_USDC=$(echo "$ALL_BAL" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    for w in d.get('evmWallets',[]):
        for b in w.get('balances',[]):
            chain=b.get('chain','').lower()
            if b.get('asset','').upper()=='USDC' and 'base' in chain and 'sepolia' not in chain:
                print(b.get('tokenAmount',{}).get('uiAmountString') or '0'); import sys; sys.exit()
    print('0')
except: print('0')
" 2>/dev/null | tr -d '[:space:]')

echo "  CASH (Solana)  : ${OWN_CASH}"
echo "  USDC (Solana)  : ${SOL_USDC}"
echo "  USDC (Base)    : ${BASE_USDC}"

OWN_LAST=$(cat "$OWN_CACHE" 2>/dev/null | tr -d '[:space:]' || echo "0")
OWN_HIGHER=$(python3 -c "print('yes' if ${OWN_CASH} > ${OWN_LAST:-0} else 'no')" 2>/dev/null || echo "no")
if [[ "$OWN_HIGHER" == "yes" && "$OWN_LAST" != "0" && -n "$OWN_LAST" ]]; then
  DIFF=$(python3 -c "print(f'{${OWN_CASH}-${OWN_LAST:-0}:.6f}')" 2>/dev/null || echo "0")
  send_tg_msg "CASH MASUK ke wallet! +${DIFF} CASH | Balance: ${OWN_CASH} CASH | ${NOW} UTC"
fi
echo "$OWN_CASH" > "$OWN_CACHE"
OWN_CASH_START="$OWN_CASH"

# =============================================================
# UPDATE POLICY — izinkan semua chain & token
# =============================================================
echo ""
echo "Update policy..."
POL=$(curl -s -X PATCH "https://frames.ag/api/wallets/${USER}/policy" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"max_per_tx_usd":"100","allow_chains":["solana","base","ethereum","optimism","polygon","arbitrum","bsc","gnosis","sepolia","baseSepolia"]}')
POL_OK=$(echo "$POL" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('OK' if d.get('success') else 'FAIL')" 2>/dev/null || echo "FAIL")
echo "  Policy: ${POL_OK}"

# =============================================================
# HELPER: fungsi pay utama
# =============================================================
pay() {
  local NAME="$1"
  local PAYLOAD="$2"
  TOTAL=$((TOTAL + 1))
  echo ""
  echo "[${TOTAL}] ${NAME}"

  # Dry run
  DRY=$(curl -s -X POST "$BASE" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD//__DRYRUN__/,\"dryRun\":true}")

  DRY_STATUS=$(echo "$DRY" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    p=d.get('payment',{})
    amt=p.get('amountFormatted','?') if isinstance(p,dict) else '?'
    raw=str(p.get('amountRaw','0')) if isinstance(p,dict) else '0'
    pol=str(p.get('policyAllowed','true')) if isinstance(p,dict) else 'true'
    chain=p.get('chain','?') if isinstance(p,dict) else '?'
    print(f'{amt}|{raw}|{pol}|{chain}')
except: print('?|0|true|?')
" 2>/dev/null)
  AMT=$(echo "$DRY_STATUS" | cut -d'|' -f1)
  AMT_RAW=$(echo "$DRY_STATUS" | cut -d'|' -f2)
  POLICY=$(echo "$DRY_STATUS" | cut -d'|' -f3)
  CHAIN=$(echo "$DRY_STATUS" | cut -d'|' -f4)
  echo "  Dry  : ${AMT} | chain=${CHAIN} | policy=${POLICY}"

  # Cek balance
  if [[ -n "$AMT_RAW" && "$AMT_RAW" != "0" ]]; then
    NEEDED=$(python3 -c "print(f'{int(\"${AMT_RAW}\")/1000000:.6f}')" 2>/dev/null || echo "0")
    ENOUGH=$(python3 -c "print('yes' if float('${OWN_CASH:-0}') >= float('${NEEDED:-0}') else 'no')" 2>/dev/null || echo "yes")
    if [[ "$ENOUGH" != "yes" ]]; then
      echo "  STOP: saldo habis (${OWN_CASH} < ${NEEDED})"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      send_tg_msg "SALDO HABIS — Stop!
Sisa: ${OWN_CASH} | Butuh: ${NEEDED}
Progress: ${TOTAL_OK}OK / ${TOTAL_FAIL}FAIL / ${TOTAL}total
Service: ${NAME} | ${NOW} UTC"
      break_script=1
      return 99
    fi
  fi

  if [[ "$POLICY" == "False" || "$POLICY" == "false" ]]; then
    echo "  SKIP: policy denied"
    LOG="${LOG}\n⏸ ${NAME}: policy denied"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    return
  fi

  sleep 3

  # Eksekusi
  RESULT=$(curl -s -X POST "$BASE" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD//__DRYRUN__/}")

  RESULT_STATUS=$(echo "$RESULT" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    paid=d.get('paid',False); dry=d.get('dryRun',False); suc=d.get('success',False)
    p=d.get('payment',{})
    amt=p.get('amountFormatted','?') if isinstance(p,dict) else '?'
    chain=p.get('chain','?') if isinstance(p,dict) else '?'
    r=d.get('response',{}); b=r.get('body',{}) if isinstance(r,dict) else {}
    err=d.get('error') or b.get('error') or b.get('message') or ''
    if paid or (dry and suc): print(f'OK|{amt}|{chain}|')
    else: print(f'FAIL||{chain}|{str(err)[:120]}')
except Exception as e: print(f'FAIL|||{e}')
" 2>/dev/null)

  S=$(echo "$RESULT_STATUS" | cut -d'|' -f1)
  AMT_PAID=$(echo "$RESULT_STATUS" | cut -d'|' -f2)
  CHAIN_PAID=$(echo "$RESULT_STATUS" | cut -d'|' -f3)
  ERR=$(echo "$RESULT_STATUS" | cut -d'|' -f4)

  if [[ "$S" == "OK" ]]; then
    echo "  OK   : ${AMT_PAID} @ ${CHAIN_PAID}"
    LOG="${LOG}\n✅ ${NAME}: ${AMT_PAID} @ ${CHAIN_PAID}"
    TOTAL_OK=$((TOTAL_OK + 1))
    if [[ -n "$AMT_RAW" && "$AMT_RAW" != "0" ]]; then
      OWN_CASH=$(python3 -c "print(f'{float(\"${OWN_CASH:-0}\")-${AMT_RAW:-0}/1000000:.6f}')" 2>/dev/null || echo "${OWN_CASH:-0}")
      echo "$OWN_CASH" > "$OWN_CACHE"
    fi
    # Feedback
    FB=$(curl -s -X POST "https://frames.ag/api/wallets/${USER}/feedback" \
      -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
      -d "{\"category\":\"other\",\"message\":\"OK: ${NAME} | ${AMT_PAID} | ${CHAIN_PAID}\",\"context\":{\"service\":\"${NAME}\",\"chain\":\"${CHAIN_PAID}\"}}")
    FB_ID=$(echo "$FB" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('data',{}).get('id','?'))" 2>/dev/null || echo "?")
    echo "  Feedback: ${FB_ID}"
    send_tg_msg "✅ [${TOTAL}] ${NAME}
Bayar   : ${AMT_PAID}
Chain   : ${CHAIN_PAID}
Sisa    : ${OWN_CASH} CASH
Progress: ${TOTAL_OK}OK/${TOTAL_FAIL}FAIL/${TOTAL}total
Waktu   : $(date -u '+%H:%M:%S') UTC"
  else
    echo "  FAIL : ${ERR:0:120}"
    LOG="${LOG}\n❌ ${NAME}: ${ERR:0:80}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    send_tg_msg "❌ [${TOTAL}] ${NAME}
Error  : ${ERR:0:150}
Chain  : ${CHAIN_PAID}
Sisa   : ${OWN_CASH} CASH
Waktu  : $(date -u '+%H:%M:%S') UTC"
  fi
}

# =============================================================
# FASE AWAL — Stats, Sign, Faucet, Transfer
# =============================================================
echo ""
echo "══ FASE AWAL ══════════════════════════════════════════════"

STATS=$(curl -s "https://frames.ag/api/wallets/${USER}/stats" -H "Authorization: Bearer ${TOKEN}")
REFS=$(curl -s "https://frames.ag/api/wallets/${USER}/referrals" -H "Authorization: Bearer ${TOKEN}")
PULSE=$(curl -s "https://frames.ag/api/network/pulse")
RANK=$(echo "$STATS" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('rank','?'))" 2>/dev/null)
STREAK=$(echo "$STATS" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('streakDays','?'))" 2>/dev/null)
REF_PTS=$(echo "$REFS" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('airdropPoints','?'))" 2>/dev/null)
REF_CNT=$(echo "$REFS" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('referralCount','?'))" 2>/dev/null)
REF_TIER=$(echo "$REFS" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tier','?'))" 2>/dev/null)
AGENTS=$(echo "$PULSE" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('activeAgents','?'))" 2>/dev/null)
echo "  Rank: #${RANK} | Streak: ${STREAK}d | Pts: ${REF_PTS} | Refs: ${REF_CNT} | Tier: ${REF_TIER}"
echo "  Active Agents: ${AGENTS}"

# Sign EVM
MSG_SIGN="AgentWallet | ${NOW} | ${USER}"
SIGN_EVM=$(curl -s -X POST "https://frames.ag/api/wallets/${USER}/actions/sign-message" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d "{\"message\":\"${MSG_SIGN}\",\"chain\":\"ethereum\"}")
SIGN_EVM_OK=$(echo "$SIGN_EVM" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('OK' if d.get('signature') or d.get('status') else 'FAIL')" 2>/dev/null)
echo "  Sign EVM    : ${SIGN_EVM_OK}"; sleep 2

# Sign Solana
SIGN_SOL=$(curl -s -X POST "https://frames.ag/api/wallets/${USER}/actions/sign-message" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d "{\"message\":\"${MSG_SIGN}\",\"chain\":\"solana\"}")
SIGN_SOL_OK=$(echo "$SIGN_SOL" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('OK' if d.get('signature') or d.get('status') else 'FAIL')" 2>/dev/null)
echo "  Sign Solana : ${SIGN_SOL_OK}"; sleep 2

# Faucet SOL Devnet
FAUCET=$(curl -s -X POST "https://frames.ag/api/wallets/${USER}/actions/faucet-sol" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d '{}')
FAUCET_AMT=$(echo "$FAUCET" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('amount','?'))" 2>/dev/null)
FAUCET_REM=$(echo "$FAUCET" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('remaining','?'))" 2>/dev/null)
echo "  Faucet SOL  : ${FAUCET_AMT} | Sisa: ${FAUCET_REM}/3"; sleep 2

# Transfer SOL devnet ke diri sendiri
SOL_ADDR=$(curl -s "https://frames.ag/api/wallets/${USER}" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('solanaAddress',''))" 2>/dev/null)
EVM_ADDR=$(curl -s "https://frames.ag/api/wallets/${USER}" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('evmAddress',''))" 2>/dev/null)
if [[ -n "$SOL_ADDR" ]]; then
  TX_SOL=$(curl -s -X POST "https://frames.ag/api/wallets/${USER}/actions/transfer-solana" \
    -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
    -d "{\"to\":\"${SOL_ADDR}\",\"amount\":\"1000000\",\"asset\":\"sol\",\"network\":\"devnet\"}")
  TX_SOL_S=$(echo "$TX_SOL" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('status','FAIL'))" 2>/dev/null)
  echo "  Transfer SOL devnet: ${TX_SOL_S}"; sleep 2
fi

# Manual x402 sign dry
MANUAL=$(curl -s -X POST "https://frames.ag/api/wallets/${USER}/actions/x402/pay" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"requirement":{"scheme":"exact","network":"eip155:8453","maxAmountRequired":"10000","resource":"https://registry.frames.ag/api/service/exa/api/search","description":"Manual sign test","mimeType":"application/json","payTo":"0x0000000000000000000000000000000000000000","maxTimeoutSeconds":300,"asset":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","extra":{"name":"USDC","version":"2"}},"preferredChain":"evm","preferredToken":"USDC","dryRun":true}')
MANUAL_OK=$(echo "$MANUAL" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('OK' if d.get('success') else 'FAIL')" 2>/dev/null)
echo "  Manual x402 dry: ${MANUAL_OK}"; sleep 2

send_tg_msg "AgentWallet Run Dimulai — v4.0
User    : ${USER} | ${NOW} UTC
Rank    : #${RANK} | Streak: ${STREAK}d | Pts: ${REF_PTS}
Tier    : ${REF_TIER} | Refs: ${REF_CNT} | Agents: ${AGENTS}
Sign EVM: ${SIGN_EVM_OK} | Sign SOL: ${SIGN_SOL_OK}
Faucet  : ${FAUCET_AMT} (sisa ${FAUCET_REM}/3)
Balance : CASH=${OWN_CASH} | USDC_SOL=${SOL_USDC} | USDC_BASE=${BASE_USDC}
Mulai x402 payments..."

echo ""
echo "══ X402 PAYMENTS — ALL NETWORKS ═══════════════════════════"

# =============================================================
# ── SOLANA MAINNET — CASH ─────────────────────────────────────
# =============================================================
echo "── SOLANA / CASH ────────────────────────────────────────"

pay "Jupiter: Price [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/jupiter/api/price","method":"POST","body":{"ids":"So11111111111111111111111111111111111111112"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Jupiter: Tokens [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/jupiter/api/tokens","method":"POST","body":{"query":"USDC"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "CoinGecko: Price [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"bitcoin,solana,ethereum"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "CoinGecko: Search [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/search","method":"POST","body":{"query":"solana"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "CoinGecko: Markets [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/markets","method":"POST","body":{"vs_currency":"usd","ids":"bitcoin,ethereum,solana"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Twitter: Search Tweets [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/search-tweets","method":"POST","body":{"query":"AI agents","queryType":"Latest","cursor":""},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"AgentWallet x402","numResults":3},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Answer [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/answer","method":"POST","body":{"query":"What is AgentWallet?"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "OpenRouter: GPT-4o [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/openrouter/v1/chat/completions","method":"POST","body":{"model":"openai/gpt-4o","messages":[{"role":"user","content":"Explain quantum computing"}]},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AI Gen: Minimax Music [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"minimax/music-01","prompt":"An upbeat electronic music track"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AI Gen: DALL-E 3 [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"openai/dall-e-3","prompt":"A beautiful sunset over the ocean"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AI Gen: Veo 3 Fast [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/veo-3-fast","prompt":"A futuristic city with flying cars","duration":8,"resolution":"720p"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AI Gen: Sora 2 [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"openai/sora-2","prompt":"A stunning sunset over a futuristic city","duration":5,"resolution":"720p"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AI Gen: Veo 3 [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/veo-3","prompt":"A futuristic city neon lights","duration":8,"resolution":"1080p"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Wordspace Agent [SOL/CASH]" \
  '{"url":"https://registry.frames.ag/api/service/wordspace/api/invoke","method":"POST","body":{"prompt":"Write a story about AI agents"},"preferredChain":"solana","preferredToken":"CASH"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── SOLANA MAINNET — USDC ─────────────────────────────────────
# =============================================================
echo "── SOLANA / USDC ────────────────────────────────────────"

pay "CoinGecko: Price [SOL/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"bitcoin,solana"},"preferredChain":"solana","preferredToken":"USDC"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [SOL/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"blockchain AI agents 2025","numResults":3},"preferredChain":"solana","preferredToken":"USDC"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Twitter: Trends [SOL/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/trends","method":"POST","body":{"woeid":1,"count":10},"preferredChain":"solana","preferredToken":"USDC"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "OpenRouter: Claude [SOL/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/openrouter/v1/chat/completions","method":"POST","body":{"model":"anthropic/claude-3-haiku","messages":[{"role":"user","content":"What is x402 payment protocol?"}]},"preferredChain":"solana","preferredToken":"USDC"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AgentMail: Create Inbox [SOL/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/agentmail/api/inbox/create","method":"POST","body":{"username":"myagent2","display_name":"My Agent 2"},"preferredChain":"solana","preferredToken":"USDC"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── SOLANA MAINNET — USDT ─────────────────────────────────────
# =============================================================
echo "── SOLANA / USDT ────────────────────────────────────────"

pay "CoinGecko: Token Info [SOL/USDT]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/token-info","method":"POST","body":{"id":"ethereum"},"preferredChain":"solana","preferredToken":"USDT"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Find Similar [SOL/USDT]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/find-similar","method":"POST","body":{"url":"https://frames.ag","numResults":3},"preferredChain":"solana","preferredToken":"USDT"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Jupiter: Price [SOL/USDT]" \
  '{"url":"https://registry.frames.ag/api/service/jupiter/api/price","method":"POST","body":{"ids":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"},"preferredChain":"solana","preferredToken":"USDT"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── SOLANA DEVNET — USDC ──────────────────────────────────────
# =============================================================
echo "── SOLANA DEVNET / USDC ─────────────────────────────────"

pay "CoinGecko: Price [SOL-DEV/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"bitcoin"},"preferredChain":"solana","preferredToken":"USDC","preferredChainId":"solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [SOL-DEV/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Solana devnet testing","numResults":2},"preferredChain":"solana","preferredToken":"USDC","preferredChainId":"solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── BASE MAINNET — USDC ───────────────────────────────────────
# =============================================================
echo "── BASE / USDC ──────────────────────────────────────────"

pay "CoinGecko: Price [BASE/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"bitcoin,ethereum"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [BASE/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Base blockchain ecosystem 2025","numResults":3},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Twitter: Search [BASE/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/search-tweets","method":"POST","body":{"query":"Base L2 blockchain","queryType":"Latest","cursor":""},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "OpenRouter: GPT-4o [BASE/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/openrouter/v1/chat/completions","method":"POST","body":{"model":"openai/gpt-4o","messages":[{"role":"user","content":"Explain Base blockchain"}]},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AgentMail: Send Email [BASE/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/agentmail/api/send","method":"POST","body":{"inbox_id":"test","to":[{"email":"test@example.com"}],"subject":"Hello from Base","text":"Test from Base network"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "AI Gen: DALL-E 3 [BASE/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"openai/dall-e-3","prompt":"A futuristic base chain ecosystem"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── BASE MAINNET — USDT ───────────────────────────────────────
# =============================================================
echo "── BASE / USDT ──────────────────────────────────────────"

pay "CoinGecko: Markets [BASE/USDT]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/markets","method":"POST","body":{"vs_currency":"usd","ids":"bitcoin,ethereum"},"preferredChain":"evm","preferredToken":"USDT","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Answer [BASE/USDT]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/answer","method":"POST","body":{"query":"What is x402 protocol?"},"preferredChain":"evm","preferredToken":"USDT","preferredChainId":8453}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── BASE SEPOLIA — USDC (testnet) ─────────────────────────────
# =============================================================
echo "── BASE SEPOLIA / USDC (testnet) ────────────────────────"

pay "CoinGecko: Price [BASE-SEP/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"bitcoin"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":84532}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [BASE-SEP/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Base Sepolia testnet","numResults":2},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":84532}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── ETHEREUM MAINNET — USDC ───────────────────────────────────
# =============================================================
echo "── ETHEREUM / USDC ──────────────────────────────────────"

pay "CoinGecko: Price [ETH/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"ethereum,bitcoin"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":1}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [ETH/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Ethereum L2 scaling solutions","numResults":3},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":1}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "OpenRouter: GPT-4o [ETH/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/openrouter/v1/chat/completions","method":"POST","body":{"model":"openai/gpt-4o","messages":[{"role":"user","content":"Explain Ethereum EIP-1559"}]},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":1}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── ETHEREUM MAINNET — USDT ───────────────────────────────────
# =============================================================
echo "── ETHEREUM / USDT ──────────────────────────────────────"

pay "CoinGecko: Token Info [ETH/USDT]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/token-info","method":"POST","body":{"id":"ethereum"},"preferredChain":"evm","preferredToken":"USDT","preferredChainId":1}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Twitter: User Tweets [ETH/USDT]" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/user-tweets","method":"POST","body":{"userName":"VitalikButerin"},"preferredChain":"evm","preferredToken":"USDT","preferredChainId":1}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── SEPOLIA TESTNET — USDC ────────────────────────────────────
# =============================================================
echo "── SEPOLIA / USDC (testnet) ─────────────────────────────"

pay "CoinGecko: Price [SEPOLIA/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"ethereum"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":11155111}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [SEPOLIA/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Sepolia testnet Ethereum","numResults":2},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":11155111}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── OPTIMISM — USDC ───────────────────────────────────────────
# =============================================================
echo "── OPTIMISM / USDC ──────────────────────────────────────"

pay "CoinGecko: Price [OP/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"optimism,ethereum"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":10}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [OP/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Optimism OP Stack ecosystem","numResults":3},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":10}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "OpenRouter: GPT-4o [OP/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/openrouter/v1/chat/completions","method":"POST","body":{"model":"openai/gpt-4o","messages":[{"role":"user","content":"Explain Optimism Superchain"}]},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":10}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── POLYGON — USDC ────────────────────────────────────────────
# =============================================================
echo "── POLYGON / USDC ───────────────────────────────────────"

pay "CoinGecko: Price [MATIC/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"matic-network,ethereum"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":137}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [MATIC/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Polygon 2.0 roadmap","numResults":3},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":137}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Twitter: Search [MATIC/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/search-tweets","method":"POST","body":{"query":"Polygon blockchain","queryType":"Latest","cursor":""},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":137}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── ARBITRUM — USDC ───────────────────────────────────────────
# =============================================================
echo "── ARBITRUM / USDC ──────────────────────────────────────"

pay "CoinGecko: Price [ARB/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"arbitrum,ethereum"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":42161}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [ARB/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Arbitrum DeFi ecosystem","numResults":3},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":42161}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "OpenRouter: Claude [ARB/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/openrouter/v1/chat/completions","method":"POST","body":{"model":"anthropic/claude-3-haiku","messages":[{"role":"user","content":"Explain Arbitrum Nitro"}]},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":42161}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── BNB SMART CHAIN — USDC ────────────────────────────────────
# =============================================================
echo "── BNB SMART CHAIN / USDC ───────────────────────────────"

pay "CoinGecko: Price [BNB/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"binancecoin,bitcoin"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":56}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [BNB/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"BNB Chain DeFi 2025","numResults":3},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":56}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Twitter: Search [BNB/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/search-tweets","method":"POST","body":{"query":"BNB Chain ecosystem","queryType":"Latest","cursor":""},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":56}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# ── GNOSIS — USDC ─────────────────────────────────────────────
# =============================================================
echo "── GNOSIS / USDC ────────────────────────────────────────"

pay "CoinGecko: Price [GNO/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"gnosis,xdai"},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":100}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

pay "Exa: Search [GNO/USDC]" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"Gnosis Chain xDAI","numResults":3},"preferredChain":"evm","preferredToken":"USDC","preferredChainId":100}'
sleep $DELAY; [[ $break_script -eq 1 ]] && exit 0

# =============================================================
# SUMMARY FINAL
# =============================================================
echo ""
echo "============================================================"
echo "  SELESAI | $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
echo "  OK    : ${TOTAL_OK}/${TOTAL}"
echo "  GAGAL : ${TOTAL_FAIL}/${TOTAL}"
echo -e "  Log:\n${LOG}"
echo "============================================================"

FINAL_BAL=$(curl -s "https://frames.ag/api/wallets/${USER}/balances" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    for w in d.get('solanaWallets',[]):
        for b in w.get('balances',[]):
            if b.get('asset','').upper()=='CASH' and 'devnet' not in b.get('chain','').lower():
                print(b.get('tokenAmount',{}).get('uiAmountString') or '0'); import sys; sys.exit()
    print('0')
except: print('0')
" 2>/dev/null | tr -d '[:space:]')

SPENT=$(python3 -c "print(f'{max(0,float(\"${OWN_CASH_START:-0}\")-float(\"${FINAL_BAL:-0}\")):.4f}')" 2>/dev/null || echo "?")

send_tg_msg "AgentWallet Run Selesai — v4.0
User     : ${USER} | ${NOW} UTC
Berhasil : ${TOTAL_OK}/${TOTAL}
Gagal    : ${TOTAL_FAIL}/${TOTAL}
Terpakai : ~${SPENT} CASH
Sisa     : ${FINAL_BAL} CASH
Detail:
$(echo -e "${LOG}")"
