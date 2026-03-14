#!/bin/bash
# =============================================================
# AgentWallet — ALL Services CASH Payment v3.0
# Urutan: paling mahal duluan, jeda 1 menit antar request
# Total: ~39 endpoint, estimasi ~40 menit
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

echo "============================================================"
echo "  AgentWallet - ALL Services CASH v3.0"
echo "  Time : ${NOW} UTC | User: ${USER}"
echo "  Jeda : ${DELAY}s | Estimasi: ~40 menit"
echo "============================================================"

# =============================================================
# HELPER: kirim notif skip ke Telegram
# =============================================================
send_tg_msg() {
  # Kirim ke Telegram via python3 — reliable, handles special chars
  local TEXT="$1"
  if [[ -z "$TG_TOKEN" || -z "$TG_CHAT" ]]; then
    echo "  TG: token/chat kosong, skip"
    return
  fi
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

send_skip() {
  local REASON="$1"
  echo "  SKIP: ${REASON}"
  local MSG="AgentWallet SKIP
━━━━━━━━━━━━━━━━━━━━━
Waktu    : ${NOW} UTC
User     : ${USER}
Reward   : ${REWARD_WALLET}
Balance  : ${CASH_BAL:-0} CASH
Minimum  : ${MIN_CASH:-0.05} CASH
Status   : ${REASON}
━━━━━━━━━━━━━━━━━━━━━
Cek berikutnya ~5 menit lagi"
  send_tg_msg "$MSG"
}

# =============================================================
# CEK CASH BALANCE WALLET REWARD
# Wallet reward: CQi9MGyFFR21dsPtHuuQTRfaeu2dT9sS1jTb855ZiicD
# Kalau balance naik = ada reward baru = jalan
# Kalau sama/turun/kosong = belum ada reward = skip
# Pakai Solana public RPC, gratis tanpa API key
# =============================================================
REWARD_WALLET="CQi9MGyFFR21dsPtHuuQTRfaeu2dT9sS1jTb855ZiicD"
CASH_MINT="CASHx9KJUStyftLFWGvEVf59SGeG9sh5FfcnZMVPCASH"
RPC="https://api.mainnet-beta.solana.com"
CACHE_FILE="/tmp/agentwallet_reward_bal.txt"

echo ""
echo "Cek CASH balance wallet reward..."
echo "  Wallet : ${REWARD_WALLET}"

RPC_RESP=$(curl -s -X POST "$RPC" \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"getTokenAccountsByOwner\", \"params\": [\"${REWARD_WALLET}\", {\"mint\": \"${CASH_MINT}\"}, {\"encoding\": \"jsonParsed\"}]}")

CASH_BAL=$(echo "$RPC_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    accounts = d.get('result', {}).get('value', [])
    if accounts:
        print(accounts[0]['account']['data']['parsed']['info']['tokenAmount']['uiAmountString'])
    else:
        print('0')
except:
    print('0')
" 2>/dev/null)
CASH_BAL="${CASH_BAL:-0}"

if [[ -f "$CACHE_FILE" ]]; then
  LAST_BAL=$(cat "$CACHE_FILE" | tr -d '[:space:]')
else
  LAST_BAL="0"
fi

echo "  Sebelumnya : ${LAST_BAL} CASH"
echo "  Sekarang   : ${CASH_BAL} CASH"

MIN_CASH="0"
IS_ENOUGH=$(python3 -c "print('yes' if ${CASH_BAL} >= ${MIN_CASH} else 'no')" 2>/dev/null || echo "no")

if [[ "$IS_ENOUGH" != "yes" ]]; then
  send_skip "CASH wallet reward ${CASH_BAL} < ${MIN_CASH} — belum cukup"
  exit 0
fi

echo "  CASH cukup! ${CASH_BAL} >= ${MIN_CASH} — lanjut jalankan semua service!"
echo ""

# =============================================================
# CEK CASH BALANCE WALLET SENDIRI — budget & deteksi CASH masuk
# =============================================================
OWN_CACHE="/tmp/agentwallet_own_cash.txt"

echo "Cek CASH balance wallet sendiri..."
OWN_BALANCES=$(curl -s "https://frames.ag/api/wallets/${USER}/balances" \
  -H "Authorization: Bearer ${TOKEN}")

OWN_CASH=$(echo "$OWN_BALANCES" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    for w in d.get('solanaWallets', []):
        for b in w.get('balances', []):
            asset = b.get('asset','')
            chain = b.get('chain','')
            if asset.upper() == 'CASH' and 'devnet' not in chain.lower():
                amt = b.get('tokenAmount',{}).get('uiAmountString') or                       b.get('displayValues',{}).get('native') or '0'
                print(str(amt).strip())
                sys.exit()
    print('0')
except Exception as e:
    import sys; print('0', file=sys.stderr)
    print('0')
" 2>/dev/null | tr -d '[:space:]')
OWN_CASH="${OWN_CASH:-0}"

# Baca balance sendiri sebelumnya
if [[ -f "$OWN_CACHE" ]]; then
  OWN_LAST=$(cat "$OWN_CACHE" | tr -d '[:space:]')
else
  OWN_LAST="0"
fi

echo "  Sebelumnya : ${OWN_LAST} CASH"
echo "  Sekarang   : ${OWN_CASH} CASH"

# Deteksi CASH masuk ke wallet sendiri
OWN_HIGHER=$(python3 -c "print('yes' if ${OWN_CASH} > ${OWN_LAST:-0} else 'no')" 2>/dev/null || echo "no")
# Notif CASH masuk hanya kalau OWN_LAST bukan 0 (bukan first run)
if [[ "$OWN_HIGHER" == "yes" && "$OWN_LAST" != "0" && -n "$OWN_LAST" ]]; then
  DIFF=$(python3 -c "print(f'{${OWN_CASH}-${OWN_LAST:-0}:.6f}')" 2>/dev/null || echo "0")
  echo "  Ada CASH masuk! +${DIFF} CASH"
  send_tg_msg "💰 CASH MASUK ke wallet kamu!
User     : ${USER}
Masuk    : +${DIFF} CASH
Balance  : ${OWN_CASH} CASH
Waktu    : ${NOW} UTC"
fi

# Simpan balance sendiri
echo "$OWN_CASH" > "$OWN_CACHE"
echo ""

pay() {
  local NAME="$1"
  local PAYLOAD="$2"
  TOTAL=$((TOTAL + 1))

  echo ""
  echo "[${TOTAL}] ${NAME}"

  # Dry run dulu — cek biaya & policy
  DRY=$(curl -s -X POST "$BASE" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD//\$DR/,\"dryRun\":true}")

  AMT=$(echo "$DRY" | grep -o '"amountFormatted":"[^"]*"' | cut -d'"' -f4)
  AMT_RAW=$(echo "$DRY" | grep -o '"amountRaw":"[^"]*"' | cut -d'"' -f4)
  POLICY=$(echo "$DRY" | grep -o '"policyAllowed":[^,}]*' | cut -d: -f2 | tr -d ' ')
  echo "  Dry : ${AMT:-unknown} | policy=${POLICY:-?} | wallet: ${OWN_CASH} CASH"

  # Cek apakah balance cukup
  if [[ -n "$AMT_RAW" ]]; then
    NEEDED=$(python3 -c "print(f'{${AMT_RAW}/1000000:.6f}')" 2>/dev/null || echo "0")
    ENOUGH=$(python3 -c "print('yes' if float('${OWN_CASH:-0}') >= float('${NEEDED:-0}') else 'no')" 2>/dev/null || echo "no")
    if [[ "$ENOUGH" != "yes" ]]; then
      echo "  SKIP: balance tidak cukup (punya ${OWN_CASH}, butuh ${NEEDED} CASH)"
      LOG="${LOG}\n⏸ ${NAME}: balance tidak cukup (${OWN_CASH} < ${NEEDED})"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      send_tg_msg "⏸ [${TOTAL}] ${NAME}
Status   : SKIP - balance tidak cukup
Punya    : ${OWN_CASH} CASH
Butuh    : ${NEEDED} CASH
Progress : ${TOTAL_OK} OK / ${TOTAL_FAIL} FAIL dari ${TOTAL}
Waktu    : $(date -u '+%H:%M:%S') UTC"
      return
    fi
  fi

  if [[ "$POLICY" == "false" ]]; then
    echo "  SKIP: policy denied"
    LOG="${LOG}\n⏸ ${NAME}: policy denied"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    send_tg_msg "⏸ [${TOTAL}] ${NAME}
Status  : SKIP (policy denied)
Waktu   : $(date -u '+%H:%M:%S') UTC"
    return
  fi

  # Jeda singkat hindari rate limit
  sleep 3

  # Bayar
  RESULT=$(curl -s -X POST "$BASE" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD//\$DR/}")

  # Untuk dryRun: cek success=true, untuk real: cek paid=true
  RESULT_STATUS=$(echo "$RESULT" | python3 -c "
import sys,json
try:
    d=json.loads(sys.stdin.read())
    success = d.get('success',False)
    paid    = d.get('paid',False)
    dry     = d.get('dryRun',False)
    r=d.get('response',{})
    b=r.get('body',{}) if isinstance(r,dict) else {}
    err=d.get('error') or d.get('message') or b.get('error') or b.get('message') or ''
    amt=d.get('payment',{}).get('amountFormatted','0.00 CASH') if isinstance(d.get('payment'),dict) else '0.00 CASH'
    if (dry and success) or paid:
        print(f'OK|{amt}|')
    else:
        print(f'FAIL||{str(err)[:120]}')
except Exception as e:
    print(f'FAIL||parse_error: {e}')
" 2>/dev/null)

  STATUS_TYPE=$(echo "$RESULT_STATUS" | cut -d'|' -f1)
  AMT_PAID=$(echo "$RESULT_STATUS" | cut -d'|' -f2)
  ERR=$(echo "$RESULT_STATUS" | cut -d'|' -f3)

  if [[ "$STATUS_TYPE" == "OK" ]]; then
    echo "  OK  : ${AMT_PAID}"
    LOG="${LOG}\n✅ ${NAME}: ${AMT_PAID}"
    TOTAL_OK=$((TOTAL_OK + 1))
    # Update own balance setelah bayar
    if [[ -n "$AMT_RAW" ]]; then
      OWN_CASH=$(python3 -c "print(f'{float(\"${OWN_CASH:-0}\")-${AMT_RAW:-0}/1000000:.6f}')" 2>/dev/null || echo "${OWN_CASH:-0}")
      echo "$OWN_CASH" > "$OWN_CACHE"
    fi
    send_tg_msg "✅ [${TOTAL}] ${NAME}
Amount   : ${AMT_PAID}
Sisa     : ${OWN_CASH} CASH
Progress : ${TOTAL_OK} OK / ${TOTAL_FAIL} FAIL dari ${TOTAL} service
Waktu    : $(date -u '+%H:%M:%S') UTC"
  else
    REASON="${ERR:-unknown}"
    echo "  FAIL: ${REASON:0:120}"
    LOG="${LOG}\n❌ ${NAME}: ${REASON:0:80}"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    send_tg_msg "❌ [${TOTAL}] ${NAME}
Error    : ${REASON:0:150}
Progress : ${TOTAL_OK} OK / ${TOTAL_FAIL} FAIL dari ${TOTAL}
Waktu    : $(date -u '+%H:%M:%S') UTC"
  fi
}

send_tg() {
  if [[ -z "$TG_TOKEN" || -z "$TG_CHAT" ]]; then return; fi
  curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"${TG_CHAT}\",\"text\":\"$1\",\"parse_mode\":\"HTML\"}" > /dev/null
}

# =============================================================
# === SERVICES — termurah duluan ===
# =============================================================

pay "Jupiter: Price (0.002 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/jupiter/api/price","method":"POST","body":{"ids":"So11111111111111111111111111111111111111112"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Jupiter: Tokens (0.002 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/jupiter/api/tokens","method":"POST","body":{"query":"USDC"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "CoinGecko: Price (0.002 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/price","method":"POST","body":{"ids":"bitcoin,solana,ethereum"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "CoinGecko: Search (0.003 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/search","method":"POST","body":{"query":"solana"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "CoinGecko: Token Info (0.005 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/token-info","method":"POST","body":{"id":"solana"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "CoinGecko: Markets (0.005 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/coingecko/api/markets","method":"POST","body":{"vs_currency":"usd","ids":"bitcoin,ethereum,solana"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Twitter: Search Tweets (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/search-tweets","method":"POST","body":{"query":"AI agents","queryType":"Latest","cursor":""},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Twitter: User Tweets (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/user-tweets","method":"POST","body":{"userName":"elonmusk"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Twitter: Trends (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/trends","method":"POST","body":{"woeid":1,"count":10},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Twitter: Tweet Replies (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/tweet-replies","method":"POST","body":{"tweetId":"1234567890","cursor":"","queryType":"Latest"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Exa: Search (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/search","method":"POST","body":{"query":"AgentWallet x402 CASH payment","numResults":3},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Exa: Answer (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/answer","method":"POST","body":{"query":"What is AgentWallet?"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Exa: Find Similar (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/exa/api/find-similar","method":"POST","body":{"url":"https://frames.ag","numResults":3},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AgentMail: Create Inbox (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/agentmail/api/inbox/create","method":"POST","body":{"username":"myagent","display_name":"My Agent"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AgentMail: Send Email (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/agentmail/api/send","method":"POST","body":{"inbox_id":"test","to":[{"email":"test@example.com"}],"subject":"Hello from AgentWallet","text":"Test email from AI agent"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "NEAR Intents: Quote (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/near-intents/api/quote","method":"POST","body":{"inputCurrency":"USDC","outputCurrency":"SOL","amount":"1"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "OpenRouter: GPT-4o (0.01 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/openrouter/v1/chat/completions","method":"POST","body":{"model":"openai/gpt-4o","messages":[{"role":"user","content":"Explain quantum computing in simple terms"}]},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Twitter: Batch Users (0.02 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/twitter/api/batch-users","method":"POST","body":{"userIds":"44196397,783214"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Minimax Music (0.042 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"minimax/music-01","prompt":"An upbeat electronic music track about the future"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Nano Banana (0.05 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/nano-banana","prompt":"A stunning galaxy in deep space ultra detailed"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Trellis 3D (0.054 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"firtoz/trellis","prompt":"A futuristic robot"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Insanely Fast Whisper (0.06 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"turian/insanely-fast-whisper-with-video","audio_url":"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Wan 2.2 I2V Fast (0.07 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"wan-video/wan-2.2-i2v-fast","prompt":"A beautiful waterfall in a jungle"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Wan 2.2 T2V Fast (0.12 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"wan-video/wan-2.2-t2v-fast","prompt":"A beautiful waterfall in a jungle"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Nano Banana 2 (0.13 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/nano-banana-2","prompt":"A stunning galaxy in deep space"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: DALL-E 3 (0.15 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"openai/dall-e-3","prompt":"A beautiful sunset over the ocean photorealistic"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Nano Banana Pro (0.18 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/nano-banana-pro","prompt":"A futuristic robot in a magical forest ultra detailed"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Hunyuan 3D 3.1 (0.20 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"tencent/hunyuan-3d-3.1","prompt":"A futuristic robot with detailed PBR materials"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Runway Gen-4 Turbo (0.30 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"runwayml/gen4-turbo","prompt":"A person running through a futuristic city","duration":5,"resolution":"1080p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Seedance 1 Pro 1080p (0.36 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"bytedance/seedance-1-pro","prompt":"A beautiful waterfall in a tropical jungle","duration":6,"resolution":"1080p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Kling v2.6 10s (0.42 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"kwaivgi/kling-v2.6","prompt":"A cinematic landscape with dramatic lighting","duration":10,"resolution":"1080p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Minimax Video-01 (0.6 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"minimax/video-01","prompt":"A robot walking through a neon city"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Sora 2 720p (0.6 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"openai/sora-2","prompt":"A stunning sunset over a futuristic city","duration":5,"resolution":"720p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Veo 3 Fast 8s (0.9 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/veo-3-fast","prompt":"A futuristic city with flying cars","duration":8,"resolution":"720p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: VEED Fabric Talking Head (0.9 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"veed/fabric-1.0","prompt":"A person talking about the future of AI"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Sora 2 Pro 1080p (1.8 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"openai/sora-2-pro","prompt":"A cinematic robot walking through a neon city","duration":5,"resolution":"1080p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "Wordspace Agent (2.0 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/wordspace/api/invoke","method":"POST","body":{"prompt":"Write a detailed story about AI agents changing the world"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Veo 3 (2.4 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/veo-3","prompt":"A futuristic city with flying cars and neon lights","duration":8,"resolution":"1080p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'
sleep $DELAY
pay "AI Gen: Veo 3.1 (2.4 CASH)" \
  '{"url":"https://registry.frames.ag/api/service/ai-gen/api/invoke","method":"POST","body":{"model":"google/veo-3.1","prompt":"A stunning ocean sunset with dramatic clouds","duration":8,"resolution":"1080p"},"preferredChain":"solana","preferredToken":"CASH","dryRun":true}'

# =============================================================
# SUMMARY
# =============================================================
echo ""
echo "============================================================"
echo "  SELESAI | $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
echo "  OK    : ${TOTAL_OK}/${TOTAL}"
echo "  GAGAL : ${TOTAL_FAIL}/${TOTAL}"
echo -e "  Log:\n${LOG}"
echo "============================================================"

TG_MSG="<b>AgentWallet ALL CASH Run v3.0</b>
${NOW} UTC
━━━━━━━━━━━━━━━━━━━━━
OK: ${TOTAL_OK}/${TOTAL} | FAIL: ${TOTAL_FAIL}
$(echo -e $LOG)"
send_tg "$TG_MSG"
