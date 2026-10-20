#!/usr/bin/env bash
# Travel.with.Jaws - load or remove the sample (demo) data on the mini PC. ASCII only.
# Runs trip.load_demo() / trip.remove_demo() inside the running hub container (it has psql + DATABASE_URL).
# Demo rows go through the same rights / evidence / approval rules and carry a "sample" badge on screen.
#
# From the work PC (PowerShell):
#   load:    Get-Content -LiteralPath "<repo>\deploy\minipc\demo-data.sh" -Raw | ssh keymedi@192.168.0.202 "bash -s"
#   remove:  Get-Content -LiteralPath "<repo>\deploy\minipc\demo-data.sh" -Raw | ssh keymedi@192.168.0.202 "ACTION=remove bash -s"
set -uo pipefail
ACTION="${ACTION:-load}"
APP_UUID="${APP_UUID:-3e80seki9tdgpqplgyzptl12}"
DOMAIN="${DOMAIN:-https://travel.jawsweb.site}"
ok()  { printf '  [ok] %s\n' "$*"; }
die() { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }

DOCKER=""
if docker ps >/dev/null 2>&1; then DOCKER=docker; elif sudo -n docker ps >/dev/null 2>&1; then DOCKER="sudo -n docker"; fi
[ -n "$DOCKER" ] || die "no docker access for $(whoami)"

C=$($DOCKER ps --format '{{.Names}}' | grep "^$APP_UUID" | head -1)
[ -n "$C" ] || die "hub container ($APP_UUID) is not running"
ok "hub container: $C"

q() { $DOCKER exec "$C" sh -c "psql \"\$DATABASE_URL\" -v ON_ERROR_STOP=1 -qAtc \"$1\""; }

# wait until the new migration (006_demo) is applied by the latest deploy
for i in $(seq 1 30); do
  has=$(q "select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'trip' and p.proname = 'load_demo'" 2>/dev/null || echo 0)
  [ "$has" = 1 ] && break
  [ "$i" = 1 ] && printf '  waiting for the new version to deploy'
  printf '.'; sleep 20
  C=$($DOCKER ps --format '{{.Names}}' | grep "^$APP_UUID" | head -1)
done
echo
[ "$has" = 1 ] || die "migration 006_demo is not applied yet - check Coolify > travelwithjaws-hub > Deployments"

case "$ACTION" in
  load)   r=$(q "select trip.load_demo()") || die "load failed";;
  remove) r=$(q "select trip.remove_demo()") || die "remove failed";;
  *) die "ACTION must be load or remove";;
esac
ok "$r"
code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 "$DOMAIN/" || echo 000)
ok "portal: $DOMAIN (HTTP $code)"
exit 0
