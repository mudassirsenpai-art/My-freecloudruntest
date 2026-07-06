#!/usr/bin/env bash
set -euo pipefail

# ===== [CONFIG] SENPAI'S PEAK PERFORMANCE DETAILS =====
TELEGRAM_TOKEN="8879018480:AAGnWtLT4VWb5OmdkJpRNLMnxBI_6uLxXq8"
TELEGRAM_CHAT_IDS="7128257853"
PROTO_OPTION="1"     # 1 = Trojan WS
SERVICE="vpn-$((RANDOM % 90000 + 10000))"  # Random Service Name
CPU="8"              # Peak vCPU for Cloud Run
MEMORY="32Gi"        # Peak RAM limit (32GB)
# ======================================================

LOG_FILE="/tmp/n4_cloudrun_$(date +%s).log"
touch "$LOG_FILE"

# =================== Premium UI Colors ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_CYAN=$'\e[38;5;44m'; C_BLUE=$'\e[38;5;33m'
  C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'
  C_RED=$'\e[38;5;196m'; C_GREY=$'\e[38;5;245m'
else
  RESET= BOLD= DIM= C_CYAN= C_BLUE= C_GREEN= C_YEL= C_RED= C_GREY=
fi

hr(){ printf "${C_GREY}──────────────────────────────────────────────────────${RESET}\n"; }
banner(){
  printf "\n${C_BLUE}${BOLD}╔════════════════════════════════════════════════════╗${RESET}\n"
  printf "${C_BLUE}${BOLD}║${RESET}  %-50s${C_BLUE}${BOLD}║${RESET}\n" "$1"
  printf "${C_BLUE}${BOLD}╚════════════════════════════════════════════════════╝${RESET}\n\n"
}

# Protocol Selection (Trojan WS Selected)
PROTO="trojan-ws"
IMAGE="docker.io/n4pro/tr:latest"

banner "🚀 N4 VPN - PEAK PERFORMANCE DEPLOYER"

# ===== AUTOMATIC PROJECT SELECTION =====
printf "${C_CYAN}🔍 Detecting active Google Cloud project...${RESET}\n"
PROJECT=$(gcloud config get-value project 2>/dev/null || true)

if [[ -z "$PROJECT" ]]; then
  PROJECT=$(gcloud projects list --format="value(projectId)" --limit=1 2>/dev/null || true)
  if [[ -n "$PROJECT" ]]; then
    gcloud config set project "$PROJECT" --quiet >>"$LOG_FILE" 2>&1
  else
    printf "${C_RED}✘ No active project found. Please run 'gcloud auth login'.${RESET}\n"
    exit 1
  fi
fi
printf "${C_GREEN}✔ Active Project:${RESET} %s\n" "${PROJECT}"
hr

printf "${C_CYAN}⚙️ Enabling required GCP APIs...${RESET}\n"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com compute.googleapis.com --quiet >>"$LOG_FILE" 2>&1

# ===== EU-FIRST SMART REGION DETECTION =====
printf "${C_CYAN}🌍 Filtering allowed regions (EU First)...${RESET}\n"
# Europe regions placed first, then US, then Asia
TEST_REGIONS=("europe-west1" "europe-west4" "europe-west9" "us-central1" "us-east1" "us-east4" "us-west1" "asia-southeast1" "asia-east1")
REGIONS=()

for R in "${TEST_REGIONS[@]}"; do
  if gcloud compute zones list --filter="region:$R" --limit=1 >>"$LOG_FILE" 2>&1; then
    REGIONS+=("$R")
    printf "   ${C_GREEN}↳ Allowed:${RESET} %s\n" "$R"
  fi
done

if (( ${#REGIONS[@]} == 0 )); then
  printf "${C_YEL}⚠ Could not verify allowed regions. Using europe-west1 fallback.${RESET}\n"
  REGIONS=("europe-west1")
fi
hr

# ===== SMART DEPLOY LOOP WITH PEAK LIMITS =====
DEPLOYED=false
CHOSEN_REGION=""

printf "${C_CYAN}🚀 Initiating Peak Deployment (${CPU} vCPU / ${MEMORY} RAM)...${RESET}\n"
for REGION in "${REGIONS[@]}"; do
  printf "⏳ Testing ${C_YEL}%s${RESET} on %s...\n" "${SERVICE}" "${REGION}"
  
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
    --max-instances=10 \
    --no-cpu-throttling \
    --execution-environment=gen2 \
    --concurrency=100 \
    --quiet
  RC=$?
  set -e

  if (( RC == 0 )); then
    printf "${C_GREEN}✔ Success! Deployed on %s${RESET}\n" "${REGION}"
    CHOSEN_REGION="$REGION"
    DEPLOYED=true
    break
  else
    printf "${C_RED}⚠ Region %s hit quota limits. Trying next...${RESET}\n" "${REGION}"
  fi
done

if [ "$DEPLOYED" = false ]; then
  printf "\n${C_RED}✘ All allowed regions failed. Google Trial limit reached.${RESET}\n"
  exit 1
fi
hr

# ===== SUCCESS & TELEGRAM NOTIFY =====
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${CHOSEN_REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

TROJAN_PASS="Trojan-2025"
URI="trojan://${TROJAN_PASS}@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${CANONICAL_HOST}&type=ws#Trojan-WS-PEAK"

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}" || true

# Clean and Professional Telegram Output
MSG=$(cat <<EOF
✨ <b>N4 VPN | Deployment Success</b> ✨
━━━━━━━━━━━━━━━━━━━━
🌍 <b>Region:</b> <code>${CHOSEN_REGION}</code>
💻 <b>Specs:</b> <code>${CPU} vCPU | ${MEMORY} (Gen2)</code>
⚡ <b>Protocol:</b> <code>TROJAN-WS</code>
🔗 <b>App URL:</b> <a href="${URL_CANONICAL}">${SERVICE}</a>
━━━━━━━━━━━━━━━━━━━━
🔑 <b>V2Ray Configuration Key:</b>

<pre><code>${URI}</code></pre>
EOF
)

RM='{"inline_keyboard":[[{"text":"🔗 Join N4 VPN Channel","url":"https://t.me/n4vpn"}]]}'

for _cid in "${CHAT_ID_ARR[@]}"; do
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d "chat_id=${_cid}" \
    --data-urlencode "text=${MSG}" \
    -d "parse_mode=HTML" \
    --data-urlencode "reply_markup=${RM}" > /dev/null 2>&1
done

printf "\n${C_GREEN}${BOLD}✨ Setup Complete! Configuration sent to Telegram.${RESET}\n\n"
