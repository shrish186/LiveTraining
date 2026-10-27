#!/usr/bin/env bash
# Start the backend for local development so an iPhone on the same Wi-Fi can reach it.
#   ./run_dev.sh            (from backend/, or from anywhere)
#   PORT=8001 ./run_dev.sh  (another port)
# Never prints secrets: it only checks that they are set.
set -euo pipefail
cd "$(dirname "$0")"
PORT="${PORT:-8000}"

# 1. backend/.env with WHOOP credentials
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created backend/.env from .env.example."
  echo "Fill in WHOOP_CLIENT_ID and WHOOP_CLIENT_SECRET (https://developer-dashboard.whoop.com), then run this again."
  exit 1
fi
missing=()
for var in WHOOP_CLIENT_ID WHOOP_CLIENT_SECRET; do
  grep -Eq "^${var}=[[:space:]]*[^[:space:]#]+" .env || missing+=("${var}")
done
if (( ${#missing[@]} )); then
  echo "ERROR: ${missing[*]} empty in backend/.env. Fill in the value(s) from https://developer-dashboard.whoop.com" >&2
  exit 1
fi

# 2. Python 3.11+ (macOS's built-in python3 is 3.9, which is too old)
PY=""
for candidate in python3.13 python3.12 python3.11 python3; do
  if command -v "${candidate}" >/dev/null 2>&1 &&
     "${candidate}" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PY="${candidate}"; break
  fi
done
if [[ -z "${PY}" ]]; then
  echo "ERROR: Python 3.11 or newer is required. Install it with:  brew install python@3.12" >&2
  exit 1
fi

# 3. Virtualenv + dependencies (quick no-op when already installed)
if [[ ! -x .venv/bin/python ]] || ! .venv/bin/python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo "Creating backend/.venv with ${PY}..."
  rm -rf .venv
  "${PY}" -m venv .venv
fi
.venv/bin/pip install --quiet --disable-pip-version-check -r requirements.txt

# 4. LAN IP for the phone
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
if [[ -z "${IP}" ]] && command -v hostname >/dev/null; then
  IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"   # Linux fallback
fi

echo
echo "  Live Training backend"
echo "  -----------------------------------------------"
if [[ -n "${IP}" ]]; then
  echo "  Backend URL for the app:  http://${IP}:${PORT}"
else
  echo "  Backend URL for the app:  (could not find your Wi-Fi IP; check System Settings > Wi-Fi > Details)"
fi
echo "  Status page on this Mac:  http://localhost:${PORT}"
echo "  Connect WHOOP (on Mac):   http://localhost:${PORT}/auth/whoop/login"
echo "  Phone and Mac must be on the same Wi-Fi. Ctrl+C to stop."
echo

exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "${PORT}"
