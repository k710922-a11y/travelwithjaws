#!/usr/bin/env bash
# Travel.with.Jaws - set (or change) the admin console password. ASCII only.
# Stores only a PBKDF2 hash (never the password) in the hub app env via the Coolify API, rotates the
# session secret (everyone logged in is logged out), then redeploys. Login: /admin-login with ADMIN_EMAIL.
#
# From the work PC (PowerShell) - the password is typed hidden and sent base64-encoded:
#   $t = Read-Host "Coolify token"
#   $s = Read-Host "New admin password" -AsSecureString
#   $p = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))))
#   Get-Content -LiteralPath "<repo>\deploy\minipc\set-admin-password.sh" -Raw | ssh keymedi@192.168.0.202 "COOLIFY_TOKEN='$t' ADMIN_PASS_B64='$p' bash -s"
set -uo pipefail
COOLIFY_URL="${COOLIFY_URL:-http://localhost:8000}"
TOKEN="${COOLIFY_TOKEN:?COOLIFY_TOKEN is required}"
TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]\r' | sed $'s/^\xef\xbb\xbf//'); TOKEN="${TOKEN#\'}"; TOKEN="${TOKEN%\'}"
ADMIN_EMAIL="${ADMIN_EMAIL:-k710922@gmail.com}"
APP_NAME="${APP_NAME:-travelwithjaws-hub}"
DOMAIN="${DOMAIN:-https://travel.jawsweb.site}"
B64=$(printf '%s' "${ADMIN_PASS_B64:?ADMIN_PASS_B64 is required}" | tr -d '[:space:]\r')
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

echo "== 1. password"
HASH=$(B64="$B64" python3 - <<'PY'
import os, sys, base64, hashlib
try:
    pw = base64.b64decode(os.environ["B64"]).decode("utf-8")
except Exception:
    sys.exit("could not read the password (base64)")
pw = pw.rstrip("\r\n")
if len(pw) < 10: sys.exit("password must be at least 10 characters")
if pw.lower() == pw or pw.upper() == pw or not any(c.isdigit() for c in pw):
    sys.exit("use upper and lower case letters and at least one digit")
salt = os.urandom(16); it = 310000
h = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, it, 32)
u = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
print(f"pbkdf2_sha256:{it}:{u(salt)}:{u(h)}")
PY
) || die "password rejected"
SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")
ok "hashed (PBKDF2-SHA256, 310000 rounds) - the password itself is not stored"

echo "== 2. hub app"
api GET /applications
APP_UUID=$(python3 -c "import json,sys
try: d=json.loads(sys.argv[1])
except Exception: d=[]
print(next((a['uuid'] for a in d if a.get('name')==sys.argv[2]),''))" "$BODY" "$APP_NAME")
[ -n "$APP_UUID" ] || die "app $APP_NAME not found (HTTP $CODE) - check the token"
ok "app: $APP_UUID"
api GET "/applications/$APP_UUID/envs"
STAFF=$(python3 -c "import json,sys
try: d=json.loads(sys.argv[1])
except Exception: d=[]
v=next((e.get('value') or e.get('real_value') or '' for e in d if e.get('key')=='CONSOLE_STAFF'),'')
print(v.split(';')[0].split('|')[0].strip())" "$BODY")
[ -n "$STAFF" ] || die "CONSOLE_STAFF not set on the app - run bootstrap.sh first"
ok "admin staff id: $STAFF"

setenv() {
  local j; j=$(python3 -c "import json,sys; print(json.dumps({'key':sys.argv[1],'value':sys.argv[2],'is_preview':False,'is_literal':True}))" "$1" "$2")
  api PATCH "/applications/$APP_UUID/envs" "$j"
  if [ "$CODE" != 201 ] && [ "$CODE" != 200 ]; then
    j=$(python3 -c "import json,sys; print(json.dumps({'key':sys.argv[1],'value':sys.argv[2],'is_preview':False}))" "$1" "$2")
    api PATCH "/applications/$APP_UUID/envs" "$j"
    if [ "$CODE" != 201 ] && [ "$CODE" != 200 ]; then api POST "/applications/$APP_UUID/envs" "$j"; fi
  fi
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "setting $1 failed (HTTP $CODE): $BODY"
  ok "$1"
}
setenv ADMIN_EMAIL "$ADMIN_EMAIL"
setenv ADMIN_PASSWORD_HASH "$HASH"
setenv ADMIN_SESSION_SECRET "$SECRET"
setenv ADMIN_STAFF "$STAFF"

echo "== 3. redeploy (new settings apply when the container is recreated)"
api POST "/deploy?uuid=$APP_UUID&force=false"; { [ "$CODE" = 405 ] || [ "$CODE" = 404 ]; } && api GET "/deploy?uuid=$APP_UUID&force=false"
case "$CODE" in 200|201|202) ok "deploy queued";; *) die "deploy failed (HTTP $CODE): $BODY";; esac
printf '  waiting'
for i in $(seq 1 40); do
  sleep 10; printf '.'
  loc=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -m 10 "$DOMAIN/console" || true)
  case "$loc" in 307*admin-login*|308*admin-login*) break;; esac
done
echo
case "$loc" in *admin-login*) ok "login screen is live: $DOMAIN/admin-login";; *) printf '  [!] not switched yet (%s) - check Coolify > %s > Deployments\n' "$loc" "$APP_NAME";; esac
echo "  Log in with $ADMIN_EMAIL and the password you just typed. The old id/password prompt is now off."
exit 0
