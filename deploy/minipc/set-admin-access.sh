#!/usr/bin/env bash
# Travel.with.Jaws - turn on the Cloudflare Access login for the admin console. ASCII only.
# Sets CF_ACCESS_TEAM_DOMAIN, CF_ACCESS_AUD, CONSOLE_ADMINS on the hub app (Coolify API) and restarts it.
# After this the console accepts only the allowed e-mail(s); the old id/password login is switched off.
#
# From the work PC (PowerShell):
#   $t = Read-Host "Coolify token"
#   Get-Content -LiteralPath "<repo>\deploy\minipc\set-admin-access.sh" -Raw | ssh keymedi@192.168.0.202 "COOLIFY_TOKEN='$t' TEAM='<team>.cloudflareaccess.com' AUD='<aud tag>' bash -s"
set -uo pipefail
COOLIFY_URL="${COOLIFY_URL:-http://localhost:8000}"
TOKEN="${COOLIFY_TOKEN:?COOLIFY_TOKEN is required}"
TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]\r' | sed $'s/^\xef\xbb\xbf//'); TOKEN="${TOKEN#\'}"; TOKEN="${TOKEN%\'}"
TEAM="${TEAM:?TEAM is required, e.g. keymedi.cloudflareaccess.com}"
AUD="${AUD:?AUD is required (Access application > Overview > Application Audience (AUD) Tag)}"
ADMIN_EMAIL="${ADMIN_EMAIL:-k710922@gmail.com}"
APP_NAME="${APP_NAME:-travelwithjaws-hub}"
DOMAIN="${DOMAIN:-https://travel.jawsweb.site}"
TEAM=$(printf '%s' "$TEAM" | tr -d '[:space:]\r' | sed -E 's#^https?://##; s#/.*$##')
AUD=$(printf '%s' "$AUD" | tr -d '[:space:]\r')
ok()  { printf '  [ok] %s\n' "$*"; }
die() { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }
api() {
  local m="$1" p="$2" d="${3:-}" out; out=$(mktemp)
  if [ -n "$d" ]; then
    CODE=$(curl -s -m 60 -o "$out" -w '%{http_code}' -X "$m" "$COOLIFY_URL/api/v1$p" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data "$d" || echo 000)
  else
    CODE=$(curl -s -m 60 -o "$out" -w '%{http_code}' -X "$m" "$COOLIFY_URL/api/v1$p" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" || echo 000)
  fi
  BODY=$(cat "$out"); rm -f "$out"
}

echo "== 1. check"
case "$TEAM" in *.cloudflareaccess.com) ok "team: $TEAM";; *) die "TEAM should look like <name>.cloudflareaccess.com (got: $TEAM)";; esac
[ "${#AUD}" -ge 32 ] || die "AUD tag looks too short (${#AUD} chars) - copy the whole Application Audience (AUD) Tag"
curl -sf -m 15 "https://$TEAM/cdn-cgi/access/certs" | grep -q '"keys"' && ok "Cloudflare signing keys reachable" || die "cannot read https://$TEAM/cdn-cgi/access/certs - check the team name"
api GET /applications
APP_UUID=$(python3 -c "import json,sys
try: d=json.loads(sys.argv[1])
except Exception: d=[]
print(next((a['uuid'] for a in d if a.get('name')==sys.argv[2]),''))" "$BODY" "$APP_NAME")
[ -n "$APP_UUID" ] || die "app $APP_NAME not found (HTTP $CODE)"
ok "app: $APP_UUID"
api GET "/applications/$APP_UUID/envs"
STAFF=$(python3 -c "import json,sys
try: d=json.loads(sys.argv[1])
except Exception: d=[]
v=next((e.get('value') or e.get('real_value') or '' for e in d if e.get('key')=='CONSOLE_STAFF'),'')
print(v.split(';')[0].split('|')[0].strip())" "$BODY")
[ -n "$STAFF" ] || die "CONSOLE_STAFF not set on the app - run bootstrap.sh first"
ok "admin staff id: $STAFF"

echo "== 2. set env"
setenv() {
  local j; j=$(python3 -c "import json,sys; print(json.dumps({'key':sys.argv[1],'value':sys.argv[2],'is_preview':False}))" "$1" "$2")
  api PATCH "/applications/$APP_UUID/envs" "$j"
  if [ "$CODE" != 201 ] && [ "$CODE" != 200 ]; then api POST "/applications/$APP_UUID/envs" "$j"; fi
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "setting $1 failed (HTTP $CODE): $BODY"
  ok "$1"
}
setenv CF_ACCESS_TEAM_DOMAIN "$TEAM"
setenv CF_ACCESS_AUD "$AUD"
setenv CONSOLE_ADMINS "$ADMIN_EMAIL=$STAFF"

echo "== 3. redeploy (new env is applied when the container is recreated)"
api POST "/deploy?uuid=$APP_UUID&force=false"; { [ "$CODE" = 405 ] || [ "$CODE" = 404 ]; } && api GET "/deploy?uuid=$APP_UUID&force=false"
case "$CODE" in 200|201|202) ok "deploy queued (about 1-3 minutes, build cache is reused)";; *) die "deploy failed (HTTP $CODE): $BODY";; esac
printf '  waiting'
for i in $(seq 1 40); do
  sleep 10; printf '.'
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$DOMAIN/console" || echo 000)" != 401 ] && break
done
echo
code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$DOMAIN/console" || echo 000)
ok "console without login -> HTTP $code (302 = Cloudflare login page, 403 = Access app not covering /console yet)"
echo
echo "  Open $DOMAIN and press the admin button (top right). Cloudflare mails a code to $ADMIN_EMAIL."
exit 0
