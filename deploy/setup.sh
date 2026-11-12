#!/usr/bin/env bash
# One-time preparation of deploy/ on the server (Linux or WSL 2):
#   * deploy/.env with long random secrets (never overwritten once it exists)
#   * deploy/ca/   a private CA for the devices (keep ca.key offline; ca.crt goes into firmware)
#   * deploy/certs/server.crt + server.key   TLS for the device ports 8883 (MQTT) and 7000 (TCP)
#
#   ./setup.sh <name-or-ip> [more names or IPs...]
#   ./setup.sh hub.example.com                       # a public domain
#   ./setup.sh 192.168.1.20 titiswitch.local         # this PC on the LAN (WSL: the Windows IP)
#
# Run again with other names to renew only the device certificate (same CA, same secrets).
set -euo pipefail
cd "$(dirname "$0")"

if [ "$#" -lt 1 ]; then
  echo "usage: ./setup.sh <name-or-ip> [more names or IPs...]" >&2
  exit 2
fi
command -v openssl >/dev/null || { echo "openssl is needed (sudo apt install openssl)" >&2; exit 1; }

rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
is_ip() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

hosts=("$@")
first="${hosts[0]}"
public_host="$(IFS=,; echo "${hosts[*]}" | sed 's/,/, /g')"

# --- deploy/.env -------------------------------------------------------------------------------
if [ -f .env ]; then
  echo ".env exists: secrets kept"
else
  tls="/certs/server.crt /certs/server.key"
  if ! is_ip "$first" && [[ "$first" == *.* ]] && [[ "$first" != *.local ]] && [[ "$first" != *.lan ]]; then
    read -r -p "Public domain: e-mail for Let's Encrypt (empty = the deploy/ca certificate): " mail || true
    [ -n "${mail:-}" ] && tls="$mail"
  fi
  admin_pass="$(rand 14)Aa7"
  sed -e "s|^PUBLIC_HOST=.*|PUBLIC_HOST=${public_host}|" \
      -e "s|^DEFAULT_SNI=.*|DEFAULT_SNI=${first}|" \
      -e "s|^CADDY_TLS=.*|CADDY_TLS=${tls}|" \
      -e "s|^HUB_PUBLIC_URL=.*|HUB_PUBLIC_URL=https://${first}|" \
      -e "s|^DB_PASSWORD=.*|DB_PASSWORD=$(rand 32)|" \
      -e "s|^HUB_JWT_SECRET=.*|HUB_JWT_SECRET=$(rand 64)|" \
      -e "s|^HUB_DATA_KEY=.*|HUB_DATA_KEY=$(rand 48)|" \
      -e "s|^EMQX_DASHBOARD_PASSWORD=.*|EMQX_DASHBOARD_PASSWORD=$(rand 24)|" \
      -e "s|^HUB_BROKER_HOOK_TOKEN=.*|HUB_BROKER_HOOK_TOKEN=$(rand 40)|" \
      -e "s|^HUB_PLATFORM_MQTT_PASSWORD=.*|HUB_PLATFORM_MQTT_PASSWORD=$(rand 32)|" \
      -e "s|^HUB_BOOTSTRAP_ADMIN_PASSWORD=.*|HUB_BOOTSTRAP_ADMIN_PASSWORD=${admin_pass}|" \
      .env.example > .env
  chmod 600 .env
  echo "wrote .env (random secrets; PUBLIC_HOST=${public_host}, CADDY_TLS=${tls})"
  echo
  echo "FIRST SIGN-IN (shown once; it is also in .env until you delete the line):"
  echo "    user: admin      password: ${admin_pass}"
  echo "    the same account opens /  /maker/  /app/  - a new password is required at once"
fi

# --- device CA and server certificate ----------------------------------------------------------
mkdir -p ca certs
chmod 700 ca
if [ ! -f ca/ca.key ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -sha256 -days 3650 \
    -keyout ca/ca.key -out ca/ca.crt -subj "/O=TiTiSwitch/CN=TiTiSwitch device CA" 2>/dev/null
  chmod 600 ca/ca.key
  echo "made the device CA: deploy/ca/ca.crt (into the firmware), deploy/ca/ca.key (keep offline)"
fi

san=""
for h in "${hosts[@]}"; do
  if is_ip "$h"; then san+="IP:${h},"; else san+="DNS:${h},"; fi
done
san="${san%,}"
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -sha256 \
  -keyout certs/server.key -out certs/server.csr -subj "/O=TiTiSwitch/CN=${first}" 2>/dev/null
openssl x509 -req -in certs/server.csr -CA ca/ca.crt -CAkey ca/ca.key -CAcreateserial \
  -days 825 -sha256 -out certs/server.crt \
  -extfile <(printf "subjectAltName=%s\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature" "$san") 2>/dev/null
rm -f certs/server.csr ca/ca.srl
cp ca/ca.crt certs/ca.crt
# the hub (uid 10001) and EMQX (uid 1000) read these through a read-only mount
chmod 755 certs
chmod 644 certs/server.crt certs/ca.crt certs/server.key
echo "device certificate for: ${san}"
# the phone app shows this when it first connects (a private CA): compare and approve
echo "SHA-256 fingerprint (compare in the app): $(openssl x509 -in certs/server.crt -noout -fingerprint -sha256 | cut -d= -f2)"
echo
echo "next:  docker compose up -d --build"
echo "then sign in with the first account above (no terminal account needed)."
