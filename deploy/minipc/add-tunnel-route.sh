#!/usr/bin/env bash
# Travel.with.Jaws - add travel.jawsweb.site to the locally-managed Cloudflare Tunnel (keymedi-home).
# ASCII only. Run ON the mini PC with a terminal (sudo asks for the password):
#   ssh -t keymedi@192.168.0.202 "bash ~/add-tunnel-route.sh"
# What it does:
#   1) find the cloudflared config.yml, back it up
#   2) add   - hostname: travel.jawsweb.site / service: http://127.0.0.1:80   before the catch-all rule
#   3) validate the config, restart cloudflared
#   4) create the DNS record (cloudflared tunnel route dns) - or tell you the one record to add by hand
set -uo pipefail
HOST="${HOST:-travel.jawsweb.site}"
SERVICE="${SERVICE:-http://127.0.0.1:80}"
ok()   { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [!] %s\n' "$*"; }
die()  { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }

echo "== 1. find config"
sudo -v || die "sudo needed"
CFG="${CFG:-}"
if [ -z "$CFG" ]; then
  # the running service tells us which file it uses
  CFG=$(ps -eo args | grep -E '[c]loudflared.*--config' | sed -E 's/.*--config[ =]([^ ]+).*/\1/' | head -1)
fi
for c in "$CFG" /etc/cloudflared/config.yml /etc/cloudflared/config.yaml "$HOME/.cloudflared/config.yml" /root/.cloudflared/config.yml; do
  [ -n "$c" ] && sudo test -f "$c" && { CFG="$c"; break; }
done
sudo test -f "${CFG:-/nonexistent}" || die "config.yml not found. Run: sudo find / -name 'config.y*ml' -path '*cloudflared*' 2>/dev/null"
ok "config: $CFG"
TMP=$(mktemp); sudo cat "$CFG" > "$TMP"
if grep -qE "hostname:\s*['\"]?$HOST['\"]?\s*$" "$TMP"; then
  ok "$HOST is already in the config"
else
  BK="$CFG.bak-$(date +%Y%m%d-%H%M%S)"; sudo cp -p "$CFG" "$BK"; ok "backup: $BK"
  python3 - "$TMP" "$HOST" "$SERVICE" <<'PY' || die "could not edit the config"
import sys, re
p, host, svc = sys.argv[1:]
lines = open(p).read().split('\n')
# catch-all = an ingress item with "service:" but no hostname, usually "- service: http_status:404"
idx = next((i for i, l in enumerate(lines) if re.match(r'^\s*-\s*service:\s*http_status', l)), None)
if idx is None: raise SystemExit("catch-all rule (- service: http_status:404) not found")
ind = re.match(r'^(\s*)-', lines[idx]).group(1)
block = [f"{ind}- hostname: {host}", f"{ind}  service: {svc}"]
lines[idx:idx] = block
open(p, 'w').write('\n'.join(lines))
PY
  sudo cp "$TMP" "$CFG"
  ok "added: $HOST -> $SERVICE"
fi
rm -f "$TMP"

echo "== 2. validate + restart"
CF=$(command -v cloudflared || true)
if [ -n "$CF" ]; then
  sudo "$CF" tunnel --config "$CFG" ingress validate && ok "config valid" || { warn "invalid config - restoring backup"; [ -n "${BK:-}" ] && sudo cp -p "$BK" "$CFG"; die "nothing changed"; }
  sudo "$CF" tunnel --config "$CFG" ingress rule "https://$HOST" | sed 's/^/    /'
fi
UNIT=$(systemctl list-unit-files 2>/dev/null | grep -oE '^cloudflared(@[^ ]*)?\.service' | head -1)
if [ -n "$UNIT" ]; then
  sudo systemctl restart "$UNIT" && sleep 3 && systemctl is-active "$UNIT" >/dev/null && ok "restarted $UNIT" || die "$UNIT did not come back: sudo journalctl -u $UNIT -n 30"
elif sudo docker ps --format '{{.Names}}' | grep -q cloudflared; then
  C=$(sudo docker ps --format '{{.Names}}' | grep cloudflared | head -1); sudo docker restart "$C" >/dev/null && ok "restarted container $C"
else
  warn "cloudflared service not found - restart it yourself"
fi

echo "== 3. DNS record"
TID=$(sudo grep -E '^\s*tunnel:' "$CFG" | head -1 | sed -E 's/^\s*tunnel:\s*//; s/["'\'']//g')
DNS_OK=0
if [ -n "$CF" ] && [ -n "$TID" ]; then
  for home in "$HOME" /root /etc/cloudflared; do
    if sudo test -f "$home/.cloudflared/cert.pem" || sudo test -f "$home/cert.pem"; then
      cert=$(sudo test -f "$home/.cloudflared/cert.pem" && echo "$home/.cloudflared/cert.pem" || echo "$home/cert.pem")
      sudo TUNNEL_ORIGIN_CERT="$cert" "$CF" tunnel route dns "$TID" "$HOST" && { DNS_OK=1; ok "DNS record created"; }
      break
    fi
  done
fi
if [ "$DNS_OK" != 1 ]; then
  warn "add this DNS record in Cloudflare (jawsweb.site > DNS > Records > Add record):"
  echo "    Type: CNAME   Name: ${HOST%%.*}   Target: ${TID:-<tunnel id>}.cfargotunnel.com   Proxy: ON (orange cloud)"
fi

echo "== 4. check"
sleep 5
code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 "https://$HOST/api/health" || echo 000)
echo "  https://$HOST/api/health -> HTTP $code"
[ "$code" = 200 ] && ok "online" || warn "not answering yet (DNS can take a minute). Try again in a minute."
