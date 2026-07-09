#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads even when run via curl/process substitution =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/n4_cloudrun_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "—— LOG (last 80 lines) ——" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  echo "📄 Log File: $LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== Color & UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_CYAN=$'\e[38;5;44m'; C_BLUE=$'\e[38;5;33m'
  C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;226m'
  C_ORG=$'\e[38;5;214m'; C_PINK=$'\e[38;5;205m'
  C_GREY=$'\e[38;5;245m'; C_RED=$'\e[38;5;196m'
else
  RESET= BOLD= DIM= C_CYAN= C_BLUE= C_GREEN= C_YEL= C_ORG= C_PINK= C_GREY= C_RED=
fi

hr(){ printf "${C_GREY}%s${RESET}\n" "──────────────────────────────────────────────"; }
banner(){
  local title="$1"
  printf "\n${C_BLUE}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
  printf   "${C_BLUE}${BOLD}║${RESET}  %s${RESET}\n" "$(printf "%-46s" "$title")"
  printf   "${C_BLUE}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n"
}
ok(){   printf "${C_GREEN}✔${RESET} %s\n" "$1"; }
warn(){ printf "${C_ORG}⚠${RESET} %s\n" "$1"; }
err(){  printf "${C_RED}✘${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"; }

printf "\n${C_CYAN}${BOLD}🚀 N4 Cloud Run — One-Click Deploy${RESET} ${C_GREY}(Trojan WS / VLESS WS / VLESS gRPC / VMess WS)${RESET}\n"
hr

# =================== Random progress spinner ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r🌀 %s... [%s%%]" "$label" "$pct"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    wait "$pid"; local rc=$?
    printf "\r"
    if (( rc==0 )); then
      printf "✅ %s... [100%%]\n" "$label"
    else
      printf "❌ %s failed (see %s)\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
  fi
}

# =================== Step 1: Telegram Config ===================
banner "🚀 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  set -a; source ./.env; set +a
fi

read -rp "🤖 Telegram Bot Token: " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  warn "Telegram token empty; deploy will continue without messages."
else
  ok "Telegram token captured."
fi

read -rp "👤 Owner/Channel Chat ID(s): " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"

DEFAULT_LABEL="Join N4 VPN Channel"
DEFAULT_URL="https://t.me/n4vpn"
BTN_LABELS=(); BTN_URLS=()

read -rp "➕ Add URL button(s)? [y/N]: " _addbtn || true
if [[ "${_addbtn:-}" =~ ^([yY]|yes)$ ]]; then
  i=0
  while true; do
    echo "—— Button $((i+1)) ——"
    read -rp "🔖 Label [default: ${DEFAULT_LABEL}]: " _lbl || true
    if [[ -z "${_lbl:-}" ]]; then
      BTN_LABELS+=("${DEFAULT_LABEL}")
      BTN_URLS+=("${DEFAULT_URL}")
      ok "Added: ${DEFAULT_LABEL} → ${DEFAULT_URL}"
    else
      read -rp "🔗 URL (http/https): " _url || true
      if [[ -n "${_url:-}" && "${_url}" =~ ^https?:// ]]; then
        BTN_LABELS+=("${_lbl}")
        BTN_URLS+=("${_url}")
        ok "Added: ${_lbl} → ${_url}"
      else
        warn "Skipped (invalid or empty URL)."
      fi
    fi
    i=$(( i + 1 ))
    (( i >= 3 )) && break
    read -rp "➕ Add another button? [y/N]: " _more || true
    [[ "${_more:-}" =~ ^([yY]|yes)$ ]] || break
  done
fi

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1" RM=""
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  if (( ${#BTN_LABELS[@]} > 0 )); then
    local L1 U1 L2 U2 L3 U3
    [[ -n "${BTN_LABELS[0]:-}" ]] && L1="$(json_escape "${BTN_LABELS[0]}")" && U1="$(json_escape "${BTN_URLS[0]}")"
    [[ -n "${BTN_LABELS[1]:-}" ]] && L2="$(json_escape "${BTN_LABELS[1]}")" && U2="$(json_escape "${BTN_URLS[1]}")"
    [[ -n "${BTN_LABELS[2]:-}" ]] && L3="$(json_escape "${BTN_LABELS[2]}")" && U3="$(json_escape "${BTN_URLS[2]}")"
    if (( ${#BTN_LABELS[@]} == 1 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}]]}"
    elif (( ${#BTN_LABELS[@]} == 2 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"}]]}"
    else
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"},{\"text\":\"${L3}\",\"url\":\"${U3}\"}]]}"
    fi
  fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      ${RM:+--data-urlencode "reply_markup=${RM}"} >>"$LOG_FILE" 2>&1
    ok "Telegram sent → ${_cid}"
  done
}

# =================== Step 2: Project ===================
banner "🧭 Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active project. Run: gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
ok "Project Loaded: ${PROJECT}"

# =================== Step 3: Protocol ===================
banner "🧩 Step 3 — Select Protocol"
echo "  1️⃣ Trojan WS"
echo "  2️⃣ VLESS WS"
echo "  3️⃣ VLESS gRPC"
echo "  4️⃣ VMess WS"
read -rp "Choose [1-4, default 1]: " _opt || true
case "${_opt:-1}" in
  2) PROTO="vless-ws"   ; IMAGE="docker.io/n4pro/vl:latest"        ;;
  3) PROTO="vless-grpc" ; IMAGE="docker.io/n4pro/vlessgrpc:latest" ;;
  4) PROTO="vmess-ws"   ; IMAGE="docker.io/n4pro/vmess:latest"     ;;
  *) PROTO="trojan-ws"  ; IMAGE="docker.io/n4pro/tr:latest"        ;;
esac
ok "Protocol selected: ${PROTO^^}"
echo "[Docker Hidden] ${IMAGE}" >>"$LOG_FILE"

# =================== Step 4: Region ===================
banner "🌍 Step 4 — Region"
echo "--- 🇺🇸 NORTH AMERICA ---"
echo "1) us-central1 (Iowa)"
echo "2) us-east1 (South Carolina)"
echo "3) us-east4 (N. Virginia)"
echo "4) us-east5 (Columbus)"
echo "5) us-south1 (Dallas)"
echo "6) us-west1 (Oregon)"
echo "7) us-west2 (Los Angeles)"
echo "8) us-west3 (Salt Lake City)"
echo "9) us-west4 (Las Vegas)"
echo "10) northamerica-northeast1 (Montreal)"
echo "11) northamerica-northeast2 (Toronto)"
echo "--- 🇸🇬 🇮🇳 APAC (Asia Pacific) ---"
echo "12) asia-southeast1 (Singapore)"
echo "13) asia-southeast2 (Jakarta)"
echo "14) asia-east1 (Taiwan)"
echo "15) asia-east2 (Hong Kong)"
echo "16) asia-northeast1 (Tokyo)"
echo "17) asia-northeast2 (Osaka)"
echo "18) asia-northeast3 (Seoul)"
echo "19) asia-south1 (Mumbai)"
echo "20) asia-south2 (Delhi)"
echo "21) australia-southeast1 (Sydney)"
echo "22) australia-southeast2 (Melbourne)"
echo "--- 🇪🇺 EUROPE ---"
echo "23) europe-west1 (Belgium)"
echo "24) europe-west2 (London)"
echo "25) europe-west3 (Frankfurt)"
echo "26) europe-west4 (Netherlands)"
echo "27) europe-west6 (Zurich)"
echo "28) europe-west8 (Milan)"
echo "29) europe-west9 (Paris)"
echo "30) europe-west10 (Berlin)"
echo "31) europe-west12 (Turin)"
echo "32) europe-north1 (Finland)"
echo "33) europe-southwest1 (Madrid)"
echo "34) europe-central2 (Warsaw)"
echo "--- 🌍 AFRICA & MIDDLE EAST ---"
echo "35) africa-south1 (Johannesburg)"
echo "36) me-central1 (Doha)"
echo "37) me-central2 (Dammam)"
echo "38) me-west1 (Tel Aviv)"
echo "--- 🇧🇷 SOUTH AMERICA ---"
echo "39) southamerica-east1 (Sao Paulo)"
echo "40) southamerica-west1 (Santiago)"

read -rp "Choose [1-40, default 1]: " _r || true
case "${_r:-1}" in
  1) REGION="us-central1";;
  2) REGION="us-east1";;
  3) REGION="us-east4";;
  4) REGION="us-east5";;
  5) REGION="us-south1";;
  6) REGION="us-west1";;
  7) REGION="us-west2";;
  8) REGION="us-west3";;
  9) REGION="us-west4";;
  10) REGION="northamerica-northeast1";;
  11) REGION="northamerica-northeast2";;
  12) REGION="asia-southeast1";;
  13) REGION="asia-southeast2";;
  14) REGION="asia-east1";;
  15) REGION="asia-east2";;
  16) REGION="asia-northeast1";;
  17) REGION="asia-northeast2";;
  18) REGION="asia-northeast3";;
  19) REGION="asia-south1";;
  20) REGION="asia-south2";;
  21) REGION="australia-southeast1";;
  22) REGION="australia-southeast2";;
  23) REGION="europe-west1";;
  24) REGION="europe-west2";;
  25) REGION="europe-west3";;
  26) REGION="europe-west4";;
  27) REGION="europe-west6";;
  28) REGION="europe-west8";;
  29) REGION="europe-west9";;
  30) REGION="europe-west10";;
  31) REGION="europe-west12";;
  32) REGION="europe-north1";;
  33) REGION="europe-southwest1";;
  34) REGION="europe-central2";;
  35) REGION="africa-south1";;
  36) REGION="me-central1";;
  37) REGION="me-central2";;
  38) REGION="me-west1";;
  39) REGION="southamerica-east1";;
  40) REGION="southamerica-west1";;
  *) REGION="us-central1";;
esac
ok "Region: ${REGION}"

# =================== Step 5: Resources ===================
banner "🧮 Step 5 — Resources"
read -rp "CPU [1/2/4/6, default 2]: " _cpu || true
CPU="${_cpu:-2}"
read -rp "Memory [512Mi/1Gi/2Gi(default)/4Gi/8Gi]: " _mem || true
MEMORY="${_mem:-2Gi}"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"

# =================== Step 6: Service Name ===================
banner "🪪 Step 6 — Service Name"
SERVICE="${SERVICE:-freen4vpn}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"
read -rp "Service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"
ok "Service: ${SERVICE}"

# =================== Timezone Setup ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
banner "🕒 Step 7 — Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL}"

# =================== Enable APIs ===================
banner "⚙️ Step 8 — Enable APIs"
run_with_progress "Enabling CloudRun & Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Deploy ===================
banner "🚀 Step 9 — Deploying to Cloud Run"
run_with_progress "Deploying ${SERVICE}" \
  gcloud run deploy "$SERVICE" \
    --image="$IMAGE" \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --timeout="$TIMEOUT" \
    --allow-unauthenticated \
    --port="$PORT" \
    --min-instances=1 \
    --no-cpu-throttling \
    --quiet

# =================== Result ===================
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"
banner "✅ Result"
ok "Service Ready"
kv "URL:" "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"

# =================== Protocol URLs ===================
TROJAN_PASS="Trojan-2025"
VLESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"
VLESS_UUID_GRPC="0c890000-4733-4a0e-9a7f-fc341bd20000"
VMESS_UUID="0c890000-4733-b20e-067f-fc341bd20000"

make_vmess_ws_uri(){
  local host="$1"
  local json=$(cat <<JSON
{"v":"2","ps":"VMess-WS","add":"vpn.googleapis.com","port":"443","id":"${VMESS_UUID}","aid":"0","scy":"zero","net":"ws","type":"none","host":"${host}","path":"/N4","tls":"tls","sni":"vpn.googleapis.com","alpn":"http/1.1","fp":"randomized"}
JSON
)
  base64 <<<"$json" | tr -d '\n' | sed 's/^/vmess:\/\//'
}

case "$PROTO" in
  trojan-ws)  URI="trojan://${TROJAN_PASS}@vpn.googleapis.com:443?path=%2FN4&security=tls&host=${CANONICAL_HOST}&type=ws#Trojan-WS" ;;
  vless-ws)   URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2FN4&security=tls&encryption=none&host=${CANONICAL_HOST}&type=ws#Vless-WS" ;;
  vless-grpc) URI="vless://${VLESS_UUID_GRPC}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=n4-grpc&sni=${CANONICAL_HOST}#VLESS-gRPC" ;;
  vmess-ws)   URI="$(make_vmess_ws_uri "${CANONICAL_HOST}")" ;;
esac

# =================== Telegram Notify ===================
banner "📣 Step 10 — Telegram Notify"

MSG=$(cat <<EOF
✅ <b>CloudRun Deploy Success</b>
━━━━━━━━━━━━━━━━━━
<blockquote>🌍 <b>Region:</b> ${REGION}
⚙️ <b>Protocol:</b> ${PROTO^^}
🔗 <b>URL:</b> <a href="${URL_CANONICAL}">${URL_CANONICAL}</a></blockquote>
🔑 <b>V2Ray Configuration Access Key :</b>
<pre><code>${URI}</code></pre>
<blockquote>🕒 <b>Start:</b> ${START_LOCAL}
⏳ <b>End:</b> ${END_LOCAL}</blockquote>
━━━━━━━━━━━━━━━━━━
EOF
)

tg_send "${MSG}"

printf "\n${C_GREEN}${BOLD}✨ Done — Warm Instance Enabled (min=1) | Beautiful Banner UI | Cold Start Prevented${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
