#!/usr/bin/env bash
set -euo pipefail

# ===== [CONFIG] SENPAI'S CUSTOM DETAILS =====
TELEGRAM_TOKEN="8879018480:AAGnWtLT4VWb5OmdkJpRNLMnxBI_6uLxXq8"
TELEGRAM_CHAT_IDS="7128257853"
PROTO_OPTION="1"     # 1 = Trojan WS
SERVICE="vpn-$((RANDOM % 90000 + 10000))"  # Random Service Name Generate Hoga
CPU="8"              # Maximum 8 vCPU (Dedicated VPS Style)
MEMORY="16Gi"        # 16GB RAM
# ============================================

LOG_FILE="/tmp/n4_cloudrun_$(date +%s).log"
touch "$LOG_FILE"

# Colors
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; C_CYAN=$'\e[38;5;44m'; C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'; C_RED=$'\e[38;5;196m'
else
  RESET= BOLD= C_CYAN= C_GREEN= C_YEL= C_RED=
fi

# Protocol Selection (Trojan WS Selected)
PROTO="trojan-ws"
IMAGE="docker.io/n4pro/tr:latest"

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  echo "${C_RED}✘ No active project set. Run: gcloud config set project <PROJECT_ID>${RESET}"
  exit 1
fi

echo "${C_CYAN}⚙️ Enabling required APIs...${RESET}"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com compute.googleapis.com --quiet >>"$LOG_FILE" 2>&1

# ===== SMART ALLOWED REGIONS DETECTION =====
echo "${C_CYAN}🔍 Filtering out locked regions from trial account...${RESET}"
TEST_REGIONS=("us-central1" "us-east1" "us-east4" "us-west1" "europe-west1" "europe-west4" "asia-southeast1" "asia-east1")
REGIONS=()

for R in "${TEST_REGIONS[@]}"; do
  if gcloud compute zones list --filter="region:$R" --limit=1 >>"$LOG_FILE" 2>&1; then
    REGIONS+=("$R")
    echo "   -> ${C_GREEN}Region Allowed:${RESET} $R"
  fi
done

if (( ${#REGIONS[@]} == 0 )); then
  echo "${C_YEL}⚠ Could not verify allowed regions. Using us-central1 fallback.${RESET}"
  REGIONS=("us-central1")
fi

# ===== SMART DEPLOY LOOP =====
DEPLOYED=false
CHOSEN_REGION=""

echo "${C_CYAN}🚀 Testing deployment on your active regions with 8 vCPU / 16GB RAM...${RESET}"
for REGION in "${REGIONS[@]}"; do
  echo "⏳ Deploying ${SERVICE} on region: ${C_YEL}${REGION}${RESET}..."
  
  set +e
  gcloud run deploy "$SERVICE" \
    --image="$IMAGE" \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --timeout=3600 \
    --allow-unauthenticated \
    --port=8080 \
    --min-instances=1 \
    --no-cpu-throttling \
    --quiet >>"$LOG_FILE" 2>&1
  RC=$?
  set -e

  if (( RC == 0 )); then
    echo "${C_GREEN}✔ Successfully deployed on ${REGION}!${RESET}"
    CHOSEN_REGION="$REGION"
    DEPLOYED=true
    break
  else
    echo "${C_RED}⚠ Region ${REGION} hit a deployment error. Trying next allowed...${RESET}"
  fi
done

if [ "$DEPLOYED" = false ]; then
  echo "${C_RED}✘ All verified regions failed. Cloud Run quota check karna padega.${RESET}"
  exit 1
fi

# ===== SUCCESS & TELEGRAM NOTIFY =====
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${CHOSEN_REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

TROJAN_PASS="Trojan-2025"
URI="trojan://${TROJAN_PASS}@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${CANONICAL_HOST}&type=ws#Trojan-WS-VPS"

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}" || true
MSG=$(cat <<EOF
✅ <b>CloudRun VPS Deploy Success</b>
━━━━━━━━━━━━━━━━━━
🌍 <b>Active Region:</b> ${CHOSEN_REGION}
💻 <b>Resources:</b> ${CPU} vCPU | ${MEMORY} RAM
⚙️ <b>Protocol:</b> TROJAN-WS
🔗 <b>App URL:</b> <a href="${URL_CANONICAL}">${SERVICE}</a>
━━━━━━━━━━━━━━━━━━
🔑 <b>V2Ray Configuration Key:</b>
<pre><code>${URI}</code></pre>
EOF
)

# Default Button setup (Join N4 VPN Channel)
RM='{"inline_keyboard":[[{"text":"Join N4 VPN Channel","url":"https://t.me/n4vpn"}]]}'

for _cid in "${CHAT_ID_ARR[@]}"; do
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d "chat_id=${_cid}" \
    --data-urlencode "text=${MSG}" \
    -d "parse_mode=HTML" \
    --data-urlencode "reply_markup=${RM}" > /dev/null 2>&1
done

echo "${C_GREEN}${BOLD}✨ Bada mast deploy ho gaya! Config Telegram par bhej di gayi hai.${RESET}"
